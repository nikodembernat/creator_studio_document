// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/test_cases.py.

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/src/validation/cases.dart';
import 'package:test/test.dart';

void main() {
  test('a lone case unwraps to its payload '
      '(test_unwrap_primary_case_lone_case)', () {
    final (name, model) = unwrapPrimaryCase(Chart(column: ColumnChart()));
    expect(name, 'column');
    expect(model, isA<ColumnChart>());
  });

  test('the primary case wins over declaration order '
      '(test_unwrap_primary_case_prefers_primary_over_declaration_order)', () {
    final chart = Chart.unionOf(
      'two_axis',
      column: ColumnChart(),
      twoAxis: TwoAxisChart(),
    );
    final (name, model) = unwrapPrimaryCase(chart);
    expect(name, 'two_axis');
    expect(model, isA<TwoAxisChart>());
  });
}
