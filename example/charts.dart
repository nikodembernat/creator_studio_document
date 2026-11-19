// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// src/creator_studio_doc_format/examples/charts.py.

/// Builds a presentation with a mixed chart, a pie chart, and a scatter chart.
///
/// ```sh
/// dart run example/charts.dart [output]
/// ```
///
/// The 26 cases of `Chart` fall into three axis arrangements. Switching
/// between cases in one arrangement changes one token. Switching arrangements
/// changes the axis fields:
///
///   - Bar, column, line, and area charts are cartesian. They use
///     `categoryAxis` and `valueAxis`, plus an optional `valueAxisSecondary`.
///   - Scatter and bubble charts use `valueAxisX` and `valueAxisY`, with no
///     category axis.
///   - Pie and donut charts are circular, with no axes at all.
///
/// The example builds one canonical chart per arrangement. `MixedChart` is
/// cartesian, with mixed series types on one frame. `PieChart` is circular,
/// and `ScatterChart` has two value axes.
library;

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';

import 'src/support.dart';

final _rgbaBrandBlue = RGBA(red: 0.12, green: 0.45, blue: 0.82);
final _rgbaBrandOrange = RGBA(red: 0.94, green: 0.55, blue: 0.20);
final _rgbaBrandTeal = RGBA(red: 0.20, green: 0.65, blue: 0.62);

// Series reference these fills through presets, so editing a preset recolors
// every series that uses it.
final brandBlue = Fill(presetIdentifier: 'fill_brand_blue');
final brandOrange = Fill(presetIdentifier: 'fill_brand_orange');
final brandTeal = Fill(presetIdentifier: 'fill_brand_teal');

const quarters = ['Q1 2026', 'Q2 2026'];

/// Wraps a 2D array of numbers in `ChartDataRow` and `ChartDataValue` models.
List<ChartDataRow> _rows(List<List<double>> values) => [
  for (final row in values)
    ChartDataRow(values: [for (final v in row) ChartDataValue(number: v)]),
];

// One geometry for all three chart slides.
// A chart's `Geometry` is its plot area. The axis labels, axis titles, chart
// title, and legend draw outside it, so a frame near a slide edge pushes them
// off the slide. With 32 to 40 pt axis text, leave about 150 pt on the left,
// 120 pt below, 135 pt above, and 20 to 30 pt on the right. Scale those
// margins with the text size.
final chartFrame = Geometry(
  position: Position(x: 200, y: 220),
  size: Size(width: 1520, height: 620),
);

ParagraphProperties _textStyle(double fontSize) => ParagraphProperties(
  characterProperties: CharacterProperties(fontSize: Override.value(fontSize)),
);

// Text sizes that stay legible on a 1920 x 1080 slide.
final titleStyle = _textStyle(48);
final secondaryTextStyle = _textStyle(40); // Captions and axis titles.
final axisLabelStyle = _textStyle(32);
final smallTextStyle = _textStyle(32); // The legend and value labels.

/// Builds a cartesian chart with two column series and a line series.
SlideObject _mixedChart() {
  final data = ChartData(
    chartDataSource: ChartDataSource.chartDataGrid,
    columnLabels: quarters,
    rowLabels: ['Bakery', 'Café', 'Catering'],
    rows: _rows([
      [42.1, 48.3],
      [38.5, 41.0],
      [12.4, 15.9],
    ]),
  );
  final bakery = ChartSeries(
    mixedSeriesType: MixedSeriesType.column,
    fill: Override.value(brandBlue),
  );
  final cafe = ChartSeries(
    mixedSeriesType: MixedSeriesType.column,
    fill: Override.value(brandOrange),
  );
  final catering = ChartSeries(
    mixedSeriesType: MixedSeriesType.line,
    fill: Override.value(brandTeal),
    symbolType: SeriesSymbolType.circle,
    symbolSize: 8,
  );
  final chart = MixedChart(
    title: Label(
      text: Text(string: r'Quarterly revenue by product ($M)'),
      paragraphProperties: titleStyle,
    ),
    caption: Label(
      text: Text(
        string:
            'FY2026 outlook: the bakery leads, and catering is gaining '
            'momentum.',
      ),
      paragraphProperties: secondaryTextStyle,
    ),
    data: data,
    series: [bakery, cafe, catering],
    categoryAxis: ChartCategoryAxis(
      title: 'Quarter',
      showTitle: true,
      titleTextStyle: secondaryTextStyle,
      labelTextStyle: axisLabelStyle,
    ),
    valueAxis: ChartValueAxis(
      title: r'Revenue ($M)',
      showTitle: true,
      titleTextStyle: secondaryTextStyle,
      labelTextStyle: axisLabelStyle,
    ),
    legend: ChartLegend(labelTextStyle: smallTextStyle),
    geometry: chartFrame,
  );
  return SlideObject(
    object: CanvasObject(chart: Chart(mixed: chart)),
  );
}

