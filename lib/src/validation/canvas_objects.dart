// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:creator_studio_document/src/core/models.g.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/core/wire.dart';
import 'package:creator_studio_document/src/navigation/navigation.dart';
import 'package:creator_studio_document/src/validation/cases.dart';
import 'package:creator_studio_document/src/validation/errors.dart';
import 'package:creator_studio_document/src/validation/identifiers.dart';
import 'package:creator_studio_document/src/validation/model_tree.dart';
import 'package:creator_studio_document/src/validation/paths.dart';

/// Checks that canvas object identifiers are unique among siblings and
/// across the document, and that a connection line's ends anchor to a
/// sibling.
///
/// An object that a slide takes from its layout, and everything inside it,
/// may reuse the layout's identifiers, so it's left out of the
/// document-wide check.
final class CanvasObjectValidator() implements ModelTreeValidator {
  /// Creates the validator.
  this;

  @override
  void visit(IterationState state, IteratedModel iterated) {
    final model = iterated.model;
    final fromLayout = iterated.ancestors.any(
      (a) => a is SlideObject && a.sourceKind == SourceKind.layout,
    );
    final path = iterated.path;
    switch (model) {
      case final Slide slide:
        _validateContainer(
          state,
          path,
          slide.contents ?? const [],
          'contents',
          fromLayout: fromLayout,
        );
      case final SlideLayout layout:
        _validateContainer(
          state,
          path,
          layout.contents ?? const [],
          'contents',
          fromLayout: fromLayout,
        );
      case final Group group:
        _validateContainer(
          state,
          path,
          group.children,
          'children',
          fromLayout: fromLayout,
        );
      case Constituent(:final inlineObject?) when !fromLayout:
        final (_, resolved) = unwrapPrimaryCase(inlineObject);
        _claimDocumentWide(state, resolved, extendPath(path, 'inline_object'));
    }
  }

  @override
  void finalize(IterationState state) {}
}

void _validateContainer(
  IterationState state,
  String path,
  List<WireModel> items,
  String fieldName, {
  required bool fromLayout,
}) {
  final localIdPaths = <String, String>{};
  final connectionLines = <(String, ConnectionLine)>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final CanvasObject canvasObject;
    final String suffix;
    if (item is SlideObject) {
      canvasObject = item.object;
      suffix = '$fieldName[$i].object';
    } else {
      canvasObject = item as CanvasObject;
      suffix = '$fieldName[$i]';
    }
    final itemPath = extendPath(path, suffix);
    final (_, resolved) = unwrapPrimaryCase(canvasObject);
    registerCanvasObject(resolved, itemPath, localIdPaths);
    if (!fromLayout &&
        !(item is SlideObject && item.sourceKind == SourceKind.layout)) {
      _claimDocumentWide(state, resolved, itemPath);
    }
    if (resolved is ConnectionLine) {
      connectionLines.add((itemPath, resolved));
    }
  }
  for (final (linePath, line) in connectionLines) {
    _validateConnectionLineEnds(linePath, line, localIdPaths);
  }
}

void _validateConnectionLineEnds(
  String path,
  ConnectionLine line,
  Map<String, String> localIdPaths,
) {
  for (final (endName, end) in [('tail', line.tail), ('head', line.head)]) {
    if (end.endPoint == null) {
      throw DocumentValueError(
        '`ConnectionLine.End.end_point` is missing '
        '(at $path.$endName.end_point)',
      );
    }
    final anchor = end.anchor;
    if (anchor == null) {
      continue;
    }
    if (!localIdPaths.containsKey(anchor.objectId)) {
      throw DocumentReferenceError(
        '`ConnectionLine.End.Anchor.object_id` '
        '${pyStringRepr(anchor.objectId)} matches no sibling of the line '
        '(at $path.$endName.anchor.object_id)',
      );
    }
  }
}

/// Claims the identifier of [model], a canvas object at [path], among its
/// siblings in [localIdPaths].
///
/// Throws [DocumentValueError] if a sibling has the same identifier, and
/// [ArgumentError] if [model] has no `identifier` field, as upstream raises
/// `AttributeError`.
void registerCanvasObject(
  ObjectModel model,
  String path,
  Map<String, String> localIdPaths,
) {
  final schema = model.wireSchema as ObjectSchema<ObjectModel>;
  if (schema.field('identifier') == null) {
    throw ArgumentError(
      "'${schema.name}' object has no attribute 'identifier'",
      'model',
    );
  }
  if (model.wireGet('identifier') case final String identifier) {
    claimUnique(localIdPaths, identifier, path, '${schema.name}.identifier');
  }
}

void _claimDocumentWide(IterationState state, ObjectModel model, String path) {
  if (model.wireGet('identifier') case final String identifier) {
    claimUnique(
      state.canvasObjectIds,
      identifier,
      path,
      '${model.wireSchema.name}.identifier',
    );
  }
}
