// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python): the decoding half of
// `_wire.py` (`_wire_before`, `_wire_inherited`, `_wire_decode_wrap`) and the
// strict validation that Pydantic performs for the generated models.

part of 'wire.dart';

// The result of a value that failed validation. The issue is already recorded.
final class const _Invalid();

const _invalid = _Invalid();

// A `ValueError` raised inside a validator: Pydantic reports it as an issue at
// the model being validated.
final class _ValueError(final String message) implements Exception;

const _maxPresetGateDepth = 4;

// Validates JSON against the models, as Pydantic's strict mode does, and
// collects every issue.
//
// A preset gate calls [value] on a field's bare annotation, which carries none
// of the field's own constraints such as `ge`. The fields of the models nested
// in it keep theirs, as they do under Pydantic's `TypeAdapter`.
final class _Decoder(final WireContext context) {
  final List<ValidationIssue> issues = [];

  // pydantic-core's recursion guard: the mappings each model is validating,
  // compared by identity. A preset that adopts itself, directly or through
  // another preset, fills the same raw value again and again, and the guard
  // stops that loop with a `recursion_loop` issue. Each decoder starts empty,
  // as each `validate_python` call does, so a preset gate starts afresh.
  final Map<ModelSchema<WireModel>, Set<Object>> _active = HashMap.identity();

  _Invalid _fail(List<Object> loc, String type, String message) {
    issues.add(ValidationIssue(loc, message, type: type));
    return _invalid;
  }

  Object? value(
    WireType type,
    Object? input,
    List<Object> loc, {
    required bool lax,
  }) => switch (type) {
    BoolType() =>
      input is bool
          ? input
          : _fail(loc, 'bool_type', 'Input should be a valid boolean'),
    IntType() =>
      input is int
          ? input
          : _fail(loc, 'int_type', 'Input should be a valid integer'),
    FloatType() => _float(input, loc),
    StringType() =>
      input is String
          ? input
          : _fail(loc, 'string_type', 'Input should be a valid string'),
    // Pydantic matches `Literal[True]` by equality, even in strict mode, so
    // `1` and `1.0` decode as `True` too.
    LiteralTrueType() =>
      input == true || (isPyNumber(input) && pyNumEquals(input!, 1))
          ? true
          : _fail(loc, 'literal_error', 'Input should be True'),
    EnumType() => _enum(type, input, loc, lax: lax || !type.strict),
    ModelType() => _model(type.schema, input, loc),
    ListType() => _list(type, input, loc, lax: lax),
    NullableType(:final of) =>
      input == null ? null : value(of, input, loc, lax: lax),
    OverrideType() => _override(type, input, loc, lax: lax),
  };

  Object? _float(Object? input, List<Object> loc) {
    // Python's `float()` of an `int` too large for a double raises, and
    // Pydantic reports it as not a number.
    final d = switch (input) {
      final num n => n.toDouble(),
      final BigInt n when n.toDouble().isFinite => n.toDouble(),
      _ => null,
    };
    if (d == null) {
      return _fail(loc, 'float_type', 'Input should be a valid number');
    }
    if (!d.isFinite) {
      return _fail(loc, 'finite_number', 'Input should be a finite number');
    }
    return d;
  }

  Object? _enum(
    EnumType<WireEnum> type,
    Object? input,
    List<Object> loc, {
    required bool lax,
  }) {
    if (type._isMember(input)) {
      return input;
    }
    if (lax && input is String) {
      if (type.byWire(input) case final member?) {
        return member;
      }
    }
    final expected = [for (final v in type.values) "'${v.wireValue}'"];
    final last = expected.removeLast();
    final choices = expected.isEmpty ? last : '${expected.join(', ')} or $last';
    return lax
        ? _fail(loc, 'enum', 'Input should be $choices')
        : _fail(
            loc,
            'is_instance_of',
            'Input should be an instance of ${type.name}',
          );
  }

  Object? _list(
    ListType<Object?> type,
    Object? input,
    List<Object> loc, {
    required bool lax,
  }) {
    if (input is! List<Object?>) {
      return _fail(loc, 'list_type', 'Input should be a valid list');
    }
    final items = <Object?>[];
    var ok = true;
    for (var i = 0; i < input.length; i++) {
      final item = value(type.of, input[i], [...loc, i], lax: lax);
      ok = ok && item is! _Invalid;
      items.add(item);
    }
    return ok ? type._build(items) : _invalid;
  }

