# Copyright © 2026 Apple Inc. and the creator_studio_document authors.
# Licensed under Apache License v2.0. For more information, see LICENSE.
# SPDX-License-Identifier: Apache-2.0
"""Writes the upstream example documents that test/examples compares against.

Run with a Python environment where the upstream `creator_studio_doc_format`
package is installed, from the package root:

    python -I tool/make_example_expected.py

It runs every upstream example script as

    python -m creator_studio_doc_format.examples.<name> [input] <output>

with `example/fixtures/Tidal_en.keyx` as the input of `authoring` and
`example/fixtures/sample.keyx` as the input of `inspection`, and the quick
start of upstream's README as `hello`. It writes the JSON entries of each
document, `main.json`, `manifest.json`, and `presets.json`, to
`test/examples/expected/<name>.zip`, with a fixed timestamp, so a document
without random identifiers comes out the same on every run. The resources
aren't stored: the test checks those against the fixtures.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

import creator_studio_doc_format.examples as upstream_examples

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "example" / "fixtures"
EXPECTED = ROOT / "test" / "examples" / "expected"
ENTRIES = ("main.json", "manifest.json", "presets.json")

INPUTS = {
    "authoring": FIXTURES / "Tidal_en.keyx",
    "inspection": FIXTURES / "sample.keyx",
}

# The quick start of upstream's README, which `example/main.dart` ports.
HELLO = """
from creator_studio_doc_format.core import *
import sys

title = Textbox(
    geometry=Geometry(
        position=Position(x=160, y=440), size=Size(width=1600, height=200)
    ),
    stroke=Stroke(empty=True),
    layout_properties=LayoutProperties(vertical_alignment="center"),
    paragraph_properties=ParagraphProperties(
        alignment="center",
        character_properties=CharacterProperties(font_size=96),
    ),
    text=Text(string="Hello, Keynote"),
)
slide = Slide(contents=[SlideObject(object=CanvasObject(textbox=title))])

doc = KeyxDocument(
    Presentation(
        theme=KeynoteTheme(name="White", locale="en_US"),
        slide_size=Size(width=1920, height=1080),
        slides=[slide],
    )
)

doc.save(sys.argv[1])
"""


def _scripts() -> list[str]:
    folder = Path(upstream_examples.__file__).parent
    return sorted(
        p.stem for p in folder.glob("*.py") if not p.stem.startswith("_")
    )


def _store(document: Path, name: str) -> None:
    with zipfile.ZipFile(document) as source:
        entries = {e: source.read(e) for e in ENTRIES}
    target = EXPECTED / f"{name}.zip"
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as out:
        for entry, data in entries.items():
            # `writestr` with a name stamps the entry with the current time.
            info = zipfile.ZipInfo(entry, date_time=(2026, 1, 1, 0, 0, 0))
            info.external_attr = 0o600 << 16
            out.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED)
    print(f"wrote {target.relative_to(ROOT)}")


def main() -> None:
    EXPECTED.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for name in _scripts():
            output = work / f"{name}.keyx"
            args = [str(INPUTS[name])] if name in INPUTS else []
            subprocess.run(
                [
                    sys.executable,
                    "-I",
                    "-m",
                    f"creator_studio_doc_format.examples.{name}",
                    *args,
                    str(output),
                ],
                cwd=work,
                check=True,
                stdout=subprocess.DEVNULL,
            )
            _store(output, name)
        output = work / "hello.keyx"
        subprocess.run(
            [sys.executable, "-I", "-c", HELLO, str(output)],
            cwd=work,
            check=True,
        )
        _store(output, "hello")


if __name__ == "__main__":
    main()