/// Builds a pie chart, which has no axes.
///
/// With `plotDirection: PlotDirection.columnsAsSeries`, each column is a
/// wedge and `series[i].fill` colors wedge `i`. The data is one row, and its
/// values line up with `columnLabels` and `series`.
SlideObject _pieChart() {
  final wedges = [
    ('Bakery', 34.2, brandBlue),
    ('Café', 28.1, brandOrange),
    ('Catering', 22.7, brandTeal),
  ];
  final data = ChartData(
    chartDataSource: ChartDataSource.chartDataGrid,
    plotDirection: PlotDirection.columnsAsSeries,
    columnLabels: [for (final (name, _, _) in wedges) name],
    rowLabels: ['Market share'],
    rows: [
      ChartDataRow(
        values: [for (final (_, v, _) in wedges) ChartDataValue(number: v)],
      ),
    ],
  );
  final series = [
    for (final (_, _, fill) in wedges)
      ChartSeries(
        fill: Override.value(fill),
        valueLabelTextStyle: smallTextStyle,
      ),
  ];
  final chart = PieChart(
    title: Label(
      text: Text(string: 'Category market share (Q4)'),
      paragraphProperties: titleStyle,
    ),
    caption: Label(
      text: Text(
        string:
            'The bakery remains dominant, and catering is narrowing the gap.',
      ),
      paragraphProperties: secondaryTextStyle,
    ),
    data: data,
    series: series,
    legend: ChartLegend(labelTextStyle: smallTextStyle),
    geometry: chartFrame,
  );
  return SlideObject(
    object: CanvasObject(chart: Chart(pie: chart)),
  );
}

/// Builds a scatter chart, which has an x and a y value axis and no category
/// axis.
///
/// With `plotDirection: PlotDirection.columnsAsSeries` and
/// `sharedXvalues: true`, each row is one data point. Column 0 holds the
/// shared X, and columns 1..K hold Y for each of the K series. Bubble charts
/// use the same layout, with each series taking a size column after its Y
/// column. A bubble's size comes from that value, not `symbolSize`.
SlideObject _scatterChart() {
  const points = [(8.0, 18.5), (21.0, 30.1), (33.0, 44.3)];
  final data = ChartData(
    chartDataSource: ChartDataSource.chartDataGrid,
    plotDirection: PlotDirection.columnsAsSeries,
    sharedXvalues: true,
    columnLabels: ['Ad spend', 'Revenue'],
    rows: [
      for (final (x, y) in points)
        ChartDataRow(
          values: [
            ChartDataValue(number: x),
            ChartDataValue(number: y),
          ],
        ),
    ],
  );
  final campaign = ChartSeries(
    fill: Override.value(brandTeal),
    symbolType: SeriesSymbolType.circle,
    symbolSize: 12,
  );
  final chart = ScatterChart(
    title: Label(
      text: Text(string: 'Revenue versus ad spend'),
      paragraphProperties: titleStyle,
    ),
    caption: Label(
      text: Text(string: 'Positive correlation across recent campaigns.'),
      paragraphProperties: secondaryTextStyle,
    ),
    data: data,
    series: [campaign],
    valueAxisX: ChartValueAxis(
      title: r'Ad spend ($M)',
      showTitle: true,
      titleTextStyle: secondaryTextStyle,
      labelTextStyle: axisLabelStyle,
    ),
    valueAxisY: ChartValueAxis(
      title: r'Revenue ($M)',
      showTitle: true,
      titleTextStyle: secondaryTextStyle,
      labelTextStyle: axisLabelStyle,
    ),
    legend: ChartLegend(labelTextStyle: smallTextStyle),
    geometry: chartFrame,
  );
  return SlideObject(
    object: CanvasObject(chart: Chart(scatter: chart)),
  );
}

/// Builds a rectangular frame with no fill.
///
/// Chart classes don't expose a border field, so a `Shape` with a thin line
/// at the same geometry acts as one.
SlideObject _border(Geometry frame) {
  final border = Shape(
    geometry: frame,
    stroke: Stroke(
      line: Line(
        color: Color(rgba: RGBA(red: 0.75, green: 0.75, blue: 0.78)),
        width: 1.5,
      ),
    ),
  );
  return SlideObject(object: CanvasObject(shape: border));
}

List<Preset> _presets() => [
  for (final (fill, rgba) in [
    (brandBlue, _rgbaBrandBlue),
    (brandOrange, _rgbaBrandOrange),
    (brandTeal, _rgbaBrandTeal),
  ])
    Preset(fill.presetIdentifier, {
      'color': {'rgba': rgba.toJson()},
    }),
];

List<Slide> _slides() => [
  Slide(contents: [_mixedChart()]),
  Slide(contents: [_border(chartFrame), _pieChart()]),
  Slide(contents: [_scatterChart()]),
];

void main(List<String> args) {
  final parsed = parseArguments(
    args,
    script: 'charts',
    description:
        'Builds a presentation with a mixed chart, a pie chart, and a scatter '
        'chart.',
    names: ['output'],
    defaults: [defaultOutput('charts.keyx')],
  );
  if (parsed == null) {
    return;
  }
  final [output] = parsed;
  final doc = KeyxDocument(
    Presentation(slideSize: Size(width: 1920, height: 1080), slides: _slides()),
    presets: _presets(),
  );
  ensureParent(output);
  doc.save(output, preSaveHooks: [validateDocument]);
  reportSaved(output);
}
