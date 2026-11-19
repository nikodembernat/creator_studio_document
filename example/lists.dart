// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// src/creator_studio_doc_format/examples/lists.py.

/// Builds a presentation with bulleted, numbered, and image bullet lists, and
/// a rule.
///
/// ```sh
/// dart run example/lists.dart [output]
/// ```
///
/// Text and textbox styling here is deliberately minimal, with plain inline
/// `CharacterProperties` and `ParagraphProperties`, so the file stays focused
/// on list styles.
library;

import 'dart:io';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';

import 'src/support.dart';

final _rgbaOffWhite = RGBA(red: 0.96, green: 0.94, blue: 0.90);
final _rgbaOrange = RGBA(red: 0.929, green: 0.353, blue: 0.157);

final _titleStyle = CharacterProperties(
  fontSize: const Override.value(96),
  bold: const Override.value(true),
);
final _headingStyle = CharacterProperties(
  fontSize: const Override.value(32),
  bold: const Override.value(true),
);
final _bodyStyle = CharacterProperties(fontSize: const Override.value(40));

// `Textbox.stroke` defaults to a visible black line. An empty stroke draws no
// border.
final _noBorder = Stroke(empty: true);

ListProperties _listStyle(List<ListLevelType> levels) =>
    ListProperties(levels: Override.value(levels));

final bulletLevels = [
  ListLevelType(
    labelIndent: 0,
    textIndent: 1.5,
    label: ListLabelType(string: ListStringLabel(string: '•')),
  ),
  ListLevelType(
    labelIndent: 32,
    textIndent: 3,
    label: ListLabelType(string: ListStringLabel(string: '▸')),
  ),
];

final numberedLevels = [
  ListLevelType(
    labelIndent: 0,
    textIndent: 1.5,
    label: ListLabelType(
      number: ListNumberLabel(
        numberFormat: NumberFormatType(
          kind: NumberFormatTypeKind.numeric,
          format: Format.decimal,
        ),
      ),
    ),
  ),
];

// The image bullet's resource must be in `doc.resources` under its
// `IndirectResource.identifier`, or under its `filename` when the identifier
// is unset. `scale: 0.5` is half the image's pixel size. A leading space on
// each paragraph below separates it from the bullet.
final imageLevels = [
  ListLevelType(
    labelIndent: 0,
    textIndent: 1.8,
    label: ListLabelType(
      image: ListImageLabel(
        resource: Resource(indirect: IndirectResource(filename: 'bullet.png')),
        scale: 0.5,
      ),
    ),
  ),
];

SlideObject _textbox(
  CharacterProperties style,
  double x,
  double y,
  double w,
  double h, {
  required String text,
}) => SlideObject(
  object: CanvasObject(
    textbox: Textbox(
      stroke: _noBorder,
      geometry: Geometry(
        position: Position(x: x, y: y),
        size: Size(width: w, height: h),
      ),
      text: Text(
        textRuns: [TextRun(string: text, style: style)],
      ),
    ),
  ),
);

// A paragraph doesn't inherit `listStyle`, so every paragraph sets it. Omit
// `listLevel` for level 0. Numbering doesn't continue on its own, so every
// numbered item that isn't "1" sets `listStart`.
Paragraph _paragraph(
  ListProperties? listStyle,
  String text, {
  int? listStart,
  int? listLevel,
}) => Paragraph(
  listStyle: listStyle,
  listStart: listStart,
  listLevel: listLevel,
  contents: [
    Constituent(
      run: TextRun(string: text, style: _bodyStyle),
    ),
  ],
);

