// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// src/creator_studio_doc_format/examples/hyperlinks.py.

/// Builds a presentation with a hyperlink of each target kind.
///
/// ```sh
/// dart run example/hyperlinks.dart [output]
/// ```
///
/// A hyperlink is a `Constituent` case of a `Paragraph`, alongside `run` and
/// `inlineObject`. `Hyperlink` is a union over four targets (`url`,
/// `slideJump`, `file`, and `program`), so each `Hyperlink` sets exactly one
/// field.
///
/// `SlideTarget` names a slide by identifier or by one of five position
/// cases. A position case doesn't depend on the identifiers in the document,
/// so it's the dependable choice when authoring. `byIdentifier` is meaningful
/// only against the identifiers of the document that holds the link.
library;

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';

import 'src/support.dart';

final _rgbaWhite = RGBA(red: 1, green: 1, blue: 1);
final _rgbaInk = RGBA(red: 0.1, green: 0.1, blue: 0.12);
final _rgbaLink = RGBA(red: 0.10, green: 0.35, blue: 0.85);
final _whiteBackground = Fill(presetIdentifier: 'fill_slide_bg');
// `Textbox.stroke` defaults to a visible black line. An empty stroke draws no
// border.
final _noBorder = Stroke(empty: true);

final _bodyStyle = CharacterProperties(
  fontSize: const Override.value(40),
  characterFill: Override.value(Fill(presetIdentifier: 'fill_ink')),
);
// Every hyperlink shares this style, whatever its target.
final _linkStyle = CharacterProperties(
  fontSize: const Override.value(40),
  underline: const Override.value(UnderlineType.single),
  characterFill: Override.value(Fill(presetIdentifier: 'fill_link')),
);

final _presets = [
  for (final (name, rgba) in [
    ('fill_slide_bg', _rgbaWhite),
    ('fill_ink', _rgbaInk),
    ('fill_link', _rgbaLink),
  ])
    Preset(name, {
      'color': {'rgba': rgba.toJson()},
    }),
];

const _idCover = 'slide-cover';
const _idAppendix = 'slide-appendix';

Constituent _plain(String text) => Constituent(
  run: TextRun(string: text, style: _bodyStyle),
);

/// Wraps [display] in a `HyperlinkField` that points at [target].
Constituent _linked(String display, Hyperlink target) => Constituent(
  hyperlink: HyperlinkField(
    target: target,
    run: TextRun(string: display, style: _linkStyle),
  ),
);

/// Builds the cover slide, with one textbox that shows every `Hyperlink`
/// case.
Slide _coverSlide() {
  final p1 = Paragraph(
    contents: [
      _plain('Visit '),
      _linked('example.com', Hyperlink(url: 'https://www.example.com')),
      _plain(', jump to the '),
      _linked(
        'appendix',
        Hyperlink(slideJump: SlideTarget(byIdentifier: _idAppendix)),
      ),
      _plain(', open the '),
      _linked('notes', Hyperlink(file: 'file:///tmp/notes.txt')),
      _plain(', or '),
      _linked('exit', Hyperlink(program: 'exit_slideshow')),
      _plain('.'),
    ],
  );

  final p2 = Paragraph(
    contents: [
      _plain('Navigate: '),
      _linked('next slide', Hyperlink(slideJump: SlideTarget(next: true))),
      _plain('.'),
    ],
  );

  final textbox = SlideObject(
    object: CanvasObject(
      textbox: Textbox(
        stroke: _noBorder,
        geometry: Geometry(
          position: Position(x: 160, y: 380),
          size: Size(width: 1600, height: 320),
        ),
        text: Text(paragraphs: [p1, p2]),
      ),
    ),
  );
  return Slide(
    identifier: _idCover,
    contents: [textbox],
    background: Override.value(SlideBackground(standard: _whiteBackground)),
  );
}

/// Builds the target slide for the `byIdentifier` jump on the cover.
Slide _appendixSlide() {
  final paragraph = Paragraph(
    contents: [
      _plain('Appendix: jump target for '),
      _linked(
        'the cover link',
        Hyperlink(slideJump: SlideTarget(byIdentifier: _idCover)),
      ),
      _plain('.'),
    ],
  );
  final textbox = SlideObject(
    object: CanvasObject(
      textbox: Textbox(
        stroke: _noBorder,
        geometry: Geometry(
          position: Position(x: 160, y: 480),
          size: Size(width: 1600, height: 120),
        ),
        text: Text(paragraphs: [paragraph]),
      ),
    ),
  );
  return Slide(
    identifier: _idAppendix,
    contents: [textbox],
    background: Override.value(SlideBackground(standard: _whiteBackground)),
  );
}

void main(List<String> args) {
  final parsed = parseArguments(
    args,
    script: 'hyperlinks',
    description: 'Builds a presentation with a hyperlink of each target kind.',
    names: ['output'],
    defaults: [defaultOutput('hyperlinks.keyx')],
  );
  if (parsed == null) {
    return;
  }
  final [output] = parsed;
  final doc = KeyxDocument(
    Presentation(
      slideSize: Size(width: 1920, height: 1080),
      slides: [_coverSlide(), _appendixSlide()],
    ),
    presets: _presets,
  );
  ensureParent(output);
  doc.save(output, preSaveHooks: [validateDocument]);
  reportSaved(output);
}
