// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python): the quick start of
// README.md.

/// Builds a presentation with one slide that holds a text box, and saves it
/// as `hello.keyx`, which you can open in Keynote.
///
/// ```sh
/// dart run example/main.dart [output]
/// ```
///
/// The output defaults to `hello.keyx` in a `creator_studio_document_examples`
/// directory in the system's temporary directory, and `--help` prints the
/// usage, as for the other scripts. The other scripts in this directory cover
/// each kind of slide content; see `example/README.md`.
library;

import 'dart:io';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';

import 'src/support.dart';

void main(List<String> args) {
  final parsed = parseArguments(
    args,
    script: 'main',
    description:
        'Builds a presentation with one slide that holds a text box, and '
        'saves it as hello.keyx, which you can open in Keynote.',
    names: ['output'],
    defaults: [defaultOutput('hello.keyx')],
  );
  if (parsed == null) {
    return;
  }
  final [output] = parsed;

  final title = Textbox(
    geometry: Geometry(
      position: Position(x: 160, y: 440),
      size: Size(width: 1600, height: 200),
    ),
    // `Textbox.stroke` defaults to a visible line; an empty stroke has none.
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
    slideSize: Size(width: 1920, height: 1080),
    slides: [slide],
  );

  // `validateDocument` checks the whole document, and throws before anything
  // is written if it breaks the format's rules.
  ensureParent(output);
  KeyxDocument(presentation).save(output, preSaveHooks: [validateDocument]);
  stdout.writeln('wrote $output');
}
