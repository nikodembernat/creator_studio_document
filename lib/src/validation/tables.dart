// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:creator_studio_document/src/core/models.g.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/navigation/navigation.dart';
import 'package:creator_studio_document/src/validation/errors.dart';
import 'package:creator_studio_document/src/validation/model_tree.dart';

/// Checks a table's identifiers, its sparse row and column indices, the
/// formats and style sets its cells refer to, and its merged ranges.
///
/// The base table of a transformation, such as a pivot's, isn't checked.
final class TableValidator() implements ModelTreeValidator {
  /// Creates the validator.
  this;

  @override
  void visit(IterationState state, IteratedModel iterated) {
    if (iterated.model case final Table table
        when !iterated.ancestors.any((a) => a is TransformationInfo)) {
      _validateTable(table, iterated.path);
    }
  }

  @override
  void finalize(IterationState state) {}
}

void _validateTable(Table table, String path) {
  _collectUnique(
    table.columnHeaders,
    (c) => c.columnIdentifier,
    'column_headers',
    'ColumnHeader.column_identifier',
    path,
  );
  _collectUnique(
    table.content,
    (r) => r.rowIdentifier,
    'content',
    'Row.row_identifier',
    path,
  );
  final customFormatIds = _collectUnique(
    table.customFormats,
    (f) => f.identifier,
    'custom_formats',
    'CustomFormat.identifier',
    path,
  );
  final condStyleSetIds = _collectUnique(
    table.conditionalStyleSets,
    (s) => s.identifier,
    'conditional_style_sets',
    'ConditionalStyleSet.identifier',
    path,
  );

  final rowIndices = _validateSparseIndices(
    table.content,
    (r) => r.rowIndex,
    table.numberOfRows,
    noun: 'row',
    field: 'row_index',
    listField: 'content',
    path: path,
  );

  final rows = table.content ?? const <Row>[];
  for (var ri = 0; ri < rows.length; ri++) {
    final row = rows[ri];
    _validateSparseIndices(
      row.cells,
      (c) => c.columnIndex,
      table.numberOfColumns,
      noun: 'cell',
      field: 'column_index',
      listField: 'cells',
      path: '$path.content[$ri]',
    );
    final cells = row.cells ?? const <Cell>[];
    for (var ci = 0; ci < cells.length; ci++) {
      _validateCell(
        cells[ci],
        customFormatIds: customFormatIds,
        condStyleSetIds: condStyleSetIds,
        cellPath: '$path.content[$ri].cells[$ci]',
      );
    }
  }

  final merges = table.merges;
  if (merges != null && merges.isNotEmpty) {
    final columnOrder = _columnPositions(table.columnHeaders);
    final rowOrder = <String, int>{
      for (var i = 0; i < rows.length; i++)
        ?rows[i].rowIdentifier: rowIndices[i],
    };
    for (var mi = 0; mi < merges.length; mi++) {
      if (merges[mi].rowColumnIdRange case final range?) {
        _validateMergedRange(range, rowOrder, columnOrder, '$path.merges[$mi]');
      }
    }
  }
}