/// Builds one slide with a title, three section headings, and three body
/// blocks.
Slide _slide() {
  final title = _textbox(
    _titleStyle,
    130,
    60,
    1660,
    130,
    text: 'Advanced text',
  );
  final headingA = _textbox(_headingStyle, 130, 220, 850, 50, text: 'LISTS');
  final headingB = _textbox(
    _headingStyle,
    1020,
    220,
    770,
    50,
    text: 'IMAGE BULLETS',
  );
  final headingC = _textbox(
    _headingStyle,
    1020,
    620,
    770,
    50,
    text: 'PARAGRAPH RULE',
  );

  final numbered = _listStyle(numberedLevels);
  final bullet = _listStyle(bulletLevels);
  final blockA = SlideObject(
    object: CanvasObject(
      textbox: Textbox(
        stroke: _noBorder,
        geometry: Geometry(
          position: Position(x: 130, y: 280),
          size: Size(width: 850, height: 700),
        ),
        text: Text(
          paragraphs: [
            _paragraph(numbered, ' list_start=1 → shows 1', listStart: 1),
            _paragraph(
              numbered,
              " no list_start → also shows 1, because numbering doesn't "
              'continue',
            ),
            _paragraph(
              numbered,
              ' list_start=2 → shows 2 only when set explicitly',
              listStart: 2,
            ),
            _paragraph(bullet, 'Bullet at level 0, with list_level omitted'),
            _paragraph(bullet, 'Nested bullet at list_level=1', listLevel: 1),
            _paragraph(
              bullet,
              'Back to level 0, with list_level omitted again',
            ),
            _paragraph(null, 'Plain paragraph with no list_style at all'),
          ],
        ),
      ),
    ),
  );

  final imageBullet = _listStyle(imageLevels);
  final blockB = SlideObject(
    object: CanvasObject(
      textbox: Textbox(
        stroke: _noBorder,
        geometry: Geometry(
          position: Position(x: 1020, y: 280),
          size: Size(width: 770, height: 300),
        ),
        text: Text(
          paragraphs: [
            _paragraph(
              imageBullet,
              ' Image bullet with its resource in doc.resources',
              listStart: 1,
            ),
            _paragraph(
              imageBullet,
              ' Second image bullet at the same level, with the same resource',
            ),
          ],
        ),
      ),
    ),
  );

  final ruleBorder = BorderStyleType(
    stroke: Override.value(
      TextStroke(
        stroke: Stroke(
          line: Line(width: 2, color: Color(presetIdentifier: 'color_accent')),
        ),
      ),
    ),
    width: const Override.value(2),
    before: true,
  );
  final blockC = SlideObject(
    object: CanvasObject(
      textbox: Textbox(
        stroke: _noBorder,
        geometry: Geometry(
          position: Position(x: 1020, y: 680),
          size: Size(width: 770, height: 300),
        ),
        text: Text(
          paragraphs: [
            Paragraph(
              style: ParagraphProperties(borders: ruleBorder),
              contents: [
                Constituent(
                  run: TextRun(
                    string: 'Paragraph with a rule above (before=True)',
                    style: _bodyStyle,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  return Slide(
    contents: [title, headingA, headingB, headingC, blockA, blockB, blockC],
    background: Override.value(
      SlideBackground(standard: Fill(presetIdentifier: 'fill_slide_bg')),
    ),
  );
}

List<Preset> _presets() => [
  Preset('color_accent', {'rgba': _rgbaOrange.toJson()}),
  Preset('fill_slide_bg', {
    'color': {'rgba': _rgbaOffWhite.toJson()},
  }),
];

void main(List<String> args) {
  final parsed = parseArguments(
    args,
    script: 'lists',
    description:
        'Builds a presentation with bulleted, numbered, and image bullet '
        'lists, and a rule.',
    names: ['output'],
    defaults: [defaultOutput('lists.keyx')],
  );
  if (parsed == null) {
    return;
  }
  final [output] = parsed;
  final doc = KeyxDocument(
    Presentation(
      slideSize: Size(width: 1920, height: 1080),
      slides: [_slide()],
    ),
    presets: _presets(),
    resources: {'bullet.png': File(fixture('bullet.png')).readAsBytesSync()},
  );
  ensureParent(output);
  doc.save(output, preSaveHooks: [validateDocument]);
  reportSaved(output);
}
