// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:creator_studio_document/src/core/encode_error.dart';
import 'package:creator_studio_document/src/core/errors.dart';
import 'package:creator_studio_document/src/core/package.dart';
import 'package:creator_studio_document/src/core/wire.dart';
import 'package:creator_studio_document/src/validation/errors.dart';
import 'package:creator_studio_document/src/validation/field_types.dart';
import 'package:creator_studio_document/src/validation/indirect_resources.dart';
import 'package:creator_studio_document/src/validation/model_tree.dart';
import 'package:creator_studio_document/src/validation/preset_graph.dart';
import 'package:creator_studio_document/src/validation/resolve.dart';
import 'package:creator_studio_document/src/validation/version_drift.dart';
import 'package:meta/meta.dart';

/// The phase that resolves the payload's presets. Tests replace it to check
/// the self-check of [validateDocument].
@visibleForTesting
T Function<T extends ObjectModel>(Package<T> doc, Map<String, Object?> main)
resolvePhase = resolveProperties;

/// Checks a document and throws on the first value that breaks the format's
/// rules.
///
/// Unlike a model's own validation, this also checks values changed in
/// place, values inherited from a preset, resource references, and
/// references across the document: unique identifiers, slide targets, slide
/// layouts, connection line anchors, table indices, formats, and merges,
/// chart axes, and the format of strings such as SVG paths, currency codes,
/// locales, URLs, and Base64.
///
/// [mainJson] is the JSON that `Package.save` passes to a `preSaveHooks`
/// entry. When it's omitted, the function computes it from [doc]. The
/// function fits `preSaveHooks` as it is:
///
/// ```dart
/// doc.save(path, preSaveHooks: [validateDocument]);
/// ```
///
/// It logs a [DocumentVersionWarning] for each union whose primary case this
/// version of the library doesn't implement, so it reads the case's fallback
/// instead.
///
/// Throws [DocumentReferenceError] if a preset, identifier, or reference
/// doesn't resolve, and [DocumentValueError] if a value violates an
/// invariant. When it computes the JSON itself, it also throws
/// [DocumentValueError] if a union has no case to write, such as one whose
/// every case was cleared in place, and otherwise what encoding the payload
/// throws, such as [DocumentVersionError] if a union's only case comes from a
/// preset value too new for this library to read. Throws
/// [StateError] if it changed [mainJson], which is a defect in
/// `validateDocument`. Throws [ArgumentError] where upstream raises a
/// `TypeError` or `AttributeError` for malformed input, such as a preset
/// whose `properties` aren't an object, or a union whose `primary_case` is a
/// list.
void validateDocument<T extends ObjectModel>(
  Package<T> doc, [
  Map<String, Object?>? mainJson,
]) {
  validateVersionDrift(doc.payload);
  validateFieldTypes(doc.payload);
  // Runs before encoding, so that a preset cycle is reported here, not as an
  // encoding error.
  validatePresetGraph(doc.presets);
  final main = mainJson ?? _mainJson(doc);
  final before = mainJson == null ? null : _snapshot(mainJson);
  final resolved = resolvePhase(doc, main);
  validateIndirectResources(doc, resolved);
  validateModelTree(resolved);
  if (before != null && !_sameDump(before, main)) {
    throw StateError(
      '`main_json` changed during `validateDocument`. This is a defect in '
      '`validateDocument`.',
    );
  }
}

// `doc.payload.model_dump(mode="json", ...)`: a union with no case to write,
// and a value nested too deeply, are the `ValueError`s that upstream raises,
// as Pydantic's `PydanticSerializationError` for the first. For the second,
// Pydantic adds the same wrapper only at some depths, and the port never.
Map<String, Object?> _mainJson(Package<ObjectModel> doc) {
  try {
    return doc.toMainJson();
  } on Object catch (e) {
    switch (e) {
      case NoCaseError():
        throw DocumentValueError(
          'Error calling function `_wire_encode`: ValueError: ${e.message}',
          cause: e,
        );
      case SerializationDepthError():
        throw DocumentValueError(e.message, cause: e);
    }
    rethrow;
  }
}

// A deep copy of a JSON value, for the self-check.
Object? _snapshot(Object? value) => switch (value) {
  final Map<Object?, Object?> m => {
    for (final e in m.entries) e.key: _snapshot(e.value),
  },
  final List<Object?> l => [for (final v in l) _snapshot(v)],
  _ => value,
};

// Whether `json.dumps` writes [a] and [b] the same: the same keys in the same
// order, and numbers of the same type and value.
bool _sameDump(Object? a, Object? b) {
  switch ((a, b)) {
    case (final Map<Object?, Object?> x, final Map<Object?, Object?> y):
      if (x.length != y.length) {
        return false;
      }
      final xs = x.entries.toList();
      final ys = y.entries.toList();
      for (var i = 0; i < xs.length; i++) {
        if (xs[i].key != ys[i].key || !_sameDump(xs[i].value, ys[i].value)) {
          return false;
        }
      }
      return true;
    case (final List<Object?> x, final List<Object?> y):
      if (x.length != y.length) {
        return false;
      }
      for (var i = 0; i < x.length; i++) {
        if (!_sameDump(x[i], y[i])) {
          return false;
        }
      }
      return true;
    case (final double x, final double y):
      return x.compareTo(y) == 0;
    case (final int x, final int y):
      return x == y;
    case (double() || int(), _) || (_, double() || int()):
      return false;
    default:
      return a == b;
  }
}