  // `Override.__get_pydantic_core_schema__`: a bare value becomes
  // `.value(x)`, `None` becomes `.cleared()`, and a value override revalidates
  // its value.
  Object? _override(
    OverrideType<Object?> type,
    Object? input,
    List<Object> loc, {
    required bool lax,
  }) {
    switch (input) {
      case null:
        return type._cleared();
      case OverrideNotSet():
        return type._notSet();
      case OverrideCleared():
        return type._cleared();
      case OverrideValue(:final value):
        final inner = this.value(type.of, value, loc, lax: lax);
        return inner is _Invalid ? inner : type._value(inner);
    }
    final inner = value(type.of, input, loc, lax: lax);
    return inner is _Invalid ? inner : type._value(inner);
  }

  Object? _model(
    ModelSchema<WireModel> schema,
    Object? input,
    List<Object> loc,
  ) {
    if (schema._accepts(input)) {
      return input;
    }
    final data = _asJsonObject(input);
    switch (schema) {
      case ObjectSchema() when data != null:
        return _guarded(schema, input!, loc, () => _object(schema, data, loc));
      case UnionSchema() when input is String:
        return _bareCase(schema, input, loc);
      case UnionSchema() when data != null:
        return _guarded(schema, input!, loc, () => _union(schema, data, loc));
      case ObjectSchema() || UnionSchema():
        return _fail(
          loc,
          'model_type',
          'Input should be a valid dictionary or instance of ${schema.name}',
        );
    }
  }

  // Validates [input] with [validate], unless [schema] is already validating
  // that same object further up.
  Object? _guarded(
    ModelSchema<WireModel> schema,
    Object input,
    List<Object> loc,
    Object? Function() validate,
  ) {
    final active = _active.putIfAbsent(schema, Set.identity);
    if (!active.add(input)) {
      return _fail(
        loc,
        'recursion_loop',
        'Recursion error - cyclic reference detected',
      );
    }
    try {
      return validate();
    } finally {
      active.remove(input);
    }
  }

  // ---- objects -----------------------------------------------------------

  // `ObjectModel._wire_before`, the field validation, then
  // `ObjectModel._wire_inherited`.
  Object? _object(
    ObjectSchema<ObjectModel> schema,
    Map<String, Object?> data,
    List<Object> loc,
  ) {
    final out = Map<String, Object?>.of(data);
    final Set<String> filled;
    try {
      final (tooNew, _) = _gateWireVersion(schema, out, [
        for (final f in schema.fields) (f.key, f.added),
      ], 'its default');
      for (final f in schema.fields) {
        if (f.kind == FieldKind.def &&
            out.containsKey(f.key) &&
            out[f.key] == null) {
          out[f.key] = f.defaultValue!();
        }
      }
      filled = _fillObject(schema, out, tooNew);
    } on _ValueError catch (e) {
      return _fail(loc, 'value_error', 'Value error, ${e.message}');
    }
    out
      ..remove('type_identifier')
      ..remove('version');
    final model = _validateObject(schema, out, loc);
    if (model == null) {
      return _invalid;
    }
    if (_truthy(data['preset_identifier'])) {
      model._fieldsSet.removeWhere(
        (k) => schema.field(k) != null && !data.containsKey(k),
      );
      // Upstream hands the filled fields over under its hand-over key among
      // the validated keys, then pops that key from the unknown keys, so a
      // key of the input's own with that name is never written back. Pydantic
      // has counted the key as set by then, and nothing removes it, so it
      // stays in the fields set whenever the preset filled a field.
      final own = model._extras.remove(_filledKey);
      if (filled.isNotEmpty) {
        model
          .._filled = _PresetFilled(filled)
          .._fieldsSet.add(_filledKey);
      } else if (own != null) {
        model._filled = _PresetFilled(own);
      }
    }
    if (Version.parse(data['version']) case final wire?) {
      model._floor = _WireFloor.at(wire, schema.version, model);
    }
    return model;
  }