void _validateCell(
  Cell cell, {
  required Set<String> customFormatIds,
  required Set<String> condStyleSetIds,
  required String cellPath,
}) {
  final csid = cell.conditionalStyleSetIdentifier;
  if (csid != null && !condStyleSetIds.contains(csid)) {
    throw DocumentReferenceError(
      '`Cell.conditional_style_set_identifier` ${pyStringRepr(csid)} matches '
      'no `ConditionalStyleSet` (at $cellPath.conditional_style_set_identifier)',
    );
  }
  if (cell.cellFormat case final format?) {
    _validateCustomFormatId(format, customFormatIds, '$cellPath.cell_format');
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

List<int> _validateSparseIndices<T>(
  List<T>? items,
  int? Function(T) getIndex,
  int bound, {
  required String noun,
  required String field,
  required String listField,
  required String path,
}) {
  final resolved = <int>[];
  var previous = -1;
  final list = items ?? <T>[];
  for (var i = 0; i < list.length; i++) {
    final index = getIndex(list[i]) ?? previous + 1;
    final itemPath = '$path.$listField[$i].$field';
    if (!(0 <= index && index < bound)) {
      throw DocumentValueError(
        '`${_capitalize(noun)}.$field` $index is out of range [0, $bound) '
        '(at $itemPath)',
      );
    }
    if (index <= previous) {
      throw DocumentValueError(
        "`${_capitalize(noun)}.$field` $index isn't greater than the "
        "previous $noun's index $previous (at $itemPath). List ${noun}s in "
        'strictly ascending order of index.',
      );
    }
    previous = index;
    resolved.add(index);
  }
  return resolved;
}

Set<String> _collectUnique<T>(
  List<T>? items,
  String? Function(T) getId,
  String listField,
  String idName,
  String tablePath,
) {
  final seen = <String, int>{};
  final list = items ?? <T>[];
  for (var i = 0; i < list.length; i++) {
    final value = getId(list[i]);
    if (value == null) {
      continue;
    }
    if (seen[value] case final first?) {
      throw DocumentValueError(
        '`$idName` ${pyStringRepr(value)} is a duplicate within the table '
        '(at $tablePath.$listField[$i]). The first is at '
        '$tablePath.$listField[$first].',
      );
    }
    seen[value] = i;
  }
  return seen.keys.toSet();
}

void _validateCustomFormatId(
  CellFormat format,
  Set<String> customFormatIds,
  String path,
) {
  final id = format.customFormatIdentifier;
  if (format.formatType == FormatType.custom &&
      id != null &&
      !customFormatIds.contains(id)) {
    throw DocumentReferenceError(
      '`CellFormat.custom_format_identifier` ${pyStringRepr(id)} matches no '
      '`CustomFormat` (at $path.custom_format_identifier)',
    );
  }
}

Map<String, int> _columnPositions(List<ColumnHeader>? headers) {
  final list = headers ?? const <ColumnHeader>[];
  return {for (var i = 0; i < list.length; i++) ?list[i].columnIdentifier: i};
}

void _validateMergedRange(
  RowColumnIdRange range,
  Map<String, int> rowOrder,
  Map<String, int> columnOrder,
  String path,
) {
  for (final (fieldName, rid) in [
    ('top_left_row_identifier', range.topLeftRowIdentifier),
    ('bottom_right_row_identifier', range.bottomRightRowIdentifier),
  ]) {
    if (!rowOrder.containsKey(rid)) {
      throw DocumentReferenceError(
        '`RowColumnIdRange.$fieldName` ${pyStringRepr(rid)} matches no '
        '`Row.row_identifier` (at $path.row_column_id_range.$fieldName)',
      );
    }
  }
  for (final (fieldName, cid) in [
    ('top_left_column_identifier', range.topLeftColumnIdentifier),
    ('bottom_right_column_identifier', range.bottomRightColumnIdentifier),
  ]) {
    if (!columnOrder.containsKey(cid)) {
      throw DocumentReferenceError(
        '`RowColumnIdRange.$fieldName` ${pyStringRepr(cid)} matches no '
        '`ColumnHeader.column_identifier` '
        '(at $path.row_column_id_range.$fieldName)',
      );
    }
  }
  if (rowOrder[range.topLeftRowIdentifier]! >
          rowOrder[range.bottomRightRowIdentifier]! ||
      columnOrder[range.topLeftColumnIdentifier]! >
          columnOrder[range.bottomRightColumnIdentifier]!) {
    throw DocumentValueError(
      '`RowColumnIdRange` top-left corner '
      '(${pyStringRepr(range.topLeftRowIdentifier)}, '
      '${pyStringRepr(range.topLeftColumnIdentifier)}) sits after its '
      'bottom-right corner (${pyStringRepr(range.bottomRightRowIdentifier)}, '
      '${pyStringRepr(range.bottomRightColumnIdentifier)}) (at '
      '$path.row_column_id_range)',
    );
  }
}
