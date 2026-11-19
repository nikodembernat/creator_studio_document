// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/test_tables.py.

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';
import 'package:test/test.dart';

import 'builders.dart';

TableConditionalStyleSetRule _rule() => TableConditionalStyleSetRule(
  predicate: Predicate(predicateType: PredicateType.duplicates),
);

Table _mergedTable(CellRange merge) => Table(
  numberOfColumns: 2,
  numberOfRows: 2,
  columnHeaders: [
    ColumnHeader(columnIdentifier: 'c1'),
    ColumnHeader(columnIdentifier: 'c2'),
  ],
  content: [
    Row(rowIdentifier: 'r1'),
    Row(rowIdentifier: 'r2'),
  ],
  merges: [merge],
);

CellRange _merge(
  String topRow,
  String topColumn,
  String bottomRow,
  String bottomColumn,
) => CellRange(
  rowColumnIdRange: RowColumnIdRange(
    topLeftRowIdentifier: topRow,
    topLeftColumnIdentifier: topColumn,
    bottomRightRowIdentifier: bottomRow,
    bottomRightColumnIdentifier: bottomColumn,
  ),
);

Table _oneCell({
  Cell? cell,
  List<CustomFormat>? customFormats,
  List<ConditionalStyleSet>? conditionalStyleSets,
}) => Table(
  numberOfColumns: 1,
  numberOfRows: 1,
  content: [
    Row(cells: [cell ?? Cell(value: 'a')]),
  ],
  customFormats: customFormats,
  conditionalStyleSets: conditionalStyleSets,
);

