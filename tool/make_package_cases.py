# Copyright © 2026 Apple Inc. and the creator_studio_document authors.
# Licensed under Apache License v2.0. For more information, see LICENSE.
# SPDX-License-Identifier: Apache-2.0
"""Writes the package archives and outcomes that test/package compares against.

Run with a Python environment where the upstream `creator_studio_doc_format`
package is installed, from the package root:

    python -I tool/make_package_cases.py

It builds well-formed, unusual, and malformed archives from
`test/fixtures/sample.keyx` into `test/fixtures/package/`, opens each with
upstream's `KeyxDocument.open` and `KeyxDocument.open_lazy`, saves what opens,
and writes the outcomes to `test/fixtures/package/expected.json`: the error
kind (or the exception type, for an error that isn't a `DocumentPackageError`),
or the manifest version, preset identifiers, resource names, and the saved
archive's entries. A saved JSON part is stored once, under the CRC-32 of its
bytes, in `parts`; a saved resource is recorded by its CRC-32 and length.

It also writes two corpora of compressed data, from a fixed seed:

- `test/fixtures/package/codec_cases.json`: small archives whose resource is
  stored, deflated, bzip2, or LZMA data, intact, cut short, damaged, or with a
  wrong size or flags, each with how upstream opens it from a stream: the
  error kind and message, or each resource's CRC-32 and length.
- `test/fixtures/package/decompress_cases.json`: compressed streams, intact,
  cut short, or damaged, each with what the decompressor that `zipfile` reads
  that method with gives for it in one call: the CRC-32 and length of its
  output cut at a size, and whether its stream ended, or its error message.
"""

from __future__ import annotations

import base64
import bz2
import io
import json
import logging
import random
import shutil
import struct
import sys
import tempfile
import warnings
import zipfile
import zlib
from pathlib import Path
from typing import Any

from pydantic import ValidationError

from creator_studio_doc_format.core import (
    CanvasObject,
    DocumentPackageError,
    DocumentVersionError,
    KeyxDocument,
    Presentation,
    PresetRegistry,
    Shape,
    Size,
    Slide,
    SlideObject,
)

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "test" / "fixtures"
OUT = FIXTURES / "package"


def _zip(entries: list[tuple[Any, bytes]], method: int = zipfile.ZIP_DEFLATED,
         comment: bytes = b"") -> bytes:
    buf = io.BytesIO()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")  # duplicate names are deliberate
        with zipfile.ZipFile(buf, "w", method) as zf:
            for name, data in entries:
                # A fixed timestamp keeps the archives the same on every run.
                info = name if isinstance(name, zipfile.ZipInfo) else zipfile.ZipInfo(
                    name, date_time=(2026, 1, 1, 0, 0, 0))
                info.date_time = (2026, 1, 1, 0, 0, 0)
                info.external_attr = 0o600 << 16
                zf.writestr(info, data, compress_type=method)
            zf.comment = comment
    return buf.getvalue()


def _clear_utf8_flags(data: bytes) -> bytes:
    b = bytearray(data)
    for sig, at in ((b"PK\x01\x02", 8), (b"PK\x03\x04", 6)):
        i = 0
        while (i := b.find(sig, i)) >= 0:
            struct.pack_into("<H", b, i + at, struct.unpack_from("<H", b, i + at)[0] & ~0x800)
            i += 4
    return bytes(b)


def _patch_cd(data: bytes, offset: int, fmt: str, fn: Any, pick: Any = None) -> bytes:
    b = bytearray(data)
    k = 0
    while (k := b.find(b"PK\x01\x02", k)) >= 0:
        name_len = struct.unpack_from("<H", b, k + 28)[0]
        if pick is None or pick(bytes(b[k + 46:k + 46 + name_len])):
            struct.pack_into(fmt, b, k + offset, fn(struct.unpack_from(fmt, b, k + offset)[0]))
            return bytes(b)
        k += 4
    raise AssertionError("no central directory entry to patch")


