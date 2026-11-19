// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:creator_studio_document/src/core/errors.dart';
import 'package:creator_studio_document/src/core/override.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/core/wire.dart';
import 'package:creator_studio_document/src/navigation/navigation.dart';
import 'package:creator_studio_document/src/validation/errors.dart';
import 'package:creator_studio_document/src/validation/paths.dart';
import 'package:creator_studio_document/src/validation/py_text.dart';
import 'package:creator_studio_document/src/validation/resolve.dart';

const _previewLen = 60;

/// Checks that every model in [payload] holds values its declaration
/// accepts, as a model revalidates them on construction.
///
/// A Dart model validates every construction and assignment, and its typed
/// fields can't hold a value of the wrong type, so what this catches is an
/// in-place change that skipped validation: a list emptied below its minimum
/// length or grown past its maximum, a non-finite number put in a list of
/// numbers, or a union whose every case was set to `null`. Unknown keys in
/// `extras` aren't checked.
///
/// Throws [DocumentValueError] naming the first model and field at fault.
void validateFieldTypes(WireModel payload) {
  for (final iterated in iterateModels(payload)) {
    final model = iterated.model;
    _validateOverrideFields(model, iterated.path);
    final issues = revalidateWireModel(model);
    if (issues.isNotEmpty) {
      throw _rejectedError(model, iterated.path, issues);
    }
  }
}

// Upstream also catches a bare value where an `Override` is declared, which
// a Dart model's typed storage rules out; the check is kept for parity.
void _validateOverrideFields(WireModel model, String path) {
  final schema = model.wireSchema;
  if (schema is! ObjectSchema<ObjectModel>) {
    return;
  }
  for (final spec in schema.fields) {
    if (spec.kind != FieldKind.ovr && spec.kind != FieldKind.ovrdef) {
      continue;
    }
    final value = model.wireGet(spec.key);
    if (value is! Override<Object?>) {
      throw DocumentValueError(
        "`${schema.name}.${spec.key}` ${_preview(value)} isn't an `Override` "
        '(at ${extendPath(path, spec.key)}). Wrap it with `Override.value(...)`, '
        'or use `Override.cleared()` or `Override.notSet()`.',
      );
    }
  }
}

bool _hasField(ModelSchema<WireModel> schema, String key) =>
    key == 'preset_identifier' ||
    switch (schema) {
      ObjectSchema() => schema.field(key) != null,
      UnionSchema() => schema.caseSpec(key) != null,
    };

DocumentValueError _rejectedError(
  WireModel model,
  String path,
  List<ValidationIssue> issues,
) {
  final schema = model.wireSchema;
  final loc = issues.first.location;
  final field = loc.isEmpty ? '' : '${loc.first}';
  final String head;
  final String where;
  if (_hasField(schema, field)) {
    head =
        '`${schema.name}.$field` holds a value its field declaration rejects';
    where = extendPath(path, field);
  } else {
    head = '`${schema.name}` holds values its declaration rejects';
    where = path.isEmpty ? '<root>' : path;
  }
  return DocumentValueError(
    '$head (at $where). $revalidateHint Validation errors:\n'
    '${_render(model, issues)}',
    cause: ModelValidationError(schema.name, issues),
  );
}

String _preview(Object? value) => pyShorten(_pyRepr(value), _previewLen);

String _render(WireModel model, List<ValidationIssue> issues) => issues
    .map(
      (issue) =>
          '  at ${issue.path.isEmpty ? '<value>' : issue.path}: '
          '${issue.message} (got ${_preview(_inputAt(model, issue.location))})',
    )
    .join('\n');

// The value that an issue at [loc] is about, as Pydantic reports it: the
// field's value, an item of it, or, for an issue at the model, its fields as
// a mapping.
Object? _inputAt(WireModel model, List<Object> loc) {
  if (loc.isEmpty) {
    return _PyFields(model);
  }
  Object? value = model.wireGet('${loc.first}');
  for (final segment in loc.skip(1)) {
    if (value is OverrideValue<Object?>) {
      value = value.value;
    }
    value = switch ((value, segment)) {
      (final List<Object?> l, final int i) when i >= 0 && i < l.length => l[i],
      (final WireModel m, final String key) => m.wireGet(key),
      _ => value,
    };
  }
  return value is OverrideValue<Object?> ? value.value : value;
}

// A model's fields as the mapping `dict(model.__dict__)`, which upstream
// quotes for an issue at the model itself.
final class _PyFields(final WireModel model);

Iterable<String> _keys(ModelSchema<WireModel> schema) => switch (schema) {
  ObjectSchema(:final fields) => [for (final f in fields) f.key],
  UnionSchema(:final cases) => [for (final c in cases) c.key],
};

// Python's `repr`, as closely as a Dart value allows. A model prints as its
// `toString`, which differs from Pydantic's.
String _pyRepr(Object? value) => switch (value) {
  final _PyFields f =>
    '{${["'preset_identifier': ${pyStringRepr(f.model.presetIdentifier)}", for (final k in _keys(f.model.wireSchema)) '${pyStringRepr(k)}: ${_pyRepr(f.model.wireGet(k))}'].join(', ')}}',
  final WireEnum e =>
    '<${e.runtimeType}.${e.wireValue.toUpperCase()}: '
        '${pyStringRepr(e.wireValue)}>',
  OverrideNotSet() => 'Override.not_set()',
  OverrideCleared() => 'Override.cleared()',
  OverrideValue(:final value) => 'Override.value(${_pyRepr(value)})',
  final List<Object?> l => '[${l.map(_pyRepr).join(', ')}]',
  final WireModel m => '$m',
  _ => pyRepr(value),
};