void main() {
  test('a duplicate column identifier is rejected '
      '(test_validate_detects_duplicate_column_identifier)', () {
    final doc = docWithTables([
      Table(
        numberOfColumns: 2,
        numberOfRows: 1,
        columnHeaders: [
          ColumnHeader(columnIdentifier: 'dup'),
          ColumnHeader(columnIdentifier: 'dup'),
        ],
        content: [
          Row(
            cells: [
              Cell(value: 'a'),
              Cell(value: 'b'),
            ],
          ),
        ],
      ),
    ]);
    expect(
      () => validateDocument(doc),
      throwsValueError(
        "`ColumnHeader.column_identifier` 'dup' is a duplicate within the "
        'table (at slides[0].contents[0].object.table.column_headers[1]). The '
        'first is at slides[0].contents[0].object.table.column_headers[0].',
      ),
    );
  });

  test('a duplicate row identifier is rejected '
      '(test_validate_detects_duplicate_row_identifier)', () {
    final doc = docWithTables([
      Table(
        numberOfColumns: 1,
        numberOfRows: 2,
        content: [
          Row(rowIdentifier: 'dup'),
          Row(rowIdentifier: 'dup'),
        ],
      ),
    ]);
    expect(
      () => validateDocument(doc),
      throwsValueError(RegExp('`Row.row_identifier` .* is a duplicate')),
    );
  });

  test('a duplicate custom format identifier is rejected '
      '(test_validate_detects_duplicate_custom_format_identifier)', () {
    final doc = docWithTables([
      _oneCell(
        customFormats: [
          CustomFormat(identifier: 'dup', formatString: '#'),
          CustomFormat(identifier: 'dup', formatString: '0'),
        ],
      ),
    ]);
    expect(
      () => validateDocument(doc),
      throwsValueError(RegExp('`CustomFormat.identifier` .* is a duplicate')),
    );
  });

  test('a duplicate conditional style set identifier is rejected '
      '(test_validate_detects_duplicate_conditional_style_set_identifier)', () {
    final doc = docWithTables([
      _oneCell(
        conditionalStyleSets: [
          ConditionalStyleSet(identifier: 'dup', rules: [_rule()]),
          ConditionalStyleSet(identifier: 'dup', rules: [_rule()]),
        ],
      ),
    ]);
    expect(
      () => validateDocument(doc),
      throwsValueError(
        RegExp('`ConditionalStyleSet.identifier` .* is a duplicate'),
      ),
    );
  });

  test('absent and distinct identifiers pass '
      '(test_validate_allows_none_identifiers_and_distinct_identifiers)', () {
    validateDocument(
      docWithTables([
        Table(
          numberOfColumns: 2,
          numberOfRows: 2,
          columnHeaders: [
            ColumnHeader(columnIdentifier: 'a'),
            ColumnHeader(),
          ],
          content: [
            Row(),
            Row(rowIdentifier: 'r1'),
          ],
        ),
      ]),
    );
  });

  test("a cell's conditional style set resolves "
      '(test_validate_cell_conditional_style_set_identifier_resolves)', () {
    validateDocument(
      docWithTables([
        _oneCell(
          cell: Cell(value: 'a', conditionalStyleSetIdentifier: 'cs1'),
          conditionalStyleSets: [
            ConditionalStyleSet(identifier: 'cs1', rules: [_rule()]),
          ],
        ),
      ]),
    );
  });

  test(
    "a cell's dangling conditional style set is rejected "
    '(test_validate_cell_conditional_style_set_identifier_dangling_raises)',
    () {
      final doc = docWithTables([
        _oneCell(
          cell: Cell(value: 'a', conditionalStyleSetIdentifier: 'ghost'),
          conditionalStyleSets: [
            ConditionalStyleSet(identifier: 'cs1', rules: [_rule()]),
          ],
        ),
      ]);
      expect(
        () => validateDocument(doc),
        throwsLookupError(
          "`Cell.conditional_style_set_identifier` 'ghost' matches no "
          '`ConditionalStyleSet` (at slides[0].contents[0].object.table'
          '.content[0].cells[0].conditional_style_set_identifier)',
        ),
      );
    },
  );

  test('a dangling custom format identifier is rejected '
      '(test_validate_custom_format_identifier_dangling_raises)', () {
    final doc = docWithTables([
      _oneCell(
        cell: Cell(
          value: '42',
          cellFormat: CellFormat(
            formatType: FormatType.custom,
            customFormatIdentifier: 'format-that-never-was',
          ),
        ),
      ),
    ]);
    expect(
      () => validateDocument(doc),
      throwsLookupError(
        "`CellFormat.custom_format_identifier` 'format-that-never-was' "
        'matches no `CustomFormat` (at slides[0].contents[0].object.table'
        '.content[0].cells[0].cell_format.custom_format_identifier)',
      ),
    );
  });

  test('a custom format identifier resolves '
      '(test_validate_custom_format_identifier_resolves)', () {
    validateDocument(
      docWithTables([
        _oneCell(
          cell: Cell(
            value: '42',
            cellFormat: CellFormat(
              formatType: FormatType.custom,
              customFormatIdentifier: 'fmt1',
            ),
          ),
          customFormats: [CustomFormat(identifier: 'fmt1', formatString: '#')],
        ),
      ]),
    );
  });

  test("a custom format identifier on a format that isn't custom isn't "
      'checked (test_validate_custom_format_identifier_on_non_custom_format_'
      'is_not_checked)', () {
    validateDocument(
      docWithTables([
        _oneCell(
          cell: Cell(
            value: '42',
            cellFormat: CellFormat(
              formatType: FormatType.number,
              customFormatIdentifier: 'dropped',
            ),
          ),
        ),
      ]),
    );
  });

  test('a merged range resolves (test_validate_merged_range_resolves)', () {
    validateDocument(
      docWithTables([_mergedTable(_merge('r1', 'c1', 'r2', 'c2'))]),
    );
  });

  test('a merged range with a dangling row is rejected '
      '(test_validate_merged_range_dangling_row_identifier_raises)', () {
    expect(
      () => validateDocument(
        docWithTables([_mergedTable(_merge('r1', 'c1', 'ghost-row', 'c2'))]),
      ),
      throwsLookupError(
        "`RowColumnIdRange.bottom_right_row_identifier` 'ghost-row' matches "
        'no `Row.row_identifier` (at slides[0].contents[0].object.table'
        '.merges[0].row_column_id_range.bottom_right_row_identifier)',
      ),
    );
  });

  test('a merged range with a dangling column is rejected '
      '(test_validate_merged_range_dangling_column_identifier_raises)', () {
    expect(
      () => validateDocument(
        docWithTables([_mergedTable(_merge('r1', 'ghost-col', 'r2', 'c2'))]),
      ),
      throwsLookupError(
        "`RowColumnIdRange.top_left_column_identifier` 'ghost-col' matches "
        'no `ColumnHeader.column_identifier` (at slides[0].contents[0].object'
        '.table.merges[0].row_column_id_range.top_left_column_identifier)',
      ),
    );
  });

  test('a merged range with swapped rows is rejected '
      '(test_validate_merged_range_rejects_swapped_row_order)', () {
    expect(
      () => validateDocument(
        docWithTables([_mergedTable(_merge('r2', 'c1', 'r1', 'c2'))]),
      ),
      throwsValueError(
        "`RowColumnIdRange` top-left corner ('r2', 'c1') sits after its "
        "bottom-right corner ('r1', 'c2') (at slides[0].contents[0].object"
        '.table.merges[0].row_column_id_range)',
      ),
    );
  });

  test('a merged range with swapped columns is rejected '
      '(test_validate_merged_range_rejects_swapped_column_order)', () {
    expect(
      () => validateDocument(
        docWithTables([_mergedTable(_merge('r1', 'c2', 'r2', 'c1'))]),
      ),
      throwsValueError('sits after its bottom-right corner'),
    );
  });

  test("a base table isn't validated "
      '(test_validate_base_table_is_not_validated)', () {
    final base = Table(
      numberOfColumns: 2,
      numberOfRows: 1,
      columnHeaders: [
        ColumnHeader(columnIdentifier: 'dup'),
        ColumnHeader(columnIdentifier: 'dup'),
      ],
      content: [Row(rowIdentifier: 'br1')],
    );
    final top = Table(
      numberOfColumns: 1,
      numberOfRows: 1,
      content: [Row(rowIdentifier: 'tr1')],
      transformation: TransformationInfo(baseTable: base),
    );
    validateDocument(docWithTables([top]));
  });

  test('an out-of-range row index is rejected '
      '(test_validate_rejects_out_of_range_row_index)', () {
    final doc = docWithTables([
      Table(
        numberOfColumns: 1,
        numberOfRows: 2,
        content: [Row(rowIndex: 5, rowIdentifier: 'r1')],
      ),
    ]);
    expect(
      () => validateDocument(doc),
      throwsValueError(
        '`Row.row_index` 5 is out of range [0, 2) (at '
        'slides[0].contents[0].object.table.content[0].row_index)',
      ),
    );
  });

  test('a reversed row index is rejected '
      '(test_validate_rejects_reversed_row_index)', () {
    final doc = docWithTables([
      Table(
        numberOfColumns: 1,
        numberOfRows: 3,
        content: [
          Row(rowIndex: 2, rowIdentifier: 'r1'),
          Row(rowIndex: 1, rowIdentifier: 'r2'),
        ],
      ),
    ]);
    expect(
      () => validateDocument(doc),
      throwsValueError(
        "`Row.row_index` 1 isn't greater than the previous row's index 2 (at "
        'slides[0].contents[0].object.table.content[1].row_index). List rows '
        'in strictly ascending order of index.',
      ),
    );
  });

  test('a duplicate row index is rejected '
      '(test_validate_rejects_duplicate_row_index)', () {
    final doc = docWithTables([
      Table(
        numberOfColumns: 1,
        numberOfRows: 3,
        content: [
          Row(rowIndex: 1, rowIdentifier: 'r1'),
          Row(rowIndex: 1, rowIdentifier: 'r2'),
        ],
      ),
    ]);
    expect(() => validateDocument(doc), throwsValueError('strictly ascending'));
  });

  test('sparse ascending row indices pass '
      '(test_validate_allows_sparse_ascending_row_index)', () {
    validateDocument(
      docWithTables([
        Table(
          numberOfColumns: 1,
          numberOfRows: 10,
          content: [
            Row(rowIndex: 0, rowIdentifier: 'r1'),
            Row(rowIndex: 5, rowIdentifier: 'r2'),
          ],
        ),
      ]),
    );
  });

  test('an out-of-range column index is rejected '
      '(test_validate_rejects_out_of_range_column_index)', () {
    final doc = docWithTables([
      Table(
        numberOfColumns: 2,
        numberOfRows: 1,
        content: [
          Row(cells: [Cell(value: 'a', columnIndex: 5)]),
        ],
      ),
    ]);
    expect(
      () => validateDocument(doc),
      throwsValueError(
        '`Cell.column_index` 5 is out of range [0, 2) (at '
        'slides[0].contents[0].object.table.content[0].cells[0].column_index)',
      ),
    );
  });

  test('a reversed column index is rejected '
      '(test_validate_rejects_reversed_column_index)', () {
    final doc = docWithTables([
      Table(
        numberOfColumns: 3,
        numberOfRows: 1,
        content: [
          Row(
            cells: [
              Cell(value: 'a', columnIndex: 2),
              Cell(value: 'b', columnIndex: 1),
            ],
          ),
        ],
      ),
    ]);
    expect(() => validateDocument(doc), throwsValueError('strictly ascending'));
  });

  test('sparse ascending column indices pass '
      '(test_validate_allows_sparse_ascending_column_index)', () {
    validateDocument(
      docWithTables([
        Table(
          numberOfColumns: 10,
          numberOfRows: 1,
          content: [
            Row(
              cells: [
                Cell(value: 'a', columnIndex: 0),
                Cell(value: 'b', columnIndex: 4),
              ],
            ),
          ],
        ),
      ]),
    );
  });

  test('implicit indices follow the previous one', () {
    final doc = docWithTables([
      Table(
        numberOfColumns: 1,
        numberOfRows: 2,
        content: [Row(rowIndex: 1), Row()],
      ),
    ]);
    expect(
      () => validateDocument(doc),
      throwsValueError('`Row.row_index` 2 is out of range [0, 2)'),
    );
  });

  test('a merge orders rows by their resolved index', () {
    final table = Table(
      numberOfColumns: 2,
      numberOfRows: 10,
      columnHeaders: [
        ColumnHeader(columnIdentifier: 'c1'),
        ColumnHeader(columnIdentifier: 'c2'),
      ],
      content: [
        Row(rowIdentifier: 'r1', rowIndex: 3),
        Row(rowIdentifier: 'r2'),
      ],
      merges: [_merge('r1', 'c1', 'r2', 'c2')],
    );
    validateDocument(docWithTables([table]));
  });
}