def cases() -> dict[str, bytes]:
    sample = zipfile.ZipFile(FIXTURES / "sample.keyx")
    parts = {n: sample.read(n) for n in sample.namelist() if not n.endswith("/")}
    main, man, pre = parts["main.json"], parts["manifest.json"], parts["presets.json"]
    base = [("main.json", main), ("manifest.json", man), ("presets.json", pre)] + [
        (n, d) for n, d in parts.items() if n.startswith("Data/")
    ]

    def with_(**over: bytes | None) -> list[tuple[Any, bytes]]:
        out = [(n, over.get(n, d)) for n, d in base]
        return [(n, d) for n, d in out if d is not None]

    def adopt_first_slide(pid: str) -> bytes:
        m = json.loads(main)
        m["slides"][0]["preset_identifier"] = pid
        return json.dumps(m).encode()

    out: dict[str, bytes] = {}
    out["ok_plain.keyx"] = _zip(base)
    out["truncated_half.keyx"] = (FIXTURES / "sample.keyx").read_bytes()[:1000]
    out["truncated_tail.keyx"] = (FIXTURES / "sample.keyx").read_bytes()[:-10]
    out["not_a_zip.keyx"] = b"hello, this is not a zip archive at all\n" * 3
    out["empty_file.keyx"] = b""
    out["tiny.keyx"] = b"PK"
    out["local_header_only.keyx"] = b"PK\x03\x04" + b"\x00" * 40
    out["empty_zip.keyx"] = _zip([])
    out["missing_main.keyx"] = _zip(with_(**{"main.json": None}))
    out["missing_manifest.keyx"] = _zip(with_(**{"manifest.json": None}))
    out["missing_presets.keyx"] = _zip(with_(**{"presets.json": None}))
    out["bad_main_json.keyx"] = _zip(with_(**{"main.json": b'{"type_identifier": '}))
    out["main_not_object.keyx"] = _zip(with_(**{"main.json": b"[]"}))
    out["main_bigint_digits.keyx"] = _zip(with_(**{"main.json": b'{"x": ' + b"1" * 4301 + b"}"}))
    out["main_bad_utf8.keyx"] = _zip(with_(**{"main.json": main[:-1] + b',"zzz":"\xff"}'}))
    out["main_lone_surrogate_escape.keyx"] = _zip(with_(**{"main.json": main[:-1] + b',"zzz":"\\ud800"}'}))
    out["nan_extras.keyx"] = _zip(with_(**{"main.json": main[:-1] + b',"zzz":[NaN,Infinity,-Infinity,1e400]}'}))
    out["utf8_bom_main.keyx"] = _zip(with_(**{"main.json": b"\xef\xbb\xbf" + main}))
    out["utf32le_main.keyx"] = _zip(with_(**{"main.json": main.decode().encode("utf-32-le")}))
    out["utf16_presets.keyx"] = _zip(with_(**{"presets.json": pre.decode().encode("utf-16")}))
    out["presets_not_json.keyx"] = _zip(with_(**{"presets.json": b"[{"}))
    out["presets_not_array.keyx"] = _zip(with_(**{"presets.json": b'{"identifier": "a"}'}))
    out["presets_no_properties.keyx"] = _zip(with_(**{"presets.json": b'[{"identifier": "a"}]'}))
    junk = [1, "x", {"identifier": 5}, {"properties": {}}] + json.loads(pre)
    out["presets_junk_entries.keyx"] = _zip(with_(**{"presets.json": json.dumps(junk).encode()}))
    cycle = json.loads(pre) + [
        {"identifier": "cy-a", "parent_identifier": "cy-b", "properties": {}},
        {"identifier": "cy-b", "parent_identifier": "cy-a", "properties": {}},
    ]
    out["presets_cycle_reached.keyx"] = _zip(with_(**{
        "presets.json": json.dumps(cycle).encode(), "main.json": adopt_first_slide("cy-a")}))
    out["presets_cycle_unreached.keyx"] = _zip(with_(**{"presets.json": json.dumps(cycle).encode()}))
    pres = Presentation(slide_size=Size(width=1024, height=768), slides=[
        Slide(contents=[SlideObject(object=CanvasObject(shape=Shape(preset_identifier="s")))])])
    loop_main = json.dumps(pres.model_dump(mode="json", context={"wire_presets": PresetRegistry([])}))
    loop = [{"identifier": "s", "properties": {"text": {"paragraphs": [
        {"contents": [{"inline_object": {"shape": {"preset_identifier": "s"}}}]}]}}}]
    out["presets_recursion_loop.keyx"] = _zip([
        ("main.json", loop_main.encode()), ("presets.json", json.dumps(loop).encode())])
    for name, text in [
        ("manifest_bad_json", b"{nope"), ("manifest_not_object", b"[1]"),
        ("manifest_major2", b'{"package_version": "2.0"}'),
        ("manifest_dict_major2", b'{"package_version": {"major": 2, "minor": 1}}'),
        ("manifest_number2", b'{"package_version": 2.5}'),
        ("manifest_number1", b'{"package_version": 1}'),
        ("manifest_garbage", b'{"package_version": "banana"}'),
        ("manifest_bool", b'{"package_version": true}'),
    ]:
        out[f"{name}.keyx"] = _zip(with_(**{"manifest.json": text}))
    out["nested_root.keyx"] = _zip([("Deck/" + n, d) for n, d in base])
    out["nested_root_macosx.keyx"] = _zip([("Deck/" + n, d) for n, d in base] + [
        ("__MACOSX/Deck/._main.json", b"\x00\x05\x16\x07junk"), ("__MACOSX/._Deck", b"junk")])
    out["macosx_root.keyx"] = _zip(base + [
        ("__MACOSX/._main.json", b"junk"), ("__MACOSX/Data/._x.png", b"junk")])
    out["dotslash.keyx"] = _zip([("./" + n, d) for n, d in base])
    out["two_roots.keyx"] = _zip([("A/" + n, d) for n, d in base] + [("B/x", b"1")])
    out["with_comment.keyx"] = _zip(base, comment=b"a comment PK here")
    out["prepended.keyx"] = b"#!/bin/sh\nexit 0\n" * 10 + _zip(base)
    out["stored.keyx"] = _zip(base, zipfile.ZIP_STORED)
    out["bzip2.keyx"] = _zip(base, zipfile.ZIP_BZIP2)
    out["lzma.keyx"] = _zip(base, zipfile.ZIP_LZMA)
    out["data_nested.keyx"] = _zip(base + [
        ("Data/sub/x.png", b"x"), ("Data/", b""), ("Data/..", b"y"), ("Data/a\\b", b"z"),
        ("Data/ok 2.png", b"ok")])
    out["dup_entries.keyx"] = _zip(base + [("Data/dup.png", b"first"), ("Data/dup.png", b"second")])
    out["empty_member.keyx"] = _zip(base + [("Data/empty.png", b"")])
    named = _zip(base + [("Data/cé.png", b"cafe")])
    out["utf8_name_no_flag.keyx"] = _clear_utf8_flags(named)
    out["cp437_name.keyx"] = _clear_utf8_flags(named.replace("cé.png".encode(), b"c\x82.png!"))
    mismatch = _zip(base + [("Data/abc.png", b"abc")])
    at = mismatch.find(b"Data/abc.png")
    out["local_name_mismatch.keyx"] = mismatch[:at] + b"Data/abd.png" + mismatch[at + 12:]
    stored = _zip(base, zipfile.ZIP_STORED)
    out["bad_crc_main.keyx"] = _patch_cd(stored, 16, "<L", lambda v: v ^ 1)
    out["bad_crc_data.keyx"] = _patch_cd(
        stored, 16, "<L", lambda v: v ^ 1, lambda n: n.startswith(b"Data/"))
    nested = _zip([("Deck/" + n, d) for n, d in base] + [("__MACOSX/Deck/._x", b"j")], zipfile.ZIP_STORED)
    out["nested_bad_crc.keyx"] = _patch_cd(nested, 16, "<L", lambda v: v ^ 1)
    out["encrypted_flag.keyx"] = _patch_cd(_zip(base), 8, "<H", lambda v: v | 1)
    out["unsupported_method.keyx"] = _patch_cd(_zip(base), 10, "<H", lambda v: 99)
    out["extract_version.keyx"] = _patch_cd(_zip(base), 6, "<B", lambda v: 64)
    out["bad_cd_magic.keyx"] = _patch_cd(_zip(base), 3, "<B", lambda v: 9)
    deflated = bytearray(_zip(base))
    k = deflated.find(b"PK\x03\x04")
    start = k + 30 + struct.unpack_from("<H", deflated, k + 26)[0] + struct.unpack_from("<H", deflated, k + 28)[0]
    deflated[start:start + 8] = b"\xff" * 8
    out["corrupt_deflate_main.keyx"] = bytes(deflated)
    info = zipfile.ZipInfo("Data/extra.png")
    info.extra = struct.pack("<HH", 0x9999, 4) + b"abcd"
    extra = bytearray(_zip(base + [(info, b"e")]))
    k = extra.rfind(b"PK\x01\x02")
    struct.pack_into("<H", extra, k + 46 + struct.unpack_from("<H", extra, k + 28)[0] + 2, 40)
    out["corrupt_extra.keyx"] = bytes(extra)
    info = zipfile.ZipInfo("Data/plain.png")
    unicode_name = "Data/ünicode.png".encode()
    info.extra = struct.pack("<HHBL", 0x7075, 5 + len(unicode_name), 1,
                             zlib.crc32(b"Data/plain.png")) + unicode_name
    out["unicode_path.keyx"] = _zip(base + [(info, b"uni")])
    plain = _zip(base)
    eocd = plain.rfind(b"PK\x05\x06")
    out["multidisk.keyx"] = plain[:eocd] + struct.pack("<4sLQL", b"PK\x06\x07", 1, 0, 2) + plain[eocd:]
    # A central directory offset 100 bytes too large puts every local header
    # 100 bytes earlier, and the first before the start of the file.
    late = bytearray(plain)
    struct.pack_into("<L", late, eocd + 16, struct.unpack_from("<L", late, eocd + 16)[0] + 100)
    out["negative_header_offset.keyx"] = bytes(late)
    return out


