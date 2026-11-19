// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:creator_studio_document/src/core/wire.dart';
import 'package:creator_studio_document/src/navigation/navigation.dart';
import 'package:creator_studio_document/src/validation/canvas_objects.dart';
import 'package:creator_studio_document/src/validation/charts.dart';
import 'package:creator_studio_document/src/validation/slides.dart';
import 'package:creator_studio_document/src/validation/string_formats.dart';
import 'package:creator_studio_document/src/validation/tables.dart';

/// A reference to a slide that the validators resolve once every slide is
/// known.
final class PendingSlideTarget(
  /// The path of the `SlideTarget`.
  final String path,

  /// The `Slide.identifier` it names.
  final String slideId,
) {
  /// Creates the reference.
  this;
}

/// A slide's `layout` reference, which the validators resolve once every
/// slide layout is known.
final class PendingLayoutRef(
  /// The path of the `Slide`.
  final String path,

  /// The identifier or name of the slide layout.
  final String layout,
) {
  /// Creates the reference.
  this;
}

/// What the validators collect over one walk of the document.
final class IterationState() {
  /// Creates an empty state.
  this;

  /// The path of each `Slide.identifier`.
  final Map<String, String> slideIds = {};

  /// The path of each `SlideLayout.identifier`.
  final Map<String, String> slideLayoutIds = {};

  /// The path of each canvas object identifier, across the document.
  final Map<String, String> canvasObjectIds = {};

  /// The first slide layout name for each name key.
  final Map<String, String> slideLayoutNames = {};

  /// The slide targets to resolve.
  final List<PendingSlideTarget> pendingSlideTargets = [];

  /// The layout references to resolve.
  final List<PendingLayoutRef> pendingLayoutRefs = [];
}

/// A check that visits every model of the document, then finalizes.
abstract interface class ModelTreeValidator() {
  /// Creates the validator.
  this;

  /// Checks one model.
  void visit(IterationState state, IteratedModel iterated);

  /// Checks what depends on the whole document, after every visit.
  void finalize(IterationState state);
}

final List<ModelTreeValidator> _validators = [
  SlideValidator(),
  CanvasObjectValidator(),
  TableValidator(),
  ChartValidator(),
  StringFormatValidator(),
];

/// Runs every model tree validator over [payload], in one walk.
void validateModelTree(WireModel payload) {
  final state = IterationState();
  for (final iterated in iterateModels(payload)) {
    for (final validator in _validators) {
      validator.visit(state, iterated);
    }
  }
  for (final validator in _validators) {
    validator.finalize(state);
  }
}
