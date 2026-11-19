// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python),
// tests/authoring/test_slide_layouts.py.

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:test/test.dart';

/// The strings of the runs of [paragraphs], in order.
List<String?> paragraphRuns(List<Paragraph> paragraphs) => [
  for (final paragraph in paragraphs)
    for (final c in paragraph.contents ?? const <Constituent>[])
      if (c.run case final run?) run.string,
];

/// Matches an [ArgumentError] whose message matches [pattern].
Matcher throwsArgumentErrorMatching(String pattern) => throwsA(
  isArgumentError.having(
    (e) => '${e.message}',
    'message',
    matches(RegExp(pattern)),
  ),
);

/// Returns a deterministic identifier generator: `ID-1`, `ID-2`, and so on.
String Function() sequentialIdentifiers() {
  var next = 0;
  return () => 'ID-${++next}';
}
