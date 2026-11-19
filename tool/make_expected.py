# Copyright © 2026 Apple Inc. and the creator_studio_document authors.
# Licensed under Apache License v2.0. For more information, see LICENSE.
# SPDX-License-Identifier: Apache-2.0
"""Writes the reference outputs that the Dart tests compare against.

Run with a Python environment where the upstream `creator_studio_doc_format`
package is installed, from the package root:

    python -I tool/make_expected.py

For each `test/fixtures/*.keyx`, it decodes `main.json` into a `Presentation`
with a `PresetRegistry` built from `presets.json`, encodes it again with a fresh
registry (as `Package.save` does), and writes the result to
`test/fixtures/expected/<name>.roundtrip.json`. It does the same with
`wire_presets_strict` set, into `<name>.roundtrip_strict.json`.

It also evaluates every differential case that `wire_cases.cases()` in
`tool/wire_cases.py` builds, and writes the outcomes to
`test/fixtures/expected/wire_cases.json`.
"""

from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path
from typing import Any

from creator_studio_doc_format.core import Preset, PresetRegistry, Presentation

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "test" / "fixtures"
EXPECTED = FIXTURES / "expected"

sys.path.insert(0, str(Path(__file__).resolve().parent))
import wire_cases  # noqa: E402


def _presets(raw: bytes | None) -> list[Preset]:
    if raw is None:
        return []
    return [Preset.from_dict(e) for e in json.loads(raw)]


def roundtrip(main: Any, presets: list[Preset], *, strict: bool) -> Any:
    decode_ctx: dict[str, Any] = {"wire_presets": PresetRegistry(presets)}
    if strict:
        decode_ctx["wire_presets_strict"] = True
    model = Presentation.model_validate(main, context=decode_ctx)
    encode_ctx = {"wire_presets": PresetRegistry(presets), "_wire_version_error": None}
    return model.model_dump(mode="json", context=encode_ctx)


def _write(path: Path, value: Any) -> None:
    text = json.dumps(value, ensure_ascii=False, indent=1) + "\n"
    path.write_text(text, encoding="utf-8")


def main() -> None:
    EXPECTED.mkdir(parents=True, exist_ok=True)
    for keyx in sorted(FIXTURES.glob("*.keyx")):
        with zipfile.ZipFile(keyx) as z:
            names = set(z.namelist())
            main_json = json.loads(z.read("main.json"))
            presets = _presets(
                z.read("presets.json") if "presets.json" in names else None
            )
        for strict, suffix in ((False, "roundtrip"), (True, "roundtrip_strict")):
            out = roundtrip(main_json, presets, strict=strict)
            _write(EXPECTED / f"{keyx.stem}.{suffix}.json", out)
        print(f"wrote expected outputs for {keyx.name}", file=sys.stderr)
    cases = wire_cases.cases()
    results = [wire_cases.evaluate(c) for c in cases]
    _write(EXPECTED / "wire_cases.json", results)
    print(f"wrote {len(results)} wire cases", file=sys.stderr)


if __name__ == "__main__":
    main()
