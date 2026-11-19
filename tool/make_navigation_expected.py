# Copyright © 2026 Apple Inc. and the creator_studio_document authors.
# Licensed under Apache License v2.0. For more information, see LICENSE.
# SPDX-License-Identifier: Apache-2.0
"""Writes the reference iteration orders that the navigation tests compare against.

Run with a Python environment where the upstream `creator_studio_doc_format`
package is installed, from the package root:

    python -I tool/make_navigation_expected.py

For each `test/fixtures/*.keyx`, it decodes `main.json` into a `Presentation`
with a `PresetRegistry` built from `presets.json`, as opening the document
does, runs `iterate_models` over it, and writes one entry per visit to
`test/fixtures/expected/<name>.navigation.json`:
`[path, class name, index_path, number of ancestors]`.
"""

from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path
from typing import Any

from creator_studio_doc_format.core import Preset, PresetRegistry, Presentation
from creator_studio_doc_format.navigation import iterate_models

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "test" / "fixtures"
EXPECTED = FIXTURES / "expected"


def listing(main: Any, presets: list[Preset]) -> list[list[Any]]:
    model = Presentation.model_validate(
        main, context={"wire_presets": PresetRegistry(presets)}
    )
    return [
        [v.path, type(v.model).__name__, list(v.index_path), len(v.ancestors)]
        for v in iterate_models(model)
    ]


def _write(path: Path, rows: list[list[Any]]) -> None:
    # One visit per line keeps diffs readable.
    lines = [json.dumps(row, ensure_ascii=False) for row in rows]
    path.write_text("[\n" + ",\n".join(lines) + "\n]\n", encoding="utf-8")


def main() -> None:
    EXPECTED.mkdir(parents=True, exist_ok=True)
    for keyx in sorted(FIXTURES.glob("*.keyx")):
        with zipfile.ZipFile(keyx) as z:
            names = set(z.namelist())
            main_json = json.loads(z.read("main.json"))
            raw = z.read("presets.json") if "presets.json" in names else None
        presets = [Preset.from_dict(e) for e in json.loads(raw)] if raw else []
        rows = listing(main_json, presets)
        _write(EXPECTED / f"{keyx.stem}.navigation.json", rows)
        print(f"wrote {len(rows)} visits for {keyx.name}", file=sys.stderr)


if __name__ == "__main__":
    main()
