# Copyright © 2026 Apple Inc. and the creator_studio_document authors.
# Licensed under Apache License v2.0. For more information, see LICENSE.
# SPDX-License-Identifier: Apache-2.0
"""Differential cases for the wire codec, evaluated by the upstream Python package.

Each case decodes `input` as the model `type`, optionally with presets, applies
`ops`, then encodes. `tool/make_expected.py` records what upstream does in
`test/fixtures/expected/wire_cases.json`, and `test/core/wire_cases_test.dart`
checks that the Dart port does the same.

A case is a dict with:

- `name`, `type` (an upstream class name), `input` (JSON).
- `presets`: preset entries as `presets.json` stores them. When present, both
  decoding and encoding get a `PresetRegistry`.
- `strict`: decode with `wire_presets_strict`.
- `encode_without_presets`: encode with no context even though presets exist.
- `ops`: edits between decoding and encoding. Each has `path` (a list of field
  names and list indexes from the root; an `Override` on the way is unwrapped)
  and one of:
  - `{"set": key, "json": value}`: assigns the JSON value to the field, which
    validates it like an assignment does.
  - `{"touch": key}`: assigns the field its own value.
  - `{"extra": key, "json": value}`: sets an unknown key.
  - `{"preset_identifier": value}`: sets `preset_identifier`.
"""

from __future__ import annotations

import copy
import logging
import warnings
from typing import Any

from pydantic import ValidationError
from pydantic_core import PydanticSerializationError

from creator_studio_doc_format import core
from creator_studio_doc_format.core import (
    DocumentVersionError,
    Override,
    Preset,
    PresetRegistry,
    TaggedUnionModel,
)

SIZE = "com.apple.apps.content-language.size"
RGBA = "com.apple.apps.content-language.color.rgba"
SHAPE = "com.apple.apps.content-language.shape"


def _rgba(**kw: Any) -> dict[str, Any]:
    return {"rgba": kw}


def _fill(**rgba: Any) -> dict[str, Any]:
    return {"color": _rgba(**rgba)}