  Set<String> _fillObject(
    ObjectSchema<ObjectModel> schema,
    Map<String, Object?> out,
    Set<String> tooNew,
  ) {
    final pid = _adoptedPreset(out);
    final adoption = _decodeAdoption(pid, context);
    if (adoption == null) {
      return const {};
    }
    final supplies = [
      for (final f in schema.fields)
        if (!tooNew.contains(f.key) && !out.containsKey(f.key))
          (
            f.key,
            _fieldPresetSupply(schema, f, adoption, strict: adoption.strict),
          ),
    ];
    return _fillFromPreset(out, adoption.props, supplies);
  }

  // Pydantic's own validation of the fields, after `_wire_before`.
  ObjectModel? _validateObject(
    ObjectSchema<ObjectModel> schema,
    Map<String, Object?> out,
    List<Object> loc,
  ) {
    if (!_unicodeKeys(out, loc)) {
      return null;
    }
    final mark = issues.length;
    final model = schema._create();
    _presetIdentifierField(model, out, loc);
    for (final spec in schema.fields) {
      final key = spec.key;
      if (!out.containsKey(key)) {
        model._values[key] = spec._initial();
        if (spec.intDefault) {
          model._intDefaults.add(key);
        }
        if (spec.kind == FieldKind.req) {
          _fail([...loc, key], 'missing', 'Field required');
        }
        continue;
      }
      final value = _field(spec, out[key], [...loc, key]);
      if (value is! _Invalid) {
        model._values[key] = value;
        model._fieldsSet.add(key);
      }
    }
    // Pydantic counts the unknown keys as set, too.
    for (final e in out.entries) {
      if (schema.field(e.key) == null && e.key != 'preset_identifier') {
        model._extras[e.key] = e.value;
        model._fieldsSet.add(e.key);
      }
    }
    return issues.length == mark ? model : null;
  }

  // Pydantic turns every key into a Rust string before it validates any
  // field, and a key that holds a lone surrogate can't become one. That one
  // issue, at the model, replaces every other.
  bool _unicodeKeys(Map<String, Object?> out, List<Object> loc) {
    if (out.keys.every((k) => loneSurrogate(k) == null)) {
      return true;
    }
    _fail(
      loc,
      'string_unicode',
      'Input should be a valid string, unable to parse raw data as a unicode '
          'string',
    );
    return false;
  }

  Object? _field(FieldSpec spec, Object? raw, List<Object> loc) {
    if (_tooLong(spec, raw, loc, issues)) {
      return _invalid;
    }
    final v = value(spec.type, raw, loc, lax: false);
    if (v is _Invalid) {
      return v;
    }
    final mark = issues.length;
    _checkConstraints(spec, v, loc, issues);
    return issues.length == mark ? v : _invalid;
  }

  void _presetIdentifierField(
    WireModel model,
    Map<String, Object?> out,
    List<Object> loc,
  ) {
    if (!out.containsKey('preset_identifier')) {
      return;
    }
    final pid = out['preset_identifier'];
    if (pid is String) {
      model
        .._presetIdentifier = pid
        .._fieldsSet.add('preset_identifier');
    } else {
      _fail(
        [...loc, 'preset_identifier'],
        'string_type',
        'Input should be a valid string',
      );
    }
  }

  // ---- unions ------------------------------------------------------------

  Object? _bareCase(
    UnionSchema<TaggedUnionModel> schema,
    String data,
    List<Object> loc,
  ) {
    if (!(schema.caseSpec(data)?.valueless ?? false)) {
      return _fail(
        loc,
        'value_error',
        'Value error, ${schema.name}: unknown bare case ${_repr(data)}',
      );
    }
    final model = schema._create();
    model._values[data] = true;
    model._fieldsSet.add(data);
    model._primary = data;
    return model;
  }

