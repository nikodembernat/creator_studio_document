// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// src/creator_studio_doc_format/examples/basics.py.

/// Builds a presentation of one slide with presets, text, shapes, and an
/// image.
///
/// ```sh
/// dart run example/basics.dart [output]
/// ```
library;

import 'dart:io';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';

import 'src/support.dart';

// `_rgbaMoss` and `_rgbaOffWhite` feed the presets below. The slide references
// those presets through `Fill(presetIdentifier: …)`, so each color has one
// definition. `_rgbaDark` is used directly, for the slide's background and the
// hero overlay.
final _rgbaMoss = RGBA(red: 0.412, green: 0.510, blue: 0.106);
final _rgbaDark = RGBA(red: 0.05, green: 0.06, blue: 0.10);
final _rgbaOffWhite = RGBA(red: 0.96, green: 0.94, blue: 0.90);

/// Returns character, paragraph, and textbox presets, with a `base_text`
/// chain.
List<Preset> _presets() {
  final offWhiteJson = _rgbaOffWhite.toJson();
  return [
    Preset('fill_moss', {
      'color': {'rgba': _rgbaMoss.toJson()},
    }),
    Preset('fill_off_white', {
      'color': {'rgba': offWhiteJson},
    }),
    // `tracking` is a fraction of the em, not points, so `1.0` adds a full em
    // between letters.
    Preset('base_text', {'font_name': 'Helvetica Neue', 'tracking': 0.0}),
    Preset('title_text', parentIdentifier: 'base_text', {
      'font_name': 'Avenir Next Condensed',
      'font_size': 120,
      'bold': true,
      'character_fill': {
        'color': {'rgba': offWhiteJson},
      },
    }),
    Preset('subtitle_text', parentIdentifier: 'base_text', {
      'font_name': 'Helvetica Neue Light',
      'font_size': 32,
      'character_fill': {
        'color': {'rgba': offWhiteJson},
      },
    }),
    Preset('para_left', {
      'alignment': 'left',
      'line_spacing': {'value': 1.0, 'kind': 'relative'},
    }),
    Preset('para_right', {
      'alignment': 'right',
      'line_spacing': {'value': 1.0, 'kind': 'relative'},
    }),
    // One preset gives every textbox the same border, shadow, and text layout.
    // Each textbox adopts it through `presetIdentifier`.
    Preset('textbox_base', {
      'stroke': 'empty',
      'shadow': 'none',
      'layout_properties': {
        'shrink_to_fit': true,
        'padding': {'top': 0, 'bottom': 0, 'left': 0, 'right': 0},
        // Use `"center"`, not `"middle"`.
        'vertical_alignment': 'center',
      },
    }),
    // `Shape.stroke` defaults to a visible `Line`, so this preset sets
    // `"empty"` to draw shapes without an outline.
    Preset('shape_base', {'stroke': 'empty'}),
  ];
}

