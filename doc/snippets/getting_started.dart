// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// docs/snippets/getting_started.py.

/// The code of the guide's "Getting started" section of `README.md`.
///
/// Each `// [name]` … `// [/name]` region is a code block of the guide, and
/// `test/examples/snippets_test.dart` runs this file in a directory that holds
/// the files it reads.
library;

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';

void create() {
  // [create]
  final title = Textbox(
    geometry: Geometry(
      position: Position(x: 160, y: 440),
      size: Size(width: 1600, height: 200),
    ),
    stroke: Stroke(empty: true),
    layoutProperties: LayoutProperties(
      verticalAlignment: const Override.value(VerticalAlignmentType.center),
    ),
    paragraphProperties: ParagraphProperties(
      alignment: const Override.value(AlignmentType.center),
      characterProperties: CharacterProperties(
        fontSize: const Override.value(96),
      ),
    ),
    text: Text(string: 'Hello, Keynote'),
  );
  final slide = Slide(
    contents: [SlideObject(object: CanvasObject(textbox: title))],
  );

  final presentation = Presentation(
    // Without a theme, Keynote uses White in the system locale. The name is
    // localized, so pair it with a locale.
    theme: KeynoteTheme(name: 'White', locale: 'en_US'),
    // Without a slide size, Keynote has to supply one, such as the theme's,
    // or reject the document.
    slideSize: Size(width: 1920, height: 1080),
    slides: [slide],
  );

  KeyxDocument(presentation).save('hello.keyx');
  // [/create]
}

void edit() {
  // [edit]
  final doc = KeyxDocument.open('hello.keyx');
  final first = doc.presentation.slides[0]; // Read.
  doc.presentation.slides.add(Slide()); // Construct.

  first
    // Assign.
    ..note = Text(string: 'Welcome everyone, then move on.')
    // Delete.
    ..contents!.removeAt(0);

  doc.save('edited.keyx', preSaveHooks: [validateDocument]);
  // [/edit]
}

void main() {
  create();
  edit();
}
