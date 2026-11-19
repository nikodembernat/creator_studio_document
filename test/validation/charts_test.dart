// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/test_charts.py.

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';
import 'package:test/test.dart';

import 'builders.dart';

Chart _twoAxis(List<ChartSeries> series) =>
    Chart(twoAxis: TwoAxisChart(series: series));

Chart _column(List<ChartSeries> series) =>
    Chart(column: ColumnChart(series: series));

Chart _mixed(List<ChartSeries> series) =>
    Chart(mixed: MixedChart(series: series));

void main() {
  test('a y-axis selection out of range is rejected '
      '(test_validate_detects_y_axis_selection_out_of_range)', () {
    final doc = docWithChart(
      _twoAxis([
        ChartSeries(seriesIndex: 0, yAxisSelection: 0),
        ChartSeries(seriesIndex: 1, yAxisSelection: 999),
      ]),
    );
    expect(
      () => validateDocument(doc),
      throwsValueError(
        "`ChartSeries.y_axis_selection` 999 isn't 0 or 1 (at "
        'slides[0].contents[0].object.chart.two_axis.series[1]'
        '.y_axis_selection)',
      ),
    );
  });

  test('selections 0 and 1 pass (test_two_axis_selection_0_and_1_ok)', () {
    final doc = docWithChart(
      _twoAxis([
        ChartSeries(seriesIndex: 0, yAxisSelection: 0),
        ChartSeries(seriesIndex: 1, yAxisSelection: 1),
      ]),
    );
    validateDocument(doc);
  });

  test('no selection passes (test_two_axis_selection_none_ok)', () {
    validateDocument(docWithChart(_twoAxis([ChartSeries(seriesIndex: 0)])));
  });

  test('a negative selection is out of range '
      '(test_two_axis_selection_negative_out_of_range)', () {
    final doc = docWithChart(
      _twoAxis([ChartSeries(seriesIndex: 0, yAxisSelection: -1)]),
    );
    expect(() => validateDocument(doc), throwsValueError("isn't 0 or 1"));
  });

  test("a chart that isn't two-axis isn't checked "
      '(test_non_two_axis_selection_is_not_checked)', () {
    validateDocument(
      docWithChart(_column([ChartSeries(seriesIndex: 0, yAxisSelection: 999)])),
    );
  });

  test("a mixed chart's y-axis selection isn't checked "
      '(test_mixed_chart_y_axis_selection_is_not_checked)', () {
    validateDocument(
      docWithChart(_mixed([ChartSeries(seriesIndex: 0, yAxisSelection: 999)])),
    );
  });
}