/// Builds one slide that uses every feature this example covers.
Slide _slide() {
  final background = Fill(color: Color(rgba: _rgbaDark));

  // `Group.children` takes `CanvasObject` directly, with no `SlideObject`
  // wrapper.
  final heroImage = CanvasObject(
    image: Image(
      geometry: Geometry(
        position: Position(x: 0, y: -567),
        size: Size(width: 1920, height: 1267),
      ),
      resource: Resource(indirect: IndirectResource(filename: 'hero.png')),
    ),
  );
  final heroOverlay = CanvasObject(
    shape: Shape(
      presetIdentifier: 'shape_base',
      geometry: Geometry(
        position: Position(x: 0, y: 350),
        size: Size(width: 1920, height: 350),
      ),
      fill: Fill(
        gradient: Gradient(
          stops: [
            Stop(
              color: Color(rgba: _rgbaDark.deepCopy()..alpha = 0),
              fraction: 0,
            ),
            Stop(color: Color(rgba: _rgbaDark), fraction: 0.75),
            Stop(color: Color(rgba: _rgbaDark), fraction: 1),
          ],
          flavor: Flavor(linear: Linear(angle: 270)),
        ),
      ),
    ),
  );
  final heroStack = SlideObject(
    object: CanvasObject(
      group: Group(
        title: Label(
          text: Text(string: 'Hero'),
          paragraphProperties: ParagraphProperties(
            alignment: const Override.value(AlignmentType.center),
            characterProperties: CharacterProperties(
              fontSize: const Override.value(14),
              characterFill: Override.value(
                Fill(presetIdentifier: 'fill_off_white'),
              ),
            ),
          ),
        ),
        caption: Label(
          text: Text(string: 'Caption hidden on the slide'),
          isVisible: false,
        ),
        children: [heroImage, heroOverlay],
      ),
    ),
  );

  final divider = SlideObject(
    object: CanvasObject(
      shape: Shape(
        presetIdentifier: 'shape_base',
        geometry: Geometry(
          position: Position(x: 130, y: 900),
          size: Size(width: 20, height: 20),
        ),
        path: Path(
          bezier: BezierPath(
            path: 'M 0.5,0 L 1,0.5 L 0.5,1 L 0,0.5 Z',
            space: Rect(
              position: Position(x: 0, y: 0),
              size: Size(width: 1, height: 1),
            ),
          ),
        ),
        fill: Fill(presetIdentifier: 'fill_moss'),
      ),
    ),
  );

  final titleRun = TextRun(
    string: 'Kyoto',
    style: CharacterProperties(presetIdentifier: 'title_text'),
  );
  final subtitleRun = TextRun(
    string: 'Where tradition ',
    style: CharacterProperties(presetIdentifier: 'subtitle_text'),
  );
  final subtitleAccentRun = TextRun(
    string: 'meets quiet beauty.',
    style: CharacterProperties(
      presetIdentifier: 'subtitle_text',
      italic: const Override.value(true),
      characterFill: Override.value(Fill(presetIdentifier: 'fill_moss')),
    ),
  );
  // Both lines share the `"para_left"` alignment, so the textbox sets it once
  // as its default instead of repeating it on each `Paragraph.style`. A
  // paragraph needs its own `style` only when it differs from that default.
  final titleParagraph = Paragraph(contents: [Constituent(run: titleRun)]);
  final subtitleParagraph = Paragraph(
    contents: [
      Constituent(run: subtitleRun),
      Constituent(run: subtitleAccentRun),
    ],
  );
  final titleBox = SlideObject(
    object: CanvasObject(
      textbox: Textbox(
        presetIdentifier: 'textbox_base',
        geometry: Geometry(
          position: Position(x: 130, y: 640),
          size: Size(width: 1700, height: 240),
        ),
        paragraphProperties: ParagraphProperties(presetIdentifier: 'para_left'),
        // `Text.paragraphs` carries the line break between title and subtitle.
        text: Text(paragraphs: [titleParagraph, subtitleParagraph]),
      ),
    ),
  );

  // `textRuns` skips the `Paragraph`/`Constituent` wrapping that `paragraphs`
  // requires, which suits a single run with no list or paragraph break.
  final footerRun = TextRun(
    string: 'EST. 794  ·  THE ANCIENT CAPITAL',
    style: CharacterProperties(
      fontSize: const Override.value(18),
      characterFill: Override.value(Fill(presetIdentifier: 'fill_off_white')),
    ),
  );
  final footer = SlideObject(
    object: CanvasObject(
      textbox: Textbox(
        presetIdentifier: 'textbox_base',
        geometry: Geometry(
          position: Position(x: 130, y: 970),
          size: Size(width: 1660, height: 40),
        ),
        paragraphProperties: ParagraphProperties(
          presetIdentifier: 'para_right',
        ),
        text: Text(textRuns: [footerRun]),
      ),
    ),
  );

  return Slide(
    background: Override.value(SlideBackground(standard: background)),
    contents: [heroStack, divider, titleBox, footer],
    // Presenter notes are a plain `Text` on the slide, not a canvas object.
    note: Text(string: "Open on the photo, then land the 'quiet beauty' line."),
  );
}

void main(List<String> args) {
  final parsed = parseArguments(
    args,
    script: 'basics',
    description:
        'Builds a presentation of one slide with presets, text, shapes, and '
        'an image.',
    names: ['output'],
    defaults: [defaultOutput('basics.keyx')],
  );
  if (parsed == null) {
    return;
  }
  final [output] = parsed;
  final doc = KeyxDocument(
    Presentation(
      theme: KeynoteTheme(name: 'White', locale: 'en_US'),
      slideSize: Size(width: 1920, height: 1080),
      slides: [_slide()],
    ),
    presets: _presets(),
    resources: {
      'hero.png': File(fixture('photo_placeholder.png')).readAsBytesSync(),
    },
  );
  ensureParent(output);
  doc.save(output, preSaveHooks: [validateDocument]);
  reportSaved(output);
}