def cases() -> list[dict[str, Any]]:  # noqa: PLR0915 -- a flat list of cases
    c: list[dict[str, Any]] = []

    def add(name: str, type_: str, input_: Any, **kw: Any) -> None:
        c.append({"name": name, "type": type_, "input": input_, **kw})

    # -- strict scalar typing ------------------------------------------------
    add("size floats", "Size", {"width": 100.0, "height": 50.5})
    add("size ints become floats", "Size", {"width": 100, "height": 50})
    add("size bool rejected", "Size", {"width": True, "height": 1.0})
    add("size string rejected", "Size", {"width": "1", "height": 1.0})
    add("size missing required", "Size", {"width": 1.0})
    add("size null required", "Size", {"width": None, "height": 1.0})
    add("size not an object", "Size", [1, 2])
    add("size string input", "Size", "big")
    add("table int rejects float", "Table", {"number_of_columns": 1.0, "number_of_rows": 2})
    add("table int rejects bool", "Table", {"number_of_columns": False, "number_of_rows": 2})
    add("table ints", "Table", {"number_of_columns": 3, "number_of_rows": 2, "default_column_width": 50})
    add("label bool rejects int", "Label", {"is_visible": 1})
    add("shape str rejects int", "Shape", {"identifier": 5})
    add("shape nested wrong type", "Shape", {"geometry": "x"})
    add("shape nested missing", "Shape", {"geometry": {"position": {"x": 1, "y": 2}}})
    add("group children not list", "Group", {"children": "x"})
    add("group children empty", "Group", {"children": []})
    add(
        "group children item errors",
        "Group",
        {"children": [{"shape": {}}, 5, {"shape": {"identifier": 3}}]},
    )
    add("unequal columns too long", "UnequalColumnsDescription", {"column_widths": [10.0] * 11})
    add("unequal columns ok", "UnequalColumnsDescription", {"column_widths": [10, 20.5], "gutter_widths": [1]})
    add("unequal gutter too short", "UnequalColumnsDescription", {"column_widths": [10], "gutter_widths": []})
    add("rgba bounds", "RGBA", {"red": 5.0, "green": -1, "blue": 0.5, "alpha": 1})
    add("rgba ok", "RGBA", {"red": 1, "green": 0.25, "blue": 0, "headroom": 2})
    add("equal columns int bounds", "EqualColumnsDescription", {"count": 11, "gutter_width": 80})
    add("shadow drop bounds", "DropShadow", {"angle": 400, "radius": -1})

    # -- enums ---------------------------------------------------------------
    add("shape enum wire string", "Shape", {"head": "filled_arrow", "tail": "open_circle"})
    add("shape enum unknown", "Shape", {"head": "nope"})
    add("shape enum int", "Shape", {"head": 3})
    add("cell enum opt", "CellProperties", {"vertical_alignment": "middle"})
    add("paragraph override enum", "ParagraphProperties", {"alignment": "center", "decimal_tab": None})
    add("paragraph override enum bad", "ParagraphProperties", {"alignment": "sideways"})
    add("tab stop enum", "TabStopType", {"position": 1, "kind": "decimal"})
    add("series list enum", "ChartSeries", {"fill_reuse_rules": ["fill_from_stroke"]})

    # -- defaults, nulls, overrides -------------------------------------------
    add("shape def null takes default", "Shape", {"head": None, "opacity": None})
    add("shape def set to default", "Shape", {"aspect_ratio_locked": False, "opacity": 1})
    add("shape opt null not written", "Shape", {"identifier": None, "geometry": None})
    add("cell override cleared", "CellProperties", {"fill": None})
    add("cell override value", "CellProperties", {"fill": _fill(red=0.5)})
    add("cell override bad value", "CellProperties", {"fill": {"nope": {}}})
    add("shape default model untouched", "Shape", {"stroke": {"line": {}}})
    add("shape default model changed", "Shape", {"stroke": "empty"})
    add("image default union", "Image", {"resource": {"indirect": {"filename": "a.png"}}, "stroke": "empty"})

    # -- unknown keys ----------------------------------------------------------
    add(
        "size unknown keys in order",
        "Size",
        {"zeta": 1, "width": 1.0, "alpha": {"x": [1, 2.5, None]}, "height": 2.0, "type_identifier": "bogus"},
    )
    add("preset id null", "Size", {"width": 1.0, "height": 2.0, "preset_identifier": None})
    add("preset id wrong type", "Size", {"width": 1.0, "height": 2.0, "preset_identifier": 7})

    # -- versions -----------------------------------------------------------------
    add("size version map", "Size", {"width": 1.0, "height": 2.0, "version": {"major": 1, "minor": 0}})
    add("size version int", "Size", {"width": 1.0, "height": 2.0, "version": 1})
    add("size version bad", "Size", {"width": 1.0, "height": 2.0, "version": "1.x"})
    add("size version null", "Size", {"width": 1.0, "height": 2.0, "version": None})
    add("size version newer major", "Size", {"width": 1.0, "height": 2.0, "version": "2.0"})
    add("size newer minor no extras", "Size", {"width": 1.0, "height": 2.0, "version": "1.7"})
    add("size floor holds", "Size", {"width": 1.0, "height": 2.0, "version": "1.7", "depth": 3})
    add(
        "size floor edited",
        "Size",
        {"width": 1.0, "height": 2.0, "version": "1.7", "depth": 3},
        ops=[{"path": [], "set": "width", "json": 5}],
    )
    add(
        "size floor touched",
        "Size",
        {"width": 1.0, "height": 2.0, "version": "1.7", "depth": 3},
        ops=[{"path": [], "touch": "width"}],
    )
    add(
        "size floor extra edited",
        "Size",
        {"width": 1.0, "height": 2.0, "version": "1.7", "depth": 3},
        ops=[{"path": [], "extra": "depth", "json": 4}],
    )
    add(
        "indirect too new key dropped",
        "IndirectResource",
        {"filename": "a.png", "version": "1.0", "premium_resource_info": {"asset_uuid": "u", "is_derived_asset": False, "may_need_watermark": True}},
    )
    add(
        "indirect new key kept",
        "IndirectResource",
        {"filename": "a.png", "version": "2.0", "premium_resource_info": {"asset_uuid": "u", "is_derived_asset": False, "may_need_watermark": True}},
    )
    add(
        "indirect unversioned new key",
        "IndirectResource",
        {"filename": "a.png", "premium_resource_info": {"asset_uuid": "u", "is_derived_asset": False, "may_need_watermark": True}},
    )
    add("rgba base version", "RGBA", {"red": 0.5, "version": "1.0"})
    add("rgba headroom dropped", "RGBA", {"red": 0.5, "headroom": 4, "version": "1.0"})
    add("nested newer major", "Shape", {"geometry": {"position": {"x": 1, "y": 2, "version": "3.1"}, "size": "x"}})

    # -- unions -------------------------------------------------------------------
    add("stroke bare valueless", "Stroke", "empty")
    add("stroke bare unknown", "Stroke", "dotted")
    add("stroke bare payload case", "Stroke", "line")
    add("stroke valueless null", "Stroke", {"empty": None})
    add("stroke valueless true", "Stroke", {"empty": True})
    add("stroke valueless false", "Stroke", {"empty": False})
    add("stroke valueless object", "Stroke", {"empty": {}})
    add("stroke two cases", "Stroke", {"empty": None, "line": {"width": 2}})
    add("stroke no case", "Stroke", {})
    add("stroke only unknown", "Stroke", {"squiggle": {}})
    add("stroke payload null", "Stroke", {"line": None})
    add("stroke payload null and case", "Stroke", {"line": None, "frame": {"name": "chalkboard"}})
    add("stroke int input", "Stroke", 5)
    add("stroke version too new", "Stroke", {"empty": None, "version": "2.0"})
    add("stroke valueless with extra", "Stroke", {"empty": None, "glow": 1})
    add("chart one case", "Chart", {"column": {}})
    add("chart two cases newest", "Chart", {"column": {}, "bar": {}})
    add("chart two cases primary", "Chart", {"column": {}, "bar": {}, "primary_case": "column"})
    add("chart primary not str", "Chart", {"column": {}, "bar": {}, "primary_case": 3})
    add("chart primary missing case", "Chart", {"column": {}, "primary_case": "bar"})
    add("chart unknown sibling", "Chart", {"column": {}, "super_axis": {}})
    add("chart unknown primary", "Chart", {"column": {}, "super_axis": {}, "primary_case": "super_axis"})
    add("canvas newer case dropped", "CanvasObject", {"audio": {}, "shape": {}, "version": "1.0"})
    add("canvas only newer case", "CanvasObject", {"audio": {}, "version": "1.0"})
    add("canvas newer primary dropped", "CanvasObject", {"chart": {"column": {}}, "shape": {}, "version": "1.1", "primary_case": "chart"})
    add("canvas newest wins", "CanvasObject", {"shape": {}, "textbox": {}})
    add("canvas version raised", "CanvasObject", {"movie": {"resource": "x"}})
    add("canvas floor holds", "CanvasObject", {"shape": {}, "hologram": {}, "version": "1.9"})
    add(
        "canvas floor edited",
        "CanvasObject",
        {"shape": {}, "hologram": {}, "version": "1.9"},
        ops=[{"path": [], "set": "group", "json": {"children": [{"shape": {}}]}}],
    )
    add(
        "canvas floor primary kept",
        "CanvasObject",
        {"shape": {}, "hologram": {}, "version": "1.9", "primary_case": "shape"},
    )
    add(
        "canvas floor primary unknown",
        "CanvasObject",
        {"shape": {}, "hologram": {}, "version": "1.9", "primary_case": "hologram"},
    )
    add("shadow none valueless", "Shadow", "none")
    add("shadow version of none", "Shadow", {"none": None, "dropShadow": {}})
    add("text primitive case", "Text", {"string": "hello"})
    add("text primitive wrong", "Text", {"string": 5})
    add("text list case", "Text", {"text_runs": [{"string": "a"}], "string": "a"})
    add("duration float case", "Duration", {"seconds": 3})
    add("value bool case", "UnformattedValue", {"boolean": True})
    add("value bool case wrong", "UnformattedValue", {"boolean": 1})
    add("union preset id null", "Stroke", {"empty": None, "preset_identifier": None})
    add("union no case with preset id no registry", "Stroke", {"preset_identifier": "p"}, encode_without_presets=True)

    # -- presets ------------------------------------------------------------------
    base_presets = [
        {"identifier": "base", "properties": {"text_wrap": True, "vertical_alignment": "top"}},
        {"identifier": "wrapped", "parent_identifier": "base", "properties": {"vertical_alignment": "middle"}},
    ]
    add("preset fill", "CellProperties", {"preset_identifier": "wrapped"}, presets=base_presets)
    add(
        "preset fill then edit",
        "CellProperties",
        {"preset_identifier": "wrapped"},
        presets=base_presets,
        ops=[{"path": [], "set": "text_wrap", "json": False}],
    )
    add(
        "preset fill then same value",
        "CellProperties",
        {"preset_identifier": "wrapped"},
        presets=base_presets,
        ops=[{"path": [], "set": "text_wrap", "json": True}],
    )
    add("preset own value same", "CellProperties", {"preset_identifier": "wrapped", "text_wrap": True}, presets=base_presets)
    add("preset own value differs", "CellProperties", {"preset_identifier": "wrapped", "text_wrap": False}, presets=base_presets)
    add("preset own null over preset", "CellProperties", {"preset_identifier": "wrapped", "text_wrap": None}, presets=base_presets)
    add("preset missing", "CellProperties", {"preset_identifier": "nope", "text_wrap": True}, presets=base_presets)
    add("preset missing parent", "CellProperties", {"preset_identifier": "orphan"}, presets=[{"identifier": "orphan", "parent_identifier": "gone", "properties": {"text_wrap": False}}])
    cycle = [
        {"identifier": "a", "parent_identifier": "b", "properties": {}},
        {"identifier": "b", "parent_identifier": "a", "properties": {}},
    ]
    add("preset cycle", "CellProperties", {"preset_identifier": "a"}, presets=cycle)
    add("preset cycle nested", "Shape", {"fill": {"color": {"rgba": {"preset_identifier": "a"}}}}, presets=cycle)
    add("preset no registry", "CellProperties", {"preset_identifier": "wrapped"})
    add("preset encode without registry", "CellProperties", {"preset_identifier": "wrapped"}, presets=base_presets, encode_without_presets=True)
    add("preset empty id", "CellProperties", {"preset_identifier": "", "text_wrap": True}, presets=base_presets)
    rgba_presets = [
        {"identifier": "mid-red", "properties": {"red": 0.5}},
        {"identifier": "bad-rgba", "properties": {"red": "not-a-number"}},
        {"identifier": "loud", "properties": {"red": 5.0}},
        {"identifier": "int-red", "properties": {"red": 1}},
        {"identifier": "null-red", "properties": {"red": None}},
    ]
    add("preset rgba fill", "RGBA", {"preset_identifier": "mid-red"}, presets=rgba_presets)
    add("preset rgba bad type skipped", "RGBA", {"preset_identifier": "bad-rgba"}, presets=rgba_presets)
    add("preset rgba constraint", "RGBA", {"preset_identifier": "loud"}, presets=rgba_presets)
    add("preset rgba int to float", "RGBA", {"preset_identifier": "int-red"}, presets=rgba_presets)
    add("preset rgba null", "RGBA", {"preset_identifier": "null-red"}, presets=rgba_presets)
    add("preset rgba own int same", "RGBA", {"preset_identifier": "mid-red", "red": 0.5}, presets=rgba_presets)
    add("preset rgba own int json", "RGBA", {"preset_identifier": "int-red", "red": 1.0}, presets=rgba_presets)
    add(
        "preset rgba set default",
        "RGBA",
        {"preset_identifier": "mid-red"},
        presets=rgba_presets,
        ops=[{"path": [], "set": "red", "json": 0.0}],
    )
    add(
        "preset rgba touch",
        "RGBA",
        {"preset_identifier": "mid-red"},
        presets=rgba_presets,
        ops=[{"path": [], "touch": "red"}],
    )
    add(
        "preset adopted later",
        "RGBA",
        {"red": 0.5},
        presets=rgba_presets,
        ops=[{"path": [], "preset_identifier": "mid-red"}],
    )
    add(
        "preset nested rgba",
        "Slide",
        {"background": {"standard": {"color": {"rgba": {"preset_identifier": "mid-red"}}}}},
        presets=rgba_presets,
    )
    add("preset strict skips gate", "RGBA", {"preset_identifier": "bad-rgba"}, presets=rgba_presets, strict=True)
    add("preset strict good", "RGBA", {"preset_identifier": "mid-red"}, presets=rgba_presets, strict=True)
    override_presets = [
        {"identifier": "no-fill", "properties": {"fill": None}},
        {"identifier": "red-fill", "properties": {"fill": _fill(red=1)}},
        {"identifier": "foreign-fill", "properties": {"fill": {"type_identifier": SIZE, "width": 1, "height": 2}}},
        {"identifier": "bad-fill", "properties": {"fill": {"nope": {}}}},
    ]
    add("preset override clear", "CellProperties", {"preset_identifier": "no-fill"}, presets=override_presets)
    add("preset override clear own null", "CellProperties", {"preset_identifier": "no-fill", "fill": None}, presets=override_presets)
    add("preset override clear own value", "CellProperties", {"preset_identifier": "no-fill", "fill": _fill(red=1)}, presets=override_presets)
    add("preset override value", "CellProperties", {"preset_identifier": "red-fill"}, presets=override_presets)
    add("preset override own same", "CellProperties", {"preset_identifier": "red-fill", "fill": _fill(red=1)}, presets=override_presets)
    add("preset override own cleared", "CellProperties", {"preset_identifier": "red-fill", "fill": None}, presets=override_presets)
    add("preset override foreign", "CellProperties", {"preset_identifier": "foreign-fill"}, presets=override_presets)
    add("preset override bad", "CellProperties", {"preset_identifier": "bad-fill"}, presets=override_presets)
    add(
        "preset override edit nested",
        "CellProperties",
        {"preset_identifier": "red-fill"},
        presets=override_presets,
        ops=[{"path": ["fill", "color", "rgba"], "set": "green", "json": 1}],
    )
    add(
        "preset override cleared by edit",
        "CellProperties",
        {"preset_identifier": "red-fill"},
        presets=override_presets,
        ops=[{"path": [], "set": "fill", "json": None}],
    )
    shape_presets = [
        {"identifier": "null-head", "properties": {"head": None}},
        {"identifier": "arrow-head", "properties": {"head": "filled_arrow", "opacity": 0.5, "stroke": "empty"}},
        {"identifier": "proj", "properties": {"paragraph_properties": {"type_identifier": "paragraph-properties", "version": "1.0"}}},
        {"identifier": "unknown-key", "properties": {"not_a_shape_field": 1}},
        {"identifier": "geom", "properties": {"geometry": {"position": {"x": 1, "y": 2}, "size": {"width": 3, "height": 4}}}},
        {"identifier": "new-geom", "properties": {"geometry": {"position": {"x": 1, "y": 2, "version": "9.0"}, "size": {"width": 3, "height": 4}}}},
        {"identifier": "caption", "properties": {"caption": {"is_visible": False}}},
    ]
    add("preset def null skipped", "Shape", {"preset_identifier": "null-head"}, presets=shape_presets)
    add("preset def values", "Shape", {"preset_identifier": "arrow-head"}, presets=shape_presets)
    add("preset def own same", "Shape", {"preset_identifier": "arrow-head", "head": "filled_arrow", "opacity": 0.5}, presets=shape_presets)
    add(
        "preset def edit to default",
        "Shape",
        {"preset_identifier": "arrow-head"},
        presets=shape_presets,
        ops=[{"path": [], "set": "head", "json": "none"}],
    )
    add("preset projected key", "Shape", {"preset_identifier": "proj"}, presets=shape_presets)
    add("preset unknown key", "Shape", {"preset_identifier": "unknown-key"}, presets=shape_presets)
    add("preset nested model", "Shape", {"preset_identifier": "geom"}, presets=shape_presets)
    add("preset nested newer major opt", "Shape", {"preset_identifier": "new-geom"}, presets=shape_presets)
    add("preset opt null over preset", "Shape", {"preset_identifier": "caption", "caption": None}, presets=shape_presets)
    add(
        "preset opt set null over preset",
        "Shape",
        {"preset_identifier": "caption"},
        presets=shape_presets,
        ops=[{"path": [], "set": "caption", "json": None}],
    )
    req_presets = [
        {"identifier": "new-pos", "properties": {"position": {"x": 1, "y": 2, "version": "4.0"}, "size": {"width": 1, "height": 1}}},
        {"identifier": "pos", "properties": {"position": {"x": 1, "y": 2}, "size": {"width": 1, "height": 1}}},
    ]
    add("preset req newer major", "Geometry", {"preset_identifier": "new-pos"}, presets=req_presets)
    add("preset req filled", "Geometry", {"preset_identifier": "pos"}, presets=req_presets)
    add("preset req own same", "Geometry", {"preset_identifier": "pos", "size": {"width": 1, "height": 1}}, presets=req_presets)
    add("preset req own differs", "Geometry", {"preset_identifier": "pos", "size": {"width": 1, "height": 5}}, presets=req_presets)
    union_presets = [
        {"identifier": "red", "properties": {"color": _rgba(red=1)}},
        {"identifier": "two", "properties": {"color": _rgba(red=1), "gradient": {"stops": [], "flavor": {"linear": {}}}}},
        {"identifier": "bad", "properties": {"color": 5}},
        {"identifier": "newer", "properties": {"color": {"rgba": {"red": 1}, "version": "7.0"}}},
        {"identifier": "empty", "properties": {}},
        {"identifier": "stroke", "properties": {"empty": None, "line": {"width": 3}}},
    ]
    add("union preset supplies case", "Fill", {"preset_identifier": "red"}, presets=union_presets)
    add("union preset own same", "Fill", {"preset_identifier": "red", "color": _rgba(red=1)}, presets=union_presets)
    add("union preset own differs", "Fill", {"preset_identifier": "red", "color": _rgba(red=0)}, presets=union_presets)
    add("union preset own other case", "Fill", {"preset_identifier": "red", "image": {"technique": "tile", "image": {"indirect": {"filename": "a.png"}}}}, presets=union_presets)
    add("union preset two cases", "Fill", {"preset_identifier": "two"}, presets=union_presets)
    add("union preset two cases designated", "Fill", {"preset_identifier": "two", "primary_case": "gradient"}, presets=union_presets)
    add("union preset bad", "Fill", {"preset_identifier": "bad"}, presets=union_presets)
    add("union preset newer", "Fill", {"preset_identifier": "newer"}, presets=union_presets)
    add("union preset supplies nothing", "Fill", {"preset_identifier": "empty"}, presets=union_presets)
    add("union preset missing", "Fill", {"preset_identifier": "nope"}, presets=union_presets)
    add("union preset null case", "Fill", {"preset_identifier": "red", "color": None}, presets=union_presets)
    add("union preset null case and other", "Fill", {"preset_identifier": "red", "color": None, "gradient": {"stops": [], "flavor": {"linear": {}}}}, presets=union_presets)
    add("union preset valueless not supplied", "Stroke", {"preset_identifier": "stroke"}, presets=union_presets)
    add(
        "union preset edit case",
        "Fill",
        {"preset_identifier": "red"},
        presets=union_presets,
        ops=[{"path": ["color", "rgba"], "set": "red", "json": 0.25}],
    )
    add(
        "union preset set case null",
        "Fill",
        {"preset_identifier": "red"},
        presets=union_presets,
        ops=[{"path": [], "set": "color", "json": None}],
    )
    add(
        "union preset touch case",
        "Fill",
        {"preset_identifier": "red"},
        presets=union_presets,
        ops=[{"path": [], "touch": "color"}],
    )
    add("union preset no registry", "Fill", {"preset_identifier": "red"})
    add("union preset no registry encode", "Fill", {"preset_identifier": "red"}, presets=union_presets, encode_without_presets=True)
    deep = [
        {"identifier": f"d{i}", "properties": {"fill": {"color": {"rgba": {"preset_identifier": f"r{i}"}}}}}
        for i in range(6)
    ] + [
        {"identifier": f"r{i}", "properties": {"red": "bad" if i == 5 else 0.5}} for i in range(6)
    ] + [
        {"identifier": "chain0", "properties": {"fill": {"preset_identifier": "chain1"}}},
        {"identifier": "chain1", "properties": {"color": {"preset_identifier": "chain2"}}},
        {"identifier": "chain2", "properties": {"rgba": {"preset_identifier": "chain3"}}},
        {"identifier": "chain3", "properties": {"red": "bad", "green": 0.5}},
    ]
    add("preset nested adoption", "CellProperties", {"preset_identifier": "d0"}, presets=deep)
    add("preset nested adoption bad", "CellProperties", {"preset_identifier": "d5"}, presets=deep)
    add("preset gate depth", "CellProperties", {"preset_identifier": "chain0"}, presets=deep)
    add("preset gate depth strict", "CellProperties", {"preset_identifier": "chain0"}, presets=deep, strict=True)
    add(
        "preset many adopters share memo",
        "Slide",
        {
            "contents": [
                {"object": {"shape": {"preset_identifier": "arrow-head"}}},
                {"object": {"shape": {"preset_identifier": "arrow-head", "head": "line"}}},
                {"object": {"shape": {"preset_identifier": "null-head"}}},
            ]
        },
        presets=shape_presets,
    )
    return c