  // `TaggedUnionModel._wire_decode_wrap` for a mapping.
  Object? _union(
    UnionSchema<TaggedUnionModel> schema,
    Map<String, Object?> data,
    List<Object> loc,
  ) {
    final out = Map<String, Object?>.of(data);
    final Set<String> tooNewCases;
    final Version? stamp;
    final _Adoption? adoption;
    final Object? pid;
    try {
      (tooNewCases, stamp) = _gateWireVersion(schema, out, [
        for (final c in schema.cases) (c.key, c.added),
      ], 'absent');
      out
        ..remove('type_identifier')
        ..remove('version');
      pid = _adoptedPreset(out);
      adoption = _decodeAdoption(pid, context);
    } on _ValueError catch (e) {
      return _fail(loc, 'value_error', 'Value error, ${e.message}');
    }
    var primary = data['primary_case'];
    out.remove('primary_case');
    if (primary is String && tooNewCases.contains(primary)) {
      primary = null;
    }
    var filled = const <String>{};
    DocumentVersionError? tooNew;
    if (adoption != null) {
      final (fills, error) = _casePresetFills(
        schema,
        [
          for (final c in schema.cases)
            if (!c.valueless &&
                !out.containsKey(c.key) &&
                !tooNewCases.contains(c.key))
              c,
        ],
        adoption,
        strict: adoption.strict,
      );
      tooNew = error;
      filled = _fillFromPreset(
        out,
        adoption.props,
        fills.entries.map((e) => (e.key, e.value)),
      );
    }
    for (final c in schema.cases) {
      if (c.valueless && out.containsKey(c.key) && out[c.key] == null) {
        out[c.key] = true;
      }
    }
    final model = _validateUnion(schema, out, loc);
    if (model == null) {
      return _invalid;
    }
    model._fieldsSet.removeAll(filled);
    if (!model._hasCase) {
      if (tooNew != null) {
        throw tooNew;
      }
      if (!_truthy(pid) || adoption != null || model._extras.isNotEmpty) {
        return _fail(
          loc,
          'value_error',
          'Value error, ${schema.name}: no case present',
        );
      }
    }
    model
      .._primary = primary
      .._floor = _WireFloor.at(stamp, schema.version, model);
    return model;
  }

  TaggedUnionModel? _validateUnion(
    UnionSchema<TaggedUnionModel> schema,
    Map<String, Object?> out,
    List<Object> loc,
  ) {
    if (!_unicodeKeys(out, loc)) {
      return null;
    }
    final mark = issues.length;
    final model = schema._create();
    _presetIdentifierField(model, out, loc);
    for (final c in schema.cases) {
      if (!out.containsKey(c.key)) {
        continue;
      }
      final raw = out[c.key];
      final v = raw == null
          ? null
          : value(c._payloadType, raw, [...loc, c.key], lax: false);
      if (v is! _Invalid) {
        model._values[c.key] = v;
        model._fieldsSet.add(c.key);
      }
    }
    // Pydantic counts the unknown keys as set, too.
    for (final e in out.entries) {
      if (schema.caseSpec(e.key) == null && e.key != 'preset_identifier') {
        model._extras[e.key] = e.value;
        model._fieldsSet.add(e.key);
      }
    }
    return issues.length == mark ? model : null;
  }
}

Map<String, Object?>? _asJsonObject(Object? input) {
  if (input is Map<String, Object?>) {
    return input;
  }
  if (input is Map<Object?, Object?> && input.keys.every((k) => k is String)) {
    return input.cast<String, Object?>();
  }
  return null;
}

// `_gate_wire_version`: rejects a newer major version, and drops the keys that
// are newer than the version the JSON declares.
(Set<String>, Version?) _gateWireVersion(
  ModelSchema<WireModel> schema,
  Map<String, Object?> out,
  List<(String, Version)> specs,
  String dropped,
) {
  final wireV = out['version'];
  if (wireV == null) {
    return (const {}, null);
  }
  final wire = Version.parse(wireV);
  if (wire == null) {
    throw _ValueError('${schema.name}: unparsable version ${_repr(wireV)}');
  }
  final implemented = schema.version.major;
  if (wire.major > implemented) {
    throw DocumentVersionError(
      '${schema.name}: input declares version $wire but this library '
      'implements $implemented.x. Update this library to a newer version to '
      'read it.',
    );
  }
  final tooNew = {
    for (final (name, added) in specs)
      if (added > wire) name,
  };
  for (final name in tooNew) {
    if (out.containsKey(name)) {
      _log.warning(
        '${schema.name}.$name: the key is newer than the version $wire, so it '
        'decodes as $dropped.',
      );
      out.remove(name);
    }
  }
  return (tooNew, wire);
}
