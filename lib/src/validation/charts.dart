// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:creator_studio_document/src/core/models.g.dart';
import 'package:creator_studio_document/src/navigation/navigation.dart';
import 'package:creator_studio_document/src/validation/cases.dart';
import 'package:creator_studio_document/src/validation/errors.dart';
import 'package:creator_studio_document/src/validation/model_tree.dart';

/// Checks that each series of a two-axis chart picks the first or the
/// second y-axis.
final class ChartValidator() implements ModelTreeValidator {
  /// Creates the validator.
  this;

  @override
  void visit(IterationState state, IteratedModel iterated) {
    if (iterated.model case final Chart chart) {
      _validateChart(chart, iterated.path);
    }
  }

  @override
  void finalize(IterationState state) {}
}

void _validateChart(Chart chart, String path) {
  final (caseName, model) = unwrapPrimaryCase(chart);
  if (model is! TwoAxisChart) {
    return;
  }
  final series = model.series ?? const [];
  for (var i = 0; i < series.length; i++) {
    final selection = series[i].yAxisSelection;
    if (selection != null && selection != 0 && selection != 1) {
      throw DocumentValueError(
        "`ChartSeries.y_axis_selection` $selection isn't 0 or 1 "
        '(at $path.$caseName.series[$i].y_axis_selection)',
      );
    }
  }
}
