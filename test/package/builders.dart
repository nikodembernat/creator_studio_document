// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/builders.py, the builders the package tests use.

import 'dart:typed_data';

import 'package:creator_studio_document/creator_studio_document.dart';

/// The bytes of a PNG signature, which the tests store as a resource.
final png = Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
]);

Size slideSize() => Size(width: 1024, height: 768);

KeyxDocument emptyDoc() => KeyxDocument(
  Presentation(slideSize: slideSize(), slides: [Slide()]),
  presets: [],
);

KeyxDocument docWithIndirectImage(
  String filename, {
  String? identifier,
  String presetIdentifier = '',
  List<Preset>? presets,
}) {
  final indirect = IndirectResource(
    identifier: identifier,
    filename: filename,
    presetIdentifier: presetIdentifier,
  );
  final image = Image(resource: Resource(indirect: indirect));
  return KeyxDocument(
    Presentation(
      slideSize: slideSize(),
      slides: [
        Slide(
          contents: [SlideObject(object: CanvasObject(image: image))],
        ),
      ],
    ),
    presets: presets ?? [],
  );
}
