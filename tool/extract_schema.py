# Copyright © 2026 Apple Inc. and the creator_studio_document authors.
# Licensed under Apache License v2.0. For more information, see LICENSE.
# SPDX-License-Identifier: Apache-2.0
"""Extracts the model schema from the upstream Python package into tool/schema.json.

Run with a Python environment where `creator_studio_doc_format` (the upstream
apple/creator-studio-doc-format package) is installed:

    python -I tool/extract_schema.py [output path]

The script introspects every class in `core._MODEL_FOR` and every enum reachable from
their field annotations. Anything it can't classify makes it fail loudly: a silent skip
would make the Dart models drift from upstream without anyone noticing.
"""

from __future__ import annotations

import inspect
import json
import re
import sys
import types
import typing
import unicodedata
from enum import Enum
from importlib.metadata import version as dist_version
from pathlib import Path
from typing import Any

import annotated_types
from pydantic import BaseModel, Strict
from pydantic.fields import FieldInfo
from pydantic_core import PydanticUndefined

from creator_studio_doc_format import core
from creator_studio_doc_format.core import _MODEL_FOR, ObjectModel, TaggedUnionModel
from creator_studio_doc_format.core._preset import _annotation_is_enum
from creator_studio_doc_format.core._wire import Override

_KINDS = {"req", "def", "opt", "ovr", "ovrdef"}


class ExtractError(Exception):
    pass


def fail(where: str, message: str) -> typing.NoReturn:
    raise ExtractError(f"{where}: {message}")


_MODEL_NAMES: dict[type, str] = {}
_ENUMS: dict[str, type[Enum]] = {}


def _doc(obj: Any) -> str:
    return inspect.cleandoc(obj.__doc__ or "")


def classify(annotation: Any, where: str) -> dict[str, Any]:
    """Returns the structured type tree for an annotation, or fails."""
    origin = typing.get_origin(annotation)
    args = typing.get_args(annotation)
    if origin in (typing.Union, types.UnionType):
        members = [a for a in args if a is not type(None)]
        if len(members) != 1 or len(args) != 2:
            fail(where, f"unsupported union {annotation!r}")
        return {"kind": "nullable", "of": classify(members[0], where)}
    if origin is list:
        if len(args) != 1:
            fail(where, f"unsupported list {annotation!r}")
        return {"kind": "list", "of": classify(args[0], where)}
    if origin is Override:
        if len(args) != 1:
            fail(where, f"unsupported Override {annotation!r}")
        inner = classify(args[0], where)
        if inner["kind"] == "enum":
            # `Override.__get_pydantic_core_schema__` marks a directly wrapped enum
            # schema `strict: False`.
            inner = {**inner, "strict": False}
        return {"kind": "override", "of": inner}
    if origin is typing.Annotated:
        base, *meta = args
        node = classify(base, where)
        for m in meta:
            if isinstance(m, Strict) and m.strict is False and node["kind"] == "enum":
                node = {**node, "strict": False}
            else:
                fail(where, f"unsupported Annotated metadata {m!r} on {base!r}")
        return node
    if origin is typing.Literal:
        if args == (True,):
            return {"kind": "literal_true"}
        fail(where, f"unsupported Literal {annotation!r}")
    if origin is not None:
        fail(where, f"unsupported generic {annotation!r}")
    if annotation is bool:
        return {"kind": "bool"}
    if annotation is int:
        return {"kind": "int"}
    if annotation is float:
        return {"kind": "float"}
    if annotation is str:
        return {"kind": "str"}
    if isinstance(annotation, type) and issubclass(annotation, Enum):
        if not issubclass(annotation, str):
            fail(where, f"enum {annotation.__name__} isn't a str enum")
        _ENUMS[annotation.__name__] = annotation
        return {"kind": "enum", "name": annotation.__name__, "strict": True}
    if isinstance(annotation, type) and issubclass(annotation, BaseModel):
        name = _MODEL_NAMES.get(annotation)
        if name is None:
            fail(where, f"model {annotation!r} isn't in _MODEL_FOR")
        return {"kind": "model", "name": name}
    fail(where, f"unclassifiable annotation {annotation!r}")


