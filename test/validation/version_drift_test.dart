// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/test_version_drift.py.

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/src/validation/version_drift.dart';
import 'package:creator_studio_document/validation.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'builders.dart';

// The warnings that [body] logs, as `pytest.warns` records them.
List<DocumentVersionWarning> _warnings(void Function() body) {
  final seen = <DocumentVersionWarning>[];
  final subscription = Logger.root.onRecord.listen((r) {
    if (r.object case final DocumentVersionWarning w) {
      expect(r.level, Level.WARNING);
      expect(r.loggerName, 'creator_studio_document.validation');
      expect(r.message, w.message);
      seen.add(w);
    }
  });
  try {
    body();
  } finally {
    subscription.cancel();
  }
  return seen;
}

void main() {
  test('an unknown primary case warns (test_unknown_primary_case_warns)', () {
    final doc = docWithChart(
      Chart.fromJson({
        'column': <String, Object?>{},
        'super_axis': <String, Object?>{},
        'primary_case': 'super_axis',
      }),
    );
    final warnings = _warnings(() => validateDocument(doc));
    expect(warnings, hasLength(1));
    final w = warnings.single;
    expect(w.message, contains('super_axis'));
    expect(
      w.message,
      "`Chart` primary case 'super_axis' isn't implemented in this version of "
      'the library ($packageVersion), so `unionPrimary` reads '
      "'column' instead (at slides[0].contents[0].object.chart). Upgrade "
      '`creator_studio_document` to read and validate it.',
    );
    expect(w.model, 'Chart');
    expect(w.primary, 'super_axis');
    expect(w.fallback, 'column');
    expect(w.path, 'slides[0].contents[0].object.chart');
  });

  test("an unknown sibling of a known primary doesn't warn "
      '(test_unknown_sibling_with_known_primary_does_not_warn)', () {
    final doc = docWithChart(
      Chart.fromJson({
        'column': <String, Object?>{},
        'super_axis': <String, Object?>{},
      }),
    );
    expect(_warnings(() => validateDocument(doc)), isEmpty);
  });

  test('a clean document of the same version passes '
      '(test_clean_same_version_doc_passes)', () {
    final doc = docWithChart(Chart.fromJson({'column': <String, Object?>{}}));
    expect(_warnings(() => validateDocument(doc)), isEmpty);
  });

  // Upstream checks a `Chart.model_construct()` with no fields at all. A
  // Dart union always holds its cases; one with every case unset and no
  // primary designated is the nearest.
  test("a union without a primary isn't flagged "
      '(test_no_primary_not_flagged)', () {
    final chart = Chart(column: ColumnChart())..column = null;
    expect(_warnings(() => validateVersionDrift(chart)), isEmpty);
  });

  test('a union at the root names <root>', () {
    final chart = Chart.fromJson({
      'column': <String, Object?>{},
      'super_axis': <String, Object?>{},
      'primary_case': 'super_axis',
    });
    final warnings = _warnings(() => validateVersionDrift(chart));
    expect(warnings.single.message, contains('(at <root>)'));
  });

  test('an unknown lone primary reads no case', () {
    final chart = Chart.fromJson({
      'primary_case': 'super_axis',
      'preset_identifier': 'p',
    });
    final warnings = _warnings(() => validateVersionDrift(chart));
    expect(warnings.single.fallback, isNull);
    expect(warnings.single.message, contains('reads no case instead'));
  });

  test('a list or object primary case is unhashable, as upstream', () {
    // Upstream's `primary in known_cases` raises TypeError, so the document
    // is rejected rather than read through a fallback.
    for (final (primary, type) in [
      (<Object?>[], 'list'),
      (<Object?>['x'], 'list'),
      (<String, Object?>{}, 'dict'),
      ({'a': 1}, 'dict'),
    ]) {
      final doc = docWithChart(
        Chart.fromJson({
          'column': <String, Object?>{},
          'primary_case': primary,
        }),
      );
      final warnings = _warnings(
        () => expect(
          () => validateDocument(doc),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              "unhashable type: '$type'",
            ),
          ),
          reason: '$primary',
        ),
      );
      expect(warnings, isEmpty);
    }
  });

  test('a scalar primary case that is not a string warns', () {
    for (final (primary, spelled) in [(5, '5'), (true, 'True'), (1.5, '1.5')]) {
      final doc = docWithChart(
        Chart.fromJson({
          'column': <String, Object?>{},
          'primary_case': primary,
        }),
      );
      final warnings = _warnings(() => validateDocument(doc));
      expect(
        warnings.single.message,
        startsWith("`Chart` primary case $spelled isn't implemented"),
      );
    }
  });
}