def _navigate(model: Any, path: list[Any]) -> Any:
    node = model
    for step in path:
        node = node[step] if isinstance(step, int) else getattr(node, step)
        if isinstance(node, Override):
            node = node.get()
    return node


def _apply(model: Any, op: dict[str, Any]) -> None:
    node = _navigate(model, op["path"])
    if "set" in op:
        setattr(node, op["set"], op["json"])
    elif "touch" in op:
        setattr(node, op["touch"], getattr(node, op["touch"]))
    elif "extra" in op:
        setattr(node, op["extra"], op["json"])
    elif "preset_identifier" in op:
        node.preset_identifier = op["preset_identifier"]
    else:
        raise ValueError(f"unknown op {op!r}")


def _issues(e: ValidationError) -> list[list[Any]]:
    return sorted(
        ([list(err["loc"]), err["type"]] for err in e.errors()),
        key=lambda x: (str(x[0]), x[1]),
    )


def _encode(model: Any, presets: list[Preset] | None) -> dict[str, Any]:
    ctx = None
    if presets is not None:
        ctx = {"wire_presets": PresetRegistry(presets), "_wire_version_error": None}
    try:
        return {"json": model.model_dump(mode="json", context=ctx)}
    except PydanticSerializationError as e:
        if ctx is not None and isinstance(ctx.get("_wire_version_error"), DocumentVersionError):
            return {"error": "DocumentVersionError", "message": str(ctx["_wire_version_error"])}
        return {"error": "EncodeError", "message": str(e)}