def _leaves(node: dict[str, Any]) -> list[dict[str, Any]]:
    if "of" in node:
        return _leaves(node["of"])
    return [node]


def _set_enum_lax(node: dict[str, Any], where: str) -> dict[str, Any]:
    # `Field(strict=False)` reaches an enum at the top or under `| None`, but not
    # the items of a list, which need `Annotated[E, Strict(False)]` instead.
    if node["kind"] == "nullable":
        return {**node, "of": _set_enum_lax(node["of"], where)}
    if node["kind"] == "enum":
        return {**node, "strict": False}
    fail(where, f"strict=False on a {node['kind']} doesn't reach an enum")


def _json_number(value: Any, where: str) -> int | float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        fail(where, f"non-numeric constraint {value!r}")
    return value


def field_metadata(info: FieldInfo, where: str) -> tuple[dict[str, Any], bool | None]:
    constraints: dict[str, Any] = {}
    strict: bool | None = None
    for m in info.metadata:
        if isinstance(m, annotated_types.Ge):
            constraints["ge"] = _json_number(m.ge, where)
        elif isinstance(m, annotated_types.Le):
            constraints["le"] = _json_number(m.le, where)
        elif isinstance(m, annotated_types.Gt):
            constraints["gt"] = _json_number(m.gt, where)
        elif isinstance(m, annotated_types.Lt):
            constraints["lt"] = _json_number(m.lt, where)
        elif isinstance(m, annotated_types.MinLen):
            constraints["min_length"] = m.min_length
        elif isinstance(m, annotated_types.MaxLen):
            constraints["max_length"] = m.max_length
        elif isinstance(m, Strict):
            strict = m.strict
        else:
            fail(where, f"unsupported field metadata {m!r}")
    for attr in ("alias", "validation_alias", "serialization_alias", "discriminator"):
        if getattr(info, attr, None) is not None:
            fail(where, f"unsupported field attribute {attr}={getattr(info, attr)!r}")
    if info.frozen:
        fail(where, "frozen fields aren't supported")
    return constraints, strict


def _check_constraints(
    constraints: dict[str, Any], type_tree: dict[str, Any], where: str
) -> None:
    node = type_tree["of"] if type_tree["kind"] == "nullable" else type_tree
    numeric = {"ge", "le", "gt", "lt"} & constraints.keys()
    lengths = {"min_length", "max_length"} & constraints.keys()
    if numeric and node["kind"] not in ("int", "float"):
        fail(where, f"numeric constraints on {node['kind']}")
    if lengths and node["kind"] != "list":
        fail(where, f"length constraints on {node['kind']}")


def default_json(cls: type, wk: str, info: FieldInfo, where: str) -> Any:
    """Returns the field's default as JSON, or fails if it can't be represented."""
    if info.default_factory is not None:
        value = info.default_factory()  # type: ignore[call-arg]
    elif info.default is PydanticUndefined:
        fail(where, "default requested for a field without one")
    else:
        value = info.default
    if isinstance(value, Override):
        if not value.is_not_set:
            return {"override": "value", "value": _to_json(value.get(), where)}
        return {"override": "not_set"}
    return _to_json(value, where)


def _to_json(value: Any, where: str) -> Any:
    if value is None or isinstance(value, (bool, int, float, str)):
        if isinstance(value, float) and value != value:
            fail(where, "NaN default")
        return value
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, list):
        return [_to_json(v, where) for v in value]
    if isinstance(value, BaseModel):
        dumped = value.model_dump(mode="json")
        again = type(value).model_validate(dumped)
        if again != value or again.model_dump(mode="json") != dumped:
            fail(where, f"default {value!r} doesn't round-trip through JSON")
        return dumped
    fail(where, f"unsupported default {value!r}")