_CODEC_MAIN = json.dumps({
    "type_identifier": "com.apple.iwork.keynote.presentation",
    "slide_size": {"width": 1024, "height": 768},
    "slides": [{}],
}).encode()


def _content(rng: random.Random, limit: int) -> bytes:
    n = rng.choice([0, 1, 5, 40, 300, limit])
    kind = rng.randrange(4)
    if kind == 0:
        return bytes(rng.randrange(256) for _ in range(n))
    if kind == 1:
        words = [b"slide ", b"keynote ", b"\n", b"zz" * 20]
        return b"".join(rng.choice(words) for _ in range(n // 4 + 1))[:n]
    if kind == 2:
        return bytes([rng.randrange(3)]) * n
    return bytes((i * 7) % 251 for i in range(n))


def _member(data: bytes) -> tuple[int, int, int]:
    """Returns the offsets of the central directory entry, the local header,
    and the data of the last member of `data`."""
    cd = data.rfind(b"PK\x01\x02")
    lh = struct.unpack_from("<L", data, cd + 42)[0]
    name_len, extra_len = struct.unpack_from("<HH", data, lh + 26)
    return cd, lh, lh + 30 + name_len + extra_len


def _set(data: bytearray, cd_at: int, lh_at: int | None, fmt: str, cd: int, value: int) -> None:
    struct.pack_into(fmt, data, cd + cd_at, value)
    if lh_at is not None:
        lh = struct.unpack_from("<L", data, cd + 42)[0]
        struct.pack_into(fmt, data, lh + lh_at, value)


def _patched(entry: bytes, method: int, stored: bytes, size: int, crc: int) -> bytes:
    """An archive whose `Data/e.bin` holds `stored` with `method`, `size`, and `crc`."""
    archive = bytearray(_zip([("main.json", _CODEC_MAIN), ("Data/e.bin", entry)],
                             zipfile.ZIP_STORED))
    cd, _, start = _member(bytes(archive))
    archive[start:start + len(entry)] = stored
    _set(archive, 10, 8, "<H", cd, method)
    _set(archive, 16, 14, "<L", cd, crc)
    _set(archive, 24, 22, "<L", cd, size)
    return bytes(archive)


def codec_cases() -> dict[str, bytes]:
    out: dict[str, bytes] = {}
    # Data too short for the decompressor to say anything, with no size.
    for name, method, stored, size in [
        ("lzma_short_size0", zipfile.ZIP_LZMA, b"abc", 0),
        ("lzma_header_only_size0", zipfile.ZIP_LZMA, b"\x09\x04\x05\x00", 0),
        ("lzma_big_props_size0", zipfile.ZIP_LZMA, b"\x09\x04\xff\x00xyz", 0),
        ("lzma_short_size5", zipfile.ZIP_LZMA, b"abc", 5),
        ("lzma_props_short_size9", zipfile.ZIP_LZMA, b"\x09\x04\x05\x00\x5d\x00", 9),
        ("lzma_props_size4", zipfile.ZIP_LZMA, b"\x09\x04\x04\x00\x5d\x00\x00\x10\x00", 0),
        ("lzma_props_byte225", zipfile.ZIP_LZMA, b"\x09\x04\x05\x00\xe1\x00\x00\x10\x00\x00", 0),
        ("lzma_props_lclp5", zipfile.ZIP_LZMA, b"\x09\x04\x05\x00\x05\x00\x00\x10\x00\x00", 0),
        ("lzma_range_first_byte", zipfile.ZIP_LZMA, b"\x09\x04\x05\x00\x5d\x00\x00\x10\x00\x01", 0),
        ("bzip2_short_size0", zipfile.ZIP_BZIP2, b"BZ", 0),
        ("bzip2_short_size3", zipfile.ZIP_BZIP2, b"BZh9", 3),
        ("bzip2_bad_magic", zipfile.ZIP_BZIP2, b"BZx9", 0),
        ("bzip2_level0", zipfile.ZIP_BZIP2, b"BZh0", 0),
        ("deflate_empty_garbage_size0", zipfile.ZIP_DEFLATED, b"\x03\x00", 0),
        ("deflate_block_type3", zipfile.ZIP_DEFLATED, b"\x07\x00", 0),
        ("deflate_stored_lengths", zipfile.ZIP_DEFLATED, b"\x01\x05\x00\x05\x00", 5),
        ("stored_short_size9", zipfile.ZIP_STORED, b"abc", 9),
    ]:
        out[name] = _patched(b"\0" * len(stored), method, stored, size, 0)
    # An encrypted member, which upstream names by its `ZipInfo`.
    for name, method, attr in [
        ("encrypted_deflate", zipfile.ZIP_DEFLATED, 0o600 << 16),
        ("encrypted_stored", zipfile.ZIP_STORED, 0o100644 << 16),
        ("encrypted_lzma_setuid", zipfile.ZIP_LZMA, 0o104755 << 16),
        ("encrypted_bzip2_dir_mode", zipfile.ZIP_BZIP2, (0o40755 << 16) | 0x10),
        ("encrypted_method99_sticky", 99, 0o101776 << 16),
        ("encrypted_no_mode", zipfile.ZIP_DEFLATED, 0x20),
        ("encrypted_symlink", zipfile.ZIP_DEFLATED, 0o120777 << 16),
    ]:
        info = zipfile.ZipInfo("Data/e.bin", date_time=(2026, 1, 1, 0, 0, 0))
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as zf:
            zf.writestr("main.json", _CODEC_MAIN)
            zf.writestr(info, b"secret" * 9, compress_type=method if method != 99 else 8)
        archive = bytearray(buf.getvalue())
        cd, _, _ = _member(bytes(archive))
        _set(archive, 8, 6, "<H", cd, 1)
        _set(archive, 10, 8, "<H", cd, method)
        struct.pack_into("<L", archive, cd + 38, attr)
        out[name] = bytes(archive)
    # Every method, intact and damaged.
    rng = random.Random(2026)
    methods = [zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED, zipfile.ZIP_BZIP2, zipfile.ZIP_LZMA]
    for i in range(240):
        method = methods[i % 4]
        content = _content(rng, 4000)
        archive = bytearray(_zip([("main.json", _CODEC_MAIN), ("Data/e.bin", content)], method))
        cd, lh, start = _member(bytes(archive))
        compress_size = struct.unpack_from("<L", archive, cd + 20)[0]
        ops = []
        for _ in range(rng.choice([0, 1, 1, 2, 3])):
            op = rng.choice(["cut", "flip", "bytes", "size", "size0", "prefix"])
            if op == "cut":
                _set(archive, 20, 18, "<L", cd, rng.randint(0, compress_size))
            elif op == "flip" and compress_size:
                archive[start + rng.randrange(compress_size)] ^= 1 << rng.randrange(8)
            elif op == "bytes" and compress_size:
                for _ in range(4):
                    archive[start + rng.randrange(compress_size)] = rng.randrange(256)
            elif op == "size":
                _set(archive, 24, 22, "<L", cd, rng.randint(0, 2 * len(content) + 5))
            elif op == "size0":
                _set(archive, 24, 22, "<L", cd, 0)
                _set(archive, 16, 14, "<L", cd, 0)
            elif op == "prefix":
                n = rng.randint(0, len(content))
                _set(archive, 24, 22, "<L", cd, n)
                _set(archive, 16, 14, "<L", cd, zlib.crc32(content[:n]))
            ops.append(op)
        name = f"m{method}_{i:03d}" + "".join(f"_{op}" for op in ops)
        out[name] = bytes(archive)
    return out


def codec_outcome(data: bytes) -> dict[str, Any]:
    try:
        doc = KeyxDocument.open(io.BytesIO(data))
    except DocumentPackageError as e:
        return {"error": e.kind.value, "message": str(e)}
    except Exception as e:  # noqa: BLE001 -- recorded, as upstream raises it
        return {"error": type(e).__name__, "message": str(e)}
    return {"resources": {
        n: f"{zlib.crc32(d):08x}:{len(d)}" for n, d in sorted(doc.resources.items())}}


def _decompress(method: int, data: bytes, keep: int) -> dict[str, Any]:
    """What `ZipExtFile` gets from its decompressor for `data` in one call."""
    try:
        if method == zipfile.ZIP_DEFLATED:
            d = zlib.decompressobj(-15)
            out = d.decompress(data, 1 << 30)
            if d.eof or not d.unconsumed_tail:
                out += d.flush()
        elif method == zipfile.ZIP_BZIP2:
            d = bz2.BZ2Decompressor()
            out = d.decompress(data)
        else:
            d = zipfile.LZMADecompressor()
            out = d.decompress(data)
    except Exception as e:  # noqa: BLE001 -- recorded, as upstream raises it
        return {"error": str(e)}
    out = out[:keep]
    return {"output": f"{zlib.crc32(out):08x}:{len(out)}", "ended": d.eof}


def decompress_cases() -> list[dict[str, Any]]:
    rng = random.Random(1)
    cases = []
    for i in range(600):
        method = [zipfile.ZIP_DEFLATED, zipfile.ZIP_BZIP2, zipfile.ZIP_LZMA][i % 3]
        content = _content(rng, 2000)
        if method == zipfile.ZIP_DEFLATED:
            c = zlib.compressobj(rng.choice([0, 1, 6, 9]), zlib.DEFLATED, -15, 9,
                                 rng.choice([0, 1, 2, 3, 4]))
        elif method == zipfile.ZIP_BZIP2:
            c = bz2.BZ2Compressor(rng.choice([1, 9]))
        else:
            c = zipfile.LZMACompressor()
        data = bytearray(c.compress(content) + c.flush())
        for _ in range(rng.choice([0, 1, 1, 2, 3])):
            op = rng.randrange(5)
            if op == 0 and data:
                del data[rng.randrange(len(data) + 1):]
            elif op == 1 and data:
                data[rng.randrange(len(data))] ^= 1 << rng.randrange(8)
            elif op == 2 and data:
                data[rng.randrange(min(len(data), 40))] = rng.randrange(256)
            elif op == 3:
                data += bytes(rng.randrange(256) for _ in range(rng.randrange(20)))
            elif op == 4 and data:
                for _ in range(5):
                    data[rng.randrange(len(data))] = rng.randrange(256)
        if rng.random() < 0.05:
            data = bytearray(rng.randrange(256) for _ in range(rng.randrange(60)))
        keep = rng.choice([0, 10, 1000, 1 << 20])
        cases.append({"method": method, "keep": keep,
                      "data": base64.b64encode(bytes(data)).decode(),
                      **_decompress(method, bytes(data), keep)})
    return cases


def _write_json(path: Path, value: Any) -> None:
    text = json.dumps(value, indent=1, sort_keys=True, ensure_ascii=False)
    path.write_text(text + "\n", encoding="utf-8")


def outcome(path: Path, lazy: bool, parts: dict[str, Any]) -> dict[str, Any]:
    try:
        doc = KeyxDocument.open_lazy(path) if lazy else KeyxDocument.open(path)
    except DocumentPackageError as e:
        return {"error": e.kind.value}
    except DocumentVersionError:
        return {"error": "DocumentVersionError"}
    except ValidationError:
        return {"error": "ValidationError"}
    except Exception as e:  # noqa: BLE001 -- recorded, as upstream raises it
        return {"error": type(e).__name__}
    try:
        result: dict[str, Any] = {
            "manifest": doc.manifest.package_version,
            "presets": [p.identifier for p in doc.presets],
            "resources": sorted(doc.resources),
        }
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "saved.keyx"
            try:
                doc.save(dest, validate_resources=False)
            except DocumentPackageError as e:
                result["save_error"] = e.kind.value
                return result
            except Exception as e:  # noqa: BLE001
                result["save_error"] = type(e).__name__
                return result
            saved = zipfile.ZipFile(dest)
            entries = {}
            for name in sorted(saved.namelist()):
                data = saved.read(name)
                crc = f"{zlib.crc32(data):08x}:{len(data)}"
                if name.endswith(".json") and "/" not in name:
                    parts[crc] = json.loads(data)
                entries[name] = crc
            result["saved"] = entries
        return result
    finally:
        doc.close()


def main() -> None:
    warnings.simplefilter("ignore")
    logging.disable(logging.CRITICAL)
    shutil.rmtree(OUT, ignore_errors=True)
    OUT.mkdir(parents=True)
    expected: dict[str, Any] = {}
    parts: dict[str, Any] = {}
    for name, data in sorted(cases().items()):
        path = OUT / name
        path.write_bytes(data)
        expected[name] = {
            "open": outcome(path, False, parts),
            "lazy": outcome(path, True, parts),
        }
    _write_json(OUT / "expected.json", {"cases": expected, "parts": parts})
    print(f"wrote {len(expected)} cases to {OUT.relative_to(ROOT)}", file=sys.stderr)
    codec = {name: {"archive": base64.b64encode(data).decode(), **codec_outcome(data)}
             for name, data in sorted(codec_cases().items())}
    _write_json(OUT / "codec_cases.json", codec)
    decompress = decompress_cases()
    _write_json(OUT / "decompress_cases.json", decompress)
    print(f"wrote {len(codec)} codec and {len(decompress)} decompressor cases",
          file=sys.stderr)


if __name__ == "__main__":
    main()