class _Capture(logging.Handler):
    def __init__(self) -> None:
        super().__init__(logging.WARNING)
        self.messages: list[str] = []

    def emit(self, record: logging.LogRecord) -> None:
        self.messages.append(record.getMessage())


def evaluate(case: dict[str, Any]) -> dict[str, Any]:  # noqa: C901 -- one linear pass
    cls = getattr(core, case["type"])
    presets = [Preset.from_dict(p) for p in case["presets"]] if "presets" in case else None
    ctx: dict[str, Any] | None = None
    registry = None
    if presets is not None:
        registry = PresetRegistry(presets)
        ctx = {"wire_presets": registry}
        if case.get("strict"):
            ctx["wire_presets_strict"] = True
    result: dict[str, Any] = dict(case)
    capture = _Capture()
    logger = logging.getLogger("creator_studio_doc_format")
    logger.addHandler(capture)
    logger.setLevel(logging.WARNING)
    try:
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            try:
                model = cls.model_validate(case["input"], context=ctx)
            except ValidationError as e:
                result["decode"] = {"error": "ModelValidationError", "issues": _issues(e)}
                model = None
            except DocumentVersionError as e:
                result["decode"] = {"error": "DocumentVersionError", "message": str(e)}
                model = None
            if model is not None:
                result["decode"] = "ok"
                # Unknown keys count as set, as in Pydantic. So does upstream's
                # internal hand-over key on an object a preset filled, and the
                # port keeps it too.
                result["fields_set"] = sorted(model.model_fields_set)
                if isinstance(model, TaggedUnionModel):
                    result["union_cases"] = [n for n, _p in model.union_cases()]
                if not case.get("ops"):
                    again = cls.model_validate(case["input"], context=ctx)
                    result["redecode_equal"] = again == model
                for op in case.get("ops", []):
                    _apply(model, op)
                encode_presets = None if case.get("encode_without_presets") else presets
                result["encode"] = _encode(model, encode_presets)
                twin = copy.deepcopy(model)
                result["copy_equal"] = twin == model
            logs = capture.messages + [str(w.message) for w in caught]
    finally:
        logger.removeHandler(capture)
    if model is not None:
        # The copy encodes after the logs are collected, so its floor warnings
        # don't count twice.
        result["copy_encode_same"] = _encode(twin, encode_presets) == result["encode"]
    result["logs"] = sorted(logs)
    if registry is not None:
        result["registry_warnings"] = sorted(registry.warnings)
    return result