def extract_object(cls: type[ObjectModel], name: str) -> dict[str, Any]:
    specs = cls.__wire_fields__
    declared = [k for k in cls.model_fields if k != "preset_identifier"]
    if [wk for wk, _a, _k in specs] != declared:
        fail(name, f"wire fields {specs} don't match declared fields {declared}")
    fields = []
    for wk, added, kind in specs:
        where = f"{name}.{wk}"
        if kind not in _KINDS:
            fail(where, f"unknown field kind {kind!r}")
        info = cls.model_fields[wk]
        type_tree = classify(info.annotation, where)
        constraints, strict = field_metadata(info, where)
        if strict is False:
            if any(leaf["kind"] != "enum" for leaf in _leaves(type_tree)):
                fail(where, "strict=False on a field with non-enum leaves")
            type_tree = _set_enum_lax(type_tree, where)
        elif strict is True:
            fail(where, "explicit strict=True isn't supported")
        _check_constraints(constraints, type_tree, where)
        is_override = type_tree["kind"] == "override"
        if is_override != (kind in ("ovr", "ovrdef")):
            fail(where, f"kind {kind!r} doesn't match annotation {info.annotation!r}")
        if (kind == "opt") != (type_tree["kind"] == "nullable"):
            fail(where, f"kind {kind!r} doesn't match annotation {info.annotation!r}")
        if kind == "req" and not info.is_required():
            fail(where, "req field has a default")
        if kind != "req" and info.is_required():
            fail(where, f"{kind} field has no default")
        field: dict[str, Any] = {
            "name": wk,
            "version_added": list(added),
            "kind": kind,
            "type": type_tree,
        }
        if kind == "opt" and (info.default is not None or info.default_factory):
            fail(where, "opt field with a non-None default")
        if kind in ("def", "ovrdef"):
            field["default"] = default_json(cls, wk, info, where)
        if kind == "ovr":
            if default_json(cls, wk, info, where) != {"override": "not_set"}:
                fail(where, "ovr field whose default isn't Override.not_set()")
        if kind == "ovrdef":
            if field["default"].get("override") != "value":
                fail(where, "ovrdef field whose default isn't Override.value(...)")
        annotation = cls._preset_annotation(wk, kind)
        field["preset_gate_lax"] = _annotation_is_enum(annotation)
        if field["preset_gate_lax"]:
            gate_tree = type_tree["of"] if is_override else type_tree
            if any(leaf["kind"] != "enum" for leaf in _leaves(gate_tree)):
                fail(where, "a lax preset gate over non-enum leaves")
        if constraints:
            field["constraints"] = constraints
        field["description"] = info.description or ""
        fields.append(field)
    return {
        "name": name,
        "kind": "object",
        "type_id": cls.__wire_type_id__,
        "version": cls.__wire_version__,
        "doc": _doc(cls),
        "fields": fields,
    }


def extract_union(cls: type[TaggedUnionModel], name: str) -> dict[str, Any]:
    specs = cls.__wire_cases__
    declared = [k for k in cls.model_fields if k != "preset_identifier"]
    if sorted(wn for wn, _a, _v in specs) != sorted(declared):
        fail(name, f"cases {specs} don't match declared fields {declared}")
    cases = []
    for wn, added, valueless in specs:
        where = f"{name}.{wn}"
        info = cls.model_fields[wn]
        type_tree = classify(info.annotation, where)
        constraints, strict = field_metadata(info, where)
        if constraints or strict is not None:
            fail(where, "constraints on a union case")
        if type_tree["kind"] != "nullable" or info.default is not None:
            fail(where, f"case annotation {info.annotation!r} isn't optional")
        payload = type_tree["of"]
        if valueless != (payload["kind"] == "literal_true"):
            fail(where, f"valueless={valueless} doesn't match {info.annotation!r}")
        case: dict[str, Any] = {
            "name": wn,
            "version_added": list(added),
            "valueless": valueless,
        }
        if not valueless:
            case["type"] = payload
        case["preset_gate_lax"] = _annotation_is_enum(info.annotation)
        if case["preset_gate_lax"]:
            fail(where, "enum-typed union cases aren't supported")
        case["description"] = info.description or ""
        cases.append(case)
    return {
        "name": name,
        "kind": "union",
        "type_id": cls.__wire_type_id__,
        "version": cls.__wire_version__,
        "doc": _doc(cls),
        "cases": cases,
    }


