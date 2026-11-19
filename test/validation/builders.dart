// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/builders.py.

import 'dart:typed_data';

import 'package:creator_studio_document/creator_studio_document.dart'
    hide Pattern;
import 'package:creator_studio_document/validation.dart';
import 'package:test/test.dart';

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

KeyxDocument docWithSlideLayout(SlideLayout slideLayout) => KeyxDocument(
  Presentation(
    slideSize: slideSize(),
    slides: [Slide()],
    theme: KeynoteTheme(slideLayouts: [slideLayout]),
  ),
  presets: [],
);

KeyxDocument docWithTables(List<Table> tables) => KeyxDocument(
  Presentation(
    slideSize: slideSize(),
    slides: [
      Slide(
        contents: [
          for (final t in tables) SlideObject(object: CanvasObject(table: t)),
        ],
      ),
    ],
  ),
  presets: [],
);

KeyxDocument docWithChart(Chart chart) => KeyxDocument(
  Presentation(
    slideSize: slideSize(),
    slides: [
      Slide(
        contents: [SlideObject(object: CanvasObject(chart: chart))],
      ),
    ],
  ),
  presets: [],
);

Slide slideWithHyperlink(SlideTarget target) => Slide(
  note: Text(
    paragraphs: [
      Paragraph(
        contents: [
          Constituent(
            hyperlink: HyperlinkField(
              target: Hyperlink(slideJump: target),
              run: TextRun(string: 'jump'),
            ),
          ),
        ],
      ),
    ],
  ),
);

/// Matches a [DocumentValueError], upstream's `ValueError`, whose message
/// matches [pattern], as `pytest.raises(ValueError, match=...)` checks it.
Matcher throwsValueError([Pattern? pattern]) =>
    throwsA(_withMessage(isA<DocumentValueError>(), pattern));

/// Matches a [DocumentReferenceError], upstream's `LookupError`, whose
/// message matches [pattern].
Matcher throwsLookupError([Pattern? pattern]) =>
    throwsA(_withMessage(isA<DocumentReferenceError>(), pattern));

TypeMatcher<T> _withMessage<T extends DocumentValidationError>(
  TypeMatcher<T> matcher,
  Pattern? pattern,
) => pattern == null
    ? matcher
    : matcher.having(
        (e) => e.message,
        'message',
        pattern is String ? contains(pattern) : matches(pattern),
      );
