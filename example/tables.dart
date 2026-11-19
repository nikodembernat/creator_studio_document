// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// src/creator_studio_doc_format/examples/tables.py.

/// Builds a presentation with styled tables.
///
/// ```sh
/// dart run example/tables.dart [output]
/// ```
library;

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';

import 'src/support.dart';

final _rgbaGrid = RGBA(red: 0.82, green: 0.83, blue: 0.86);
final _rgbaHeaderBackground = RGBA(red: 0.94, green: 0.94, blue: 0.96);
final _rgbaBorder = RGBA(red: 0.75, green: 0.76, blue: 0.80);
final _rgbaPositive = RGBA(red: 0.80, green: 0.92, blue: 0.82);
final _rgbaNegative = RGBA(red: 0.98, green: 0.85, blue: 0.85);
final _rgbaAltRow = RGBA(red: 0.95, green: 0.95, blue: 0.97);
final _rgbaWhite = RGBA(red: 1, green: 1, blue: 1);

// Each stroke's width and color live in its preset, built from these
// definitions.
final _strokes = {
  'stroke_grid': Stroke(
    line: Line(color: Color(rgba: _rgbaGrid), width: 0.5),
  ),
  'stroke_border': Stroke(
    line: Line(color: Color(rgba: _rgbaBorder), width: 1),
  ),
  'stroke_separator': Stroke(
    line: Line(color: Color(rgba: _rgbaBorder), width: 1.5),
  ),
};
final _strokeGrid = Stroke(presetIdentifier: 'stroke_grid');
final _strokeBorder = Stroke(presetIdentifier: 'stroke_border');
final _strokeSeparator = Stroke(presetIdentifier: 'stroke_separator');

/// Returns the strokes and fills the slides reference by identifier.
List<Preset> _presets() => [
  for (final MapEntry(key: name, value: stroke) in _strokes.entries)
    Preset(name, {
      // A preset holds only the properties of a `Stroke`, so the JSON leaves
      // out `type_identifier` and `version`.
      for (final MapEntry(:key, :value)
          in (stroke.toJson() as Map<String, Object?>).entries)
        if (key != 'type_identifier' && key != 'version') key: value,
    }),
  for (final (name, rgba) in [
    ('fill_header_bg', _rgbaHeaderBackground),
    ('fill_alt_row', _rgbaAltRow),
    ('fill_positive', _rgbaPositive),
    ('fill_negative', _rgbaNegative),
    ('fill_slide_bg', _rgbaWhite),
  ])
    Preset(name, {
      'color': {'rgba': rgba.toJson()},
    }),
];

final _cellHeader = CellProperties(
  fill: Override.value(Fill(presetIdentifier: 'fill_header_bg')),
  verticalAlignment: VerticalAlignmentType.center,
  padding: Insets(top: 8, bottom: 8, left: 12, right: 12),
);
final _cellBody = CellProperties(
  verticalAlignment: VerticalAlignmentType.center,
  padding: Insets(top: 8, bottom: 8, left: 12, right: 12),
);
final _textHeader = ParagraphProperties(
  alignment: const Override.value(AlignmentType.center),
  characterProperties: CharacterProperties(
    fontSize: const Override.value(32),
    bold: const Override.value(true),
  ),
);
final _textBody = ParagraphProperties(
  characterProperties: CharacterProperties(fontSize: const Override.value(32)),
);
final _textBodyCenter = ParagraphProperties(
  alignment: const Override.value(AlignmentType.center),
  characterProperties: CharacterProperties(fontSize: const Override.value(32)),
);

Cell _statusCell(String text, String fillPreset) => Cell(
  value: text,
  cellProperties: CellProperties(
    fill: Override.value(Fill(presetIdentifier: fillPreset)),
  ),
);

/// Builds a slide with a header row, alternating rows, and a `Label` title.
Slide _slide1Basics() {
  final visual = VisualProperties(
    overallProperties: OverallProperties(
      hasAlternatingRows: true,
      alternatingRowsFill: Override.value(
        Fill(presetIdentifier: 'fill_alt_row'),
      ),
    ),
    bodyStrokeProperties: BodyStrokeProperties(
      horizontalStroke: _strokeGrid,
      verticalStroke: _strokeGrid,
      horizontalBorderStroke: _strokeBorder,
      verticalBorderStroke: _strokeBorder,
    ),
    headerRowCellProperties: _cellHeader,
    headerRowTextProperties: _textHeader,
    headerRowStrokeProperties: HeaderFooterStrokeProperties(
      separatorStroke: _strokeSeparator,
      separatorVisible: true,
    ),
    bodyCellProperties: _cellBody,
    bodyTextProperties: _textBody,
  );

  final columnHeaders = [
    ColumnHeader(
      columnIdentifier: 'c_feature',
      title: 'Feature',
      columnWidth: 400,
    ),
    ColumnHeader(columnIdentifier: 'c_owner', title: 'Owner', columnWidth: 320),
    // The column sets the alignment because a cell's own `textProperties`
    // renders at a smaller size than the table's, even when it restates the
    // size.
    ColumnHeader(
      columnIdentifier: 'c_status',
      title: 'Status',
      columnWidth: 280,
      textProperties: _textBodyCenter,
    ),
    ColumnHeader(columnIdentifier: 'c_notes', title: 'Notes', columnWidth: 600),
  ];

  final content = [
    Row(
      rowIdentifier: 'r_hdr',
      rowHeight: 72,
      cells: [
        Cell(value: 'Feature'),
        Cell(value: 'Owner'),
        Cell(value: 'Status'),
        Cell(value: 'Notes'),
      ],
    ),
    Row(
      rowIdentifier: 'r1',
      rowHeight: 84,
      cells: [
        Cell(value: 'Feature A'),
        Cell(value: 'Alex'),
        _statusCell('Done', 'fill_positive'),
        Cell(value: 'Released last quarter'),
      ],
    ),
    Row(
      rowIdentifier: 'r2',
      rowHeight: 84,
      cells: [
        Cell(value: 'Feature B'),
        Cell(value: 'Sam'),
        _statusCell('Blocked', 'fill_negative'),
        Cell(value: 'Waiting on review'),
      ],
    ),
  ];

  final table = Table(
    geometry: Geometry(
      position: Position(x: 160, y: 260),
      size: Size(width: 1600, height: 240),
    ),
    numberOfColumns: 4,
    numberOfRows: 3,
    numberOfHeaderRows: 1,
    title: Label(text: Text(string: 'Q4 Feature Rollout')),
    visualProperties: visual,
    columnHeaders: columnHeaders,
    content: content,
  );
  return Slide(
    contents: [SlideObject(object: CanvasObject(table: table))],
    background: Override.value(
      SlideBackground(standard: Fill(presetIdentifier: 'fill_slide_bg')),
    ),
  );
}

void main(List<String> args) {
  final parsed = parseArguments(
    args,
    script: 'tables',
    description: 'Builds a presentation with styled tables.',
    names: ['output'],
    defaults: [defaultOutput('tables.keyx')],
  );
  if (parsed == null) {
    return;
  }
  final [output] = parsed;
  final doc = KeyxDocument(
    Presentation(
      slideSize: Size(width: 1920, height: 1080),
      slides: [_slide1Basics()],
    ),
    presets: _presets(),
  );
  ensureParent(output);
  doc.save(output, preSaveHooks: [validateDocument]);
  reportSaved(output);
}