# A member line of an enum docstring, `<wire value> — <description>`, at any
# indentation. Python 3.13 and later dedent `__doc__` at compile time, so the
# indentation left on a member line depends on the other lines: none when every
# line had the same, and upstream indents the list by three or four spaces. A
# prose line of this shape names no member, so it fails as an unknown member.
_MEMBER_LINE = re.compile(r"^[ \t]*(\S+) — (.*)$")


def extract_enum(cls: type[Enum]) -> dict[str, Any]:
    name = cls.__name__
    raw = inspect.cleandoc(cls.__doc__ or "")
    member_docs: dict[str, str] = {}
    lines = raw.splitlines()
    doc_lines: list[str] = []
    for line in lines:
        m = _MEMBER_LINE.match(line)
        if m is not None:
            member_docs[m.group(1)] = m.group(2).strip()
        elif not member_docs:
            doc_lines.append(line)
        elif line.strip():
            fail(name, f"unexpected docstring line after the member list: {line!r}")
    doc = inspect.cleandoc("\n".join(doc_lines)) if member_docs else raw
    members = []
    for member in cls:
        if not isinstance(member.value, str):
            fail(f"{name}.{member.name}", "non-string enum value")
        members.append(
            {
                "name": member.name,
                "value": member.value,
                "doc": member_docs.pop(member.value, ""),
            }
        )
    if member_docs:
        fail(name, f"docstring documents unknown members {sorted(member_docs)}")
    return {"name": name, "kind": "enum", "doc": doc, "members": members}


def python_repr() -> dict[str, Any]:
    """Returns what the Dart port needs to quote strings as Python's ``repr`` does.

    Upstream's messages and warnings quote values with ``repr``, which escapes every
    code point that ``str.isprintable`` rejects. Dart has no Unicode category data, so
    the table of those code points comes from the Python that runs the extractor.
    """
    ranges: list[list[int]] = []
    start = None
    for cp in range(sys.maxunicode + 2):
        printable = cp <= sys.maxunicode and chr(cp).isprintable()
        if not printable and start is None:
            start = cp
        elif printable and start is not None:
            ranges.append([start, cp - 1])
            start = None
    if start is not None:
        ranges.append([start, sys.maxunicode])
    # The escapes the Dart side hard-codes rely on these.
    if not (ranges[0] == [0, 31] and ranges[1][0] == 0x7F and " ".isprintable()):
        fail("python_repr", f"unexpected unprintable ranges {ranges[:2]}")
    return {
        "python": ".".join(map(str, sys.version_info[:3])),
        "unicode": unicodedata.unidata_version,
        # Inclusive ranges of code points in hex, `first-last` or a lone `cp`.
        "unprintable": [f"{a:x}" if a == b else f"{a:x}-{b:x}" for a, b in ranges],
    }


