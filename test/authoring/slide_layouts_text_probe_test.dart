// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python),
// tests/authoring/test_slide_layouts_text_probe.py.

@TestOn('vm')
library;

import 'package:creator_studio_document/authoring.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/src/authoring/slide_layouts.dart'
    show firstText, livePlaceholders, placeholderName;
import 'package:test/test.dart';

const _fixture = 'test/fixtures/text_probe_typed.keyx';

Text _text(Slide slide, String name) {
  final obj = livePlaceholders(slide)
      .firstWhere((o) => placeholderName(o) == name);
  final text = firstText(obj);
  expect(text, isNotNull);
  return text!;
}

List<(int, String)> _typed(KeyxDocument doc) => [
  for (final (i, slide) in doc.presentation.slides.indexed)
    for (final o in livePlaceholders(slide))
      if (placeholderName(o) case final name? when firstText(o) != null)
        (i, name),
];

String _line(Paragraph paragraph) => [
  for (final c in paragraph.contents ?? const <Constituent>[])
    if (c.run case final run?) run.string,
].join();

void main() {
  final doc = KeyxDocument.open(_fixture);

  for (final (index, name) in _typed(doc)) {
    test('typed text matches Keynote: $index-$name', () {
      final theme = doc.presentation.theme;
      expect(theme, isNotNull);
      final saved = doc.presentation.slides[index];
      expect(saved.layout, isNotNull);
      final want = _text(saved, name).paragraphs ?? const <Paragraph>[];
      final lines = [for (final p in want) _line(p)];
      final levels = [for (final p in want) p.listLevel ?? 0];
      final made = slideFromLayout(theme!, saved.layout!);
      final empty = lines.length == 1 && lines.single.isEmpty;

      setSlidePlaceholderText(
        made,
        name,
        empty ? null : lines,
        listLevels: empty ? null : levels,
      );

      expect(_text(made, name).paragraphs, want);
    });
  }
}
