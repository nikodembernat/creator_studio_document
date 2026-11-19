// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:creator_studio_document/src/core/errors.dart';
import 'package:creator_studio_document/src/core/package.dart';
import 'package:creator_studio_document/src/core/preset.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/core/wire.dart';
import 'package:creator_studio_document/src/validation/errors.dart';

/// The hint that a message about a value that skipped validation ends with.
///
/// Upstream names the Python ways to skip validation: in-place mutation,
/// `model_construct`, and `model_copy(update=...)`. A Dart model validates
/// every construction and assignment, so only an in-place change skips it.
const revalidateHint =
    'An in-place change, such as to a list, likely set the value, and it '
    'skips validation. Reassign the field to revalidate it.';

/// Decodes [mainJson] as [doc]'s payload, filling every adopted preset's
/// values without validating them first, so an invalid inherited value
/// fails the decode.
///
/// A preset cycle recurses without end, so call this only after
/// `validatePresetGraph(doc.presets)` passes.
///
/// Throws [DocumentReferenceError] if a `preset_identifier` matches no
/// preset, and [DocumentValueError] if the JSON doesn't decode, naming
/// whether the document's own values or the inherited ones are at fault.
T resolveProperties<T extends ObjectModel>(
  Package<T> doc,
  Map<String, Object?> mainJson,
) {
  final reg = PresetRegistry(doc.presets);
  final schema = doc.payload.wireSchema;
  final T resolved;
  try {
    resolved = schema.fromJson(
      mainJson,
      WireContext(presets: reg, strictPresets: true),
    ) as T;
  } on ModelValidationError catch (e) {
    _raiseIfUnresolved(reg);
    throw _attributedError(e, schema, mainJson, doc.presets);
  }
  _raiseIfUnresolved(reg);
  return resolved;
}

void _raiseIfUnresolved(PresetRegistry reg) {
  if (reg.warnings.isEmpty) {
    return;
  }
  const prefix = 'missing preset ';
  final missing = {
    for (final w in reg.warnings)
      if (w.startsWith(prefix)) w.substring(prefix.length) else w,
  }.toList()..sort(compareCodePoints);
  throw DocumentReferenceError(
    '`preset_identifier` matches no preset: ${missing.join(', ')}',
  );
}

DocumentValueError _attributedError(
  ModelValidationError e,
  ModelSchema<WireModel> schema,
  Map<String, Object?> mainJson,
  List<Preset> presets,
) {
  try {
    schema.fromJson(mainJson, WireContext(presets: PresetRegistry(presets)));
  } on ModelValidationError catch (lenient) {
    return _payloadDefectError(lenient, hasPresets: presets.isNotEmpty);
  }
  return _inheritedValueError(e);
}

String _renderLocs(ModelValidationError e) =>
    [for (final issue in e.issues) '  at ${issue.path}: ${issue.message}']
        .join('\n');

DocumentValueError _payloadDefectError(
  ModelValidationError e, {
  required bool hasPresets,
}) {
  if (hasPresets) {
    return DocumentValueError(
      "The document doesn't validate against its own JSON. Fix any invalid "
      'preset property. Otherwise, an edit bypassed validation. '
      '$revalidateHint Validation errors:\n${_renderLocs(e)}',
      cause: e,
    );
  }
  return DocumentValueError(
    "An edit bypassed validation, so the document doesn't validate against "
    'its own JSON. $revalidateHint Validation errors:\n${_renderLocs(e)}',
    cause: e,
  );
}

DocumentValueError _inheritedValueError(ModelValidationError e) =>
    DocumentValueError(
      'An inherited preset value is invalid. Fix the preset properties. '
      'Validation errors:\n${_renderLocs(e)}',
      cause: e,
    );