def python_nfc() -> dict[str, Any]:
    """Returns what the Dart port needs to normalize strings to NFC.

    ``ResourceStore`` matches a resource name to its key by canonical equivalence, as
    ``unicodedata.normalize("NFC", ...)`` does, and Dart has no Unicode normalization
    of its own, so the tables come from the Python that runs the extractor: canonical
    combining classes, one-level canonical decompositions, and the composition
    exclusions that the Dart side can't derive from those two.
    """

    def combining(cp: int) -> int:
        return unicodedata.combining(chr(cp))

    ccc: list[list[int]] = []
    decompositions: list[str] = []
    excluded: list[int] = []
    derived: set[int] = set()
    for cp in range(sys.maxunicode + 1):
        if (c := combining(cp)) != 0:
            if ccc and ccc[-1][1] == cp - 1 and ccc[-1][2] == c:
                ccc[-1][1] = cp
            else:
                ccc.append([cp, cp, c])
        d = unicodedata.decomposition(chr(cp))
        if not d or d.startswith("<"):
            continue
        parts = [int(x, 16) for x in d.split()]
        if not 1 <= len(parts) <= 2:
            fail("python_nfc", f"U+{cp:04X} decomposes to {len(parts)} code points")
        decompositions.append(f"{cp:x}:" + ".".join(f"{x:x}" for x in parts))
        # What Full_Composition_Exclusion holds beyond the explicit exclusions.
        if len(parts) == 1 or combining(cp) != 0 or combining(parts[0]) != 0:
            derived.add(cp)
        if unicodedata.normalize("NFC", chr(cp)) != chr(cp) and cp not in derived:
            excluded.append(cp)
    # The Dart side composes Hangul syllables algorithmically.
    if unicodedata.decomposition("\uac00") or unicodedata.normalize(
        "NFC", "\u1100\u1161\u11a8"
    ) != "\uac01":
        fail("python_nfc", "unexpected Hangul decomposition")
    # Every derived exclusion must be one that NFC actually applies.
    for cp in derived:
        if unicodedata.normalize("NFC", chr(cp)) == chr(cp):
            fail("python_nfc", f"U+{cp:04X} composes but looks excluded")
    return {
        "python": ".".join(map(str, sys.version_info[:3])),
        "unicode": unicodedata.unidata_version,
        # Inclusive ranges with their class, `first-last:class` in hex.
        "combining": [
            f"{a:x}:{c:x}" if a == b else f"{a:x}-{b:x}:{c:x}" for a, b, c in ccc
        ],
        # `cp:part` or `cp:first.second` in hex, one level deep.
        "decompositions": decompositions,
        # Code points in hex whose two-part decomposition doesn't compose.
        "exclusions": [f"{cp:x}" for cp in excluded],
    }


def python_layout_name_key() -> dict[str, Any]:
    """Returns what the Dart port needs, beyond ``python_nfc``, to match layout names.

    Upstream's ``layout_name_key`` folds a name with ``str.casefold`` and normalizes
    it to NFKD and NFKC. The tables are the one-level compatibility decompositions,
    which the Dart side applies together with the canonical ones in ``python_nfc``,
    and the full case foldings of single code points. The function checks that the
    Dart algorithm reproduces Python's NFKD and ``casefold`` for every code point.
    """
    compat: dict[int, list[int]] = {}
    canonical: dict[int, list[int]] = {}
    folds: list[str] = []
    for cp in range(sys.maxunicode + 1):
        d = unicodedata.decomposition(chr(cp))
        if d:
            fields = d.split()
            target = compat if fields[0].startswith("<") else canonical
            if fields[0].startswith("<"):
                fields = fields[1:]
            if not fields:
                fail("python_layout_name_key", f"U+{cp:04X} decomposes to nothing")
            target[cp] = [int(x, 16) for x in fields]
        if 0xD800 <= cp <= 0xDFFF:
            continue
        folded = chr(cp).casefold()
        if folded != chr(cp):
            folds.append(f"{cp:x}:" + ".".join(f"{ord(c):x}" for c in folded))

    def decompose(cp: int, out: list[int]) -> None:
        if 0xAC00 <= cp < 0xAC00 + 11172:
            out.extend(ord(c) for c in unicodedata.normalize("NFD", chr(cp)))
            return
        parts = compat.get(cp) or canonical.get(cp)
        if parts is None:
            out.append(cp)
            return
        for p in parts:
            decompose(p, out)

    for cp in range(sys.maxunicode + 1):
        if 0xD800 <= cp <= 0xDFFF:
            continue
        got: list[int] = []
        decompose(cp, got)
        # Canonical reordering, as the Dart side runs it.
        for i in range(1, len(got)):
            j = i
            while j > 0:
                prev = unicodedata.combining(chr(got[j - 1]))
                cc = unicodedata.combining(chr(got[j]))
                if cc == 0 or prev == 0 or prev <= cc:
                    break
                got[j], got[j - 1] = got[j - 1], got[j]
                j -= 1
        if "".join(map(chr, got)) != unicodedata.normalize("NFKD", chr(cp)):
            fail("python_layout_name_key", f"U+{cp:04X} decomposes unexpectedly")
    # `casefold` must fold a string one code point at a time.
    sample = "".join(chr(cp) for cp in range(0x2000) if not 0xD800 <= cp <= 0xDFFF)
    if sample.casefold() != "".join(c.casefold() for c in sample) or (
        "ΣΑΣ".casefold() != "σασ"
    ):
        fail("python_layout_name_key", "casefold depends on context")
    return {
        "python": ".".join(map(str, sys.version_info[:3])),
        "unicode": unicodedata.unidata_version,
        # `cp:first.second...` in hex, one level deep, without the `<tag>`.
        "compatibility": [
            f"{cp:x}:" + ".".join(f"{x:x}" for x in parts)
            for cp, parts in sorted(compat.items())
        ],
        # `cp:first.second...` in hex: what `str.casefold` maps a code point to.
        "casefold": folds,
    }


