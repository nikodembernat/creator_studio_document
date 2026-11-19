// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// docs/snippets/adding_objects.py.

/// The code of the guide's "Adding content to a slide" section of
/// `README.md`.
///
/// Each `// [name]` … `// [/name]` region is a code block of the guide, and
/// `test/examples/snippets_test.dart` runs this file in a directory that holds
/// the files it reads. After the regions run, [main] puts what they built on
/// slides and saves the documents with `validateDocument`.
library;

import 'dart:io';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';

(Fill, Stroke) union() {
  // [union]
  // `Fill.color` holds a `Color`, which is itself a union.
  final red = Fill(
    color: Color(rgba: RGBA(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)),
  );
  final noBorder = Stroke(empty: true); // A case with no payload takes `true`.
  // [/union]

  // [union-primary]
  final description = switch (red.unionPrimary()) {
    FillColorCase(:final payload) => 'solid $payload',
    FillGradientCase() => 'gradient',
    FillImageCase() => 'image',
    null => 'none',
  };
  // [/union-primary]
  stdout.writeln(description);
  return (red, noBorder);
}

Slide text() {
  // [text]
  final plain = Text(string: 'Stargazing Tips');
  final styled = Text(
    textRuns: [
      TextRun(
        string: 'Full moon',
        style: CharacterProperties(bold: const Override.value(true)),
      ),
    ],
  );
  final lines = Text(
    paragraphs: [
      Paragraph(
        contents: [Constituent(run: TextRun(string: 'First line'))],
      ),
      Paragraph(
        contents: [Constituent(run: TextRun(string: 'Second line'))],
      ),
    ],
  );

  // A content object goes on a slide inside a `SlideObject` and a
  // `CanvasObject`.
  final slide = Slide(
    contents: [
      SlideObject(
        object: CanvasObject(textbox: Textbox(text: plain)),
      ),
    ],
  );
  // [/text]
  slide.contents!.addAll([
    for (final t in [styled, lines])
      SlideObject(
        object: CanvasObject(textbox: Textbox(text: t)),
      ),
  ]);
  return slide;
}

Shape shape() {
  // [shape]
  final unitBox = Rect(
    position: Position(x: 0, y: 0),
    size: Size(width: 1, height: 1),
  );
  const oval = 'M 0,0.5 A 0.5,0.5 0 1 1 1,0.5 A 0.5,0.5 0 1 1 0,0.5 Z';

  final shape = Shape(
    identifier: 'oval',
    geometry: Geometry(
      position: Position(x: 1000, y: 200),
      size: Size(width: 180, height: 180),
    ),
    path: Path(
      bezier: BezierPath(path: oval, space: unitBox),
    ),
  );
  // [/shape]
  return shape;
}

(KeyxDocument, Image) image() {
  // [image]
  final doc = KeyxDocument.open('presentation.keyx');
  final pngBytes = File('cover.png').readAsBytesSync();

  final name = doc.resources.uniqueFilename('cover.png');
  doc.resources[name] = pngBytes;
  final image = Image(
    resource: Resource(
      indirect: IndirectResource(identifier: name, filename: 'cover.png'),
    ),
    geometry: Geometry(
      position: Position(x: 160, y: 120),
      size: Size(width: 600, height: 396),
    ),
  );
  doc.presentation.slides.add(
    Slide(
      contents: [SlideObject(object: CanvasObject(image: image))],
    ),
  );
  // [/image]
  return (doc, image);
}

Table table() {
  // [table]
  Cell revenueCell(int millions) => Cell(
    value: '$millions',
    unformattedValue: UnformattedValue(number: millions.toDouble()),
  );

  final table = Table(
    geometry: Geometry(
      position: Position(x: 160, y: 260),
      size: Size(width: 800, height: 160),
    ),
    numberOfRows: 2,
    numberOfColumns: 2,
    columnHeaders: [
      ColumnHeader(columnIdentifier: 'product'),
      ColumnHeader(columnIdentifier: 'revenue'),
    ],
    content: [
      Row(
        rowIdentifier: 'coffee',
        cells: [
          Cell(value: 'Coffee'),
          revenueCell(41),
        ],
      ),
      Row(
        rowIdentifier: 'tea',
        cells: [
          Cell(value: 'Tea'),
          revenueCell(12),
        ],
      ),
    ],
  );
  // [/table]
  return table;
}

Chart chart() {
  // [chart]
  final revenue = ChartData(
    chartDataSource: ChartDataSource.chartDataGrid,
    plotDirection: PlotDirection.rowsAsSeries,
    rowLabels: ['Coffee', 'Tea'],
    columnLabels: ['Q1', 'Q2', 'Q3'],
    rows: [
      ChartDataRow(
        values: [
          for (final n in [42.1, 48.3, 51.0]) ChartDataValue(number: n),
        ],
      ),
      ChartDataRow(
        values: [
          for (final n in [38.5, 41.0, 44.2]) ChartDataValue(number: n),
        ],
      ),
    ],
  );
  final chart = Chart(
    column: ColumnChart(
      data: revenue,
      geometry: Geometry(
        position: Position(x: 160, y: 200),
        size: Size(width: 1200, height: 700),
      ),
    ),
  );
  // [/chart]
  return chart;
}

ConnectionLine connectionLine() {
  // [connection-line]
  final arrow = ConnectionLine(
    tail: End(endPoint: Position(x: 450, y: 290)),
    head: End(
      endPoint: Position(x: 1090, y: 290),
      anchor: Anchor(objectId: 'oval'),
      lineEnd: LineEnd.filledArrow,
    ),
  );
  // [/connection-line]
  return arrow;
}

(KeyxDocument, TextRun, TextRun) preset() {
  // [preset]
  final doc = KeyxDocument.open('presentation.keyx');
  doc.presets.addAll([
    Preset('body', {'font_name': 'Helvetica Neue', 'font_size': 24}),
    // The title inherits `font_name` from the body.
    Preset('title', {'font_size': 48, 'bold': true}, parentIdentifier: 'body'),
  ]);

  // A model adopts a preset through `presetIdentifier`.
  final heading = TextRun(
    string: 'Baking Sourdough',
    style: CharacterProperties(presetIdentifier: 'title'),
  );
  final step = TextRun(
    string: 'Feed the starter',
    style: CharacterProperties(presetIdentifier: 'body'),
  );
  // [/preset]
  return (doc, heading, step);
}

void main() {
  final (red, noBorder) = union();
  final textSlide = text();
  final oval = shape()
    ..fill = red
    ..stroke = noBorder;
  final (doc, cover) = image();
  final objects = Slide(
    contents: [
      for (final object in [
        CanvasObject(shape: oval),
        CanvasObject(image: cover),
        CanvasObject(table: table()),
        CanvasObject(chart: chart()),
        CanvasObject(connectionLine: connectionLine()),
      ])
        SlideObject(object: object),
    ],
  );
  doc.presentation.slides.addAll([textSlide, objects]);
  doc.save('objects.keyx', preSaveHooks: [validateDocument]);

  final (styledDoc, heading, step) = preset();
  styledDoc.presentation.slides.add(
    Slide(
      contents: [
        SlideObject(
          object: CanvasObject(
            textbox: Textbox(text: Text(textRuns: [heading, step])),
          ),
        ),
      ],
    ),
  );
  styledDoc.save('styled.keyx', preSaveHooks: [validateDocument]);
}
