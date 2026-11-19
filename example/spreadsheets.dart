// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// src/creator_studio_doc_format/examples/spreadsheets.py.

/// Builds a presentation with a financial table: cell formats, formulas, and
/// merges.
///
/// ```sh
/// dart run example/spreadsheets.dart [output]
/// ```
///
/// Styling is minimal, so the file stays focused on how the computation
/// works.
library;

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';

import 'src/support.dart';

final _rgbaAltRow = RGBA(red: 0.95, green: 0.95, blue: 0.97);

final _currencyFormat = CellFormat(
  formatType: FormatType.currency,
  currencyFormat: CurrencyFormat(
    decimalPlaces: 2,
    useThousandsSeparator: true,
    currencyCode: 'USD',
  ),
);
final _percentFormat = CellFormat(
  formatType: FormatType.percentage,
  numberFormat: NumberFormat(decimalPlaces: 1),
);

/// Returns a cell that pairs a formatted display string with its numeric
/// source.
///
/// The cell's `CellFormat` drives rendering, so the source is a raw number.
/// Currency passes the amount, such as `120000.0`, and percentage passes the
/// fraction, such as `0.30` for 30 percent.
Cell _valued(String display, double number, CellFormat cellFormat) => Cell(
  value: display,
  unformattedValue: UnformattedValue(number: number),
  cellFormat: cellFormat,
);

/// Builds a slide with cell formats, a formula by identifier, and a merged
/// banner.
Slide _slide1FormatsFormulasMerges() {
  final visual = VisualProperties(
    overallProperties: OverallProperties(behavesLikeSpreadsheet: true),
    footerRowCellProperties: CellProperties(
      fill: Override.value(Fill(presetIdentifier: 'fill_alt_row')),
    ),
  );

  final columnHeaders = [
    // Column widths take precedence over `geometry.size.width`, so they sum to
    // the table width.
    ColumnHeader(
      columnIdentifier: 'c_category',
      title: 'Category',
      columnWidth: 640,
    ),
    ColumnHeader(columnIdentifier: 'c_spend', title: 'Spend', columnWidth: 480),
    ColumnHeader(
      columnIdentifier: 'c_pct',
      title: '% of Budget',
      columnWidth: 480,
    ),
  ];

  final content = [
    Row(
      rowIdentifier: 'r_hdr',
      rowHeight: 60,
      cells: [for (final c in columnHeaders) Cell(value: c.title ?? '')],
    ),
    Row(
      rowIdentifier: 'r_ads',
      rowHeight: 68,
      cells: [
        Cell(value: 'Ads'),
        _valued(r'$120,000.00', 120000, _currencyFormat),
        _valued('30.0%', 0.30, _percentFormat),
      ],
    ),
    Row(
      rowIdentifier: 'r_events',
      rowHeight: 68,
      cells: [
        Cell(value: 'Events'),
        _valued(r'$60,000.00', 60000, _currencyFormat),
        _valued('15.0%', 0.15, _percentFormat),
      ],
    ),
    // The banner row. The merge below spans its first two columns, with the
    // content in the top-left cell and the other merged cells blank.
    Row(
      rowIdentifier: 'r_sub',
      rowHeight: 56,
      cells: [
        Cell(
          value: 'Marketing subtotal (see footer)',
          cellProperties: CellProperties(
            fill: Override.value(Fill(presetIdentifier: 'fill_alt_row')),
          ),
          // Replaces the table's text style rather than merging with it, so
          // it restates the size. The cell can still render smaller than the
          // rest of the table. A column's `textProperties`, as in
          // `tables.dart`, keeps the size.
          textProperties: ParagraphProperties(
            alignment: const Override.value(AlignmentType.center),
            characterProperties: CharacterProperties(
              fontSize: const Override.value(32),
            ),
          ),
        ),
        Cell(value: ''),
        Cell(value: ''),
      ],
    ),
    // Footer: `SUM` by identifier over the `"c_spend"` column of the two body
    // rows.
    Row(
      rowIdentifier: 'r_total',
      rowHeight: 68,
      cells: [
        Cell(value: 'TOTAL'),
        Cell(
          value: r'$180,000.00',
          unformattedValue: UnformattedValue(number: 180000),
          cellFormat: _currencyFormat,
          // References resolve against `rowIdentifier` and
          // `columnIdentifier`.
          formula: Formula(
            idBased: IdBasedFormula(
              expression: '=SUM({ref0})',
              references: [
                CellReference(
                  placeholder: '{ref0}',
                  displayNotation: 'B2:B3',
                  startRowIdentifier: 'r_ads',
                  startColumnIdentifier: 'c_spend',
                  endRowIdentifier: 'r_events',
                  endColumnIdentifier: 'c_spend',
                ),
              ],
            ),
          ),
        ),
        Cell(value: ''),
      ],
    ),
  ];

  // `CellRange` uses the identifiers from `content` and `columnHeaders`.
  final merges = [
    CellRange(
      rowColumnIdRange: RowColumnIdRange(
        topLeftRowIdentifier: 'r_sub',
        topLeftColumnIdentifier: 'c_category',
        bottomRightRowIdentifier: 'r_sub',
        bottomRightColumnIdentifier: 'c_spend',
      ),
    ),
  ];

  final table = Table(
    geometry: Geometry(
      position: Position(x: 160, y: 200),
      size: Size(width: 1600, height: 400),
    ),
    numberOfColumns: 3,
    numberOfRows: 5,
    numberOfHeaderRows: 1,
    numberOfFooterRows: 1,
    title: Label(text: Text(string: 'Q4 Marketing Budget')),
    visualProperties: visual,
    columnHeaders: columnHeaders,
    content: content,
    merges: merges,
  );
  return Slide(
    contents: [SlideObject(object: CanvasObject(table: table))],
  );
}

void main(List<String> args) {
  final parsed = parseArguments(
    args,
    script: 'spreadsheets',
    description:
        'Builds a presentation with a financial table: cell formats, '
        'formulas, and merges.',
    names: ['output'],
    defaults: [defaultOutput('spreadsheets.keyx')],
  );
  if (parsed == null) {
    return;
  }
  final [output] = parsed;
  final doc = KeyxDocument(
    Presentation(
      slideSize: Size(width: 1920, height: 1080),
      slides: [_slide1FormatsFormulasMerges()],
    ),
    presets: [
      Preset('fill_alt_row', {
        'color': {'rgba': _rgbaAltRow.toJson()},
      }),
    ],
  );
  ensureParent(output);
  doc.save(output, preSaveHooks: [validateDocument]);
  reportSaved(output);
}