def extract() -> dict[str, Any]:
    for tid, cls in _MODEL_FOR.items():
        if getattr(cls, "__wire_type_id__", None) != tid:
            fail(cls.__name__, f"type id {cls.__wire_type_id__!r} != {tid!r}")
        if getattr(core, cls.__name__, None) is not cls:
            fail(cls.__name__, "isn't exported from core under its own name")
        _MODEL_NAMES[cls] = cls.__name__
    if len(set(_MODEL_NAMES.values())) != len(_MODEL_FOR):
        fail("_MODEL_FOR", "duplicate class names")
    models = []
    for cls in sorted(_MODEL_FOR.values(), key=lambda c: c.__name__):
        name = cls.__name__
        if issubclass(cls, ObjectModel):
            models.append(extract_object(cls, name))
        elif issubclass(cls, TaggedUnionModel):
            models.append(extract_union(cls, name))
        else:
            fail(name, "neither an ObjectModel nor a TaggedUnionModel")
    enums = [extract_enum(_ENUMS[n]) for n in sorted(_ENUMS)]
    # Every enum the package exports must be reachable from a field.
    exported = {
        n
        for n in core.__all__
        if isinstance(c := getattr(core, n), type)
        and issubclass(c, Enum)
        and c.__module__.endswith(".models")
    }
    if exported != set(_ENUMS):
        fail("enums", f"exported but unreachable: {sorted(exported - set(_ENUMS))}")
    if len(models) != len(_MODEL_FOR):
        fail("models", f"{len(models)} extracted, {len(_MODEL_FOR)} expected")
    return {
        "source": {
            "distribution": "creator-studio-doc-format",
            "version": dist_version("creator-studio-doc-format"),
        },
        "counts": {
            "models": len(models),
            "objects": sum(m["kind"] == "object" for m in models),
            "unions": sum(m["kind"] == "union" for m in models),
            "enums": len(enums),
        },
        "models": models,
        "enums": enums,
        "python_repr": python_repr(),
        "python_nfc": python_nfc(),
        "python_layout_name_key": python_layout_name_key(),
    }


def main() -> None:
    out = (
        Path(sys.argv[1])
        if len(sys.argv) > 1
        else Path(__file__).resolve().parent / "schema.json"
    )
    schema = extract()
    text = json.dumps(schema, indent=2, ensure_ascii=False, sort_keys=True) + "\n"
    out.write_text(text, encoding="utf-8")
    c = schema["counts"]
    print(
        f"wrote {out}: {c['models']} models ({c['objects']} objects, "
        f"{c['unions']} unions), {c['enums']} enums",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
