// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// The JSON codec every generated model inherits.
///
/// A field spec is (wire key, version added, [FieldKind]). The kind decides
/// when the field is on the wire:
///
/// - [FieldKind.req]: required, with no default. Always on the wire.
/// - [FieldKind.def]: has a default. On the wire only when explicitly set, so a
///   default instance omits it.
/// - [FieldKind.opt]: optional, with no default. On the wire when not `null`,
///   and can raise the version.
/// - [FieldKind.ovr]: an [Override] with no default. [Override.notSet] omits
///   the key, [Override.cleared] writes null, and [Override.value] writes the
///   value. Like [FieldKind.opt], it can raise the version when present.
/// - [FieldKind.ovrdef]: an [Override] with a default. An absent key decodes to
///   `Override.value(default)`. Like [FieldKind.def], it's on the wire only
///   when it's explicitly set.
///
/// An omittable field counts toward the version when it holds a value or a
/// clear. A `null` doesn't count, even where it's written.
///
/// An edit drops the version a value was decoded at instead of keeping it as a
/// floor. A newer key often takes precedence over an older one that stays as
/// the fallback for older readers, so keeping the floor can let unknown data
/// override the edit.
library;

import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:creator_studio_document/src/core/encode_error.dart';
import 'package:creator_studio_document/src/core/errors.dart';
import 'package:creator_studio_document/src/core/json.dart';
import 'package:creator_studio_document/src/core/override.dart';
import 'package:creator_studio_document/src/core/preset.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/core/version.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

part 'wire_decode.dart';
part 'wire_encode.dart';
part 'wire_preset.dart';
part 'wire_same.dart';

final _log = Logger('creator_studio_document.core.wire');

// ---------------------------------------------------------------------------
// Type descriptors
// ---------------------------------------------------------------------------

/// An enum whose members the JSON writes as strings.
abstract interface class WireEnum() {
  /// Creates the interface; enums implement it rather than extend it.
  this;

  /// The string that the JSON holds for the member.
  String get wireValue;
}

/// The type of a field or union case, as the runtime codec walks it.
///
/// Generated code builds these; most callers never touch them.
sealed class const WireType() {
  /// Creates the type.
  this;
}

/// A JSON boolean.
final class const BoolType() extends WireType {
  /// Creates the type.
  this;
}

/// A JSON integer. A float such as `1.0` is rejected.
///
/// Unlike upstream's Python ints, a Dart [int] holds 64 bits, and
/// `dart:convert` decodes a larger integer literal as a [double]. Such a value
/// is rejected as `int_type`, where upstream accepts it and writes it back
/// unchanged.
///
/// On the web, where `2.0 is int` is true, a decoded `2.0` can't be told from
/// `2`, so it's accepted, where upstream and the Dart VM reject it.
final class const IntType() extends WireType {
  /// Creates the type.
  this;
}

/// A JSON number, stored as a [double]. NaN and infinities are rejected.
///
/// On the web, `jsonEncode` writes a whole double such as `1.0` as `1`, where
/// upstream writes `1.0`; both decode to the same value.
final class const FloatType() extends WireType {
  /// Creates the type.
  this;
}

/// A JSON string.
final class const StringType() extends WireType {
  /// Creates the type.
  this;
}

/// The payload of a valueless union case: `true`, or a number equal to 1,
/// which decodes as `true`.
final class const LiteralTrueType() extends WireType {
  /// Creates the type.
  this;
}

/// A string enum.
///
/// A strict enum accepts only a member of [E]; a lax one, marked
/// `Strict(False)` upstream, also accepts the member's wire string.
final class const EnumType<E extends WireEnum>(
  /// The enum's name.
  final String name,

  /// Every member of the enum.
  final List<E> values, {

  /// Whether the enum rejects wire strings unless decoding is lax.
  final bool strict = true,
}) extends WireType {
  /// Creates the type for the members [values].
  this;

  /// Returns the member whose wire value is [wire], or `null`.
  E? byWire(String wire) {
    for (final v in values) {
      if (v.wireValue == wire) {
        return v;
      }
    }
    return null;
  }

  bool _isMember(Object? value) => value is E;
}

/// A generated model, decoded through its schema.
final class ModelType<M extends WireModel>(
  final ModelSchema<M> Function() _schema,
) extends WireType {
  /// Creates the type. [schema] is a function so that models can refer to
  /// each other.
  this;

  /// The model's schema.
  ModelSchema<M> get schema => _schema();
}

/// A JSON array.
final class const ListType<T>(
  /// The element type.
  final WireType of,
) extends WireType {
  /// Creates the type of a list of [of].
  this;

  List<T> _build(List<Object?> items) => List<T>.from(items);
}

/// A value that can also be `null`.
final class const NullableType(
  /// The type of a non-null value.
  final WireType of,
) extends WireType {
  /// Creates the type.
  this;
}

/// An [Override] around [of].
final class const OverrideType<T>(
  /// The type of the value an override holds.
  final WireType of,
) extends WireType {
  /// Creates the type.
  this;

  Override<T> _notSet() => Override<T>.notSet();

  Override<T> _cleared() => Override<T>.cleared();

  Override<T> _value(Object? value) => Override<T>.value(value as T);
}

// ---------------------------------------------------------------------------
// Schemas
// ---------------------------------------------------------------------------

/// When a field is on the wire. See the library documentation.
enum FieldKind() {
  /// Required, with no default.
  req,

  /// Has a default.
  def,

  /// Optional, with no default.
  opt,

  /// An [Override] with no default.
  ovr,

  /// An [Override] with a default.
  ovrdef,
}

/// The metadata of one field of an [ObjectModel].
final class FieldSpec(
  /// The JSON key, which is also the upstream field name.
  final String key,

  /// The version that introduced the field.
  final Version added,

  /// When the field is on the wire.
  final FieldKind kind,

  /// The field's type. An [FieldKind.opt] field is a [NullableType], and an
  /// override field an [OverrideType].
  final WireType type, {

  /// Returns a fresh default value, for [FieldKind.def] and
  /// [FieldKind.ovrdef] fields.
  final Object? Function()? defaultValue,

  /// Whether the preset gate validates the field leniently, because its
  /// annotation is an enum.
  final bool presetGateLax = false,

  /// Whether upstream's default is an `int` in this float field.
  ///
  /// Pydantic doesn't validate defaults, so upstream holds that int until the
  /// field is set. The value reads as a [double] here, but the model keeps
  /// track of it, so a default model edited in place to the same number, such
  /// as `line.width = 1.0`, no longer matches the default when encoding.
  final bool intDefault = false,

  /// The inclusive lower bound of a number.
  final num? ge,

  /// The inclusive upper bound of a number.
  final num? le,

  /// The exclusive lower bound of a number.
  final num? gt,

  /// The exclusive upper bound of a number.
  final num? lt,

  /// The minimum length of a list.
  final int? minLength,

  /// The maximum length of a list.
  final int? maxLength,
}) {
  /// Creates the spec of the field [key].
  this;

  bool get _isOverride => kind == FieldKind.ovr || kind == FieldKind.ovrdef;

  bool get _isBase => kind == FieldKind.req || kind == FieldKind.def;

  // The annotation without its `Override`, which presets validate against.
  WireType get _presetAnnotation => switch (type) {
    OverrideType(:final of) => of,
    final other => other,
  };

  Object? _initial() => switch (kind) {
    FieldKind.def || FieldKind.ovrdef => defaultValue!(),
    FieldKind.ovr => (type as OverrideType<Object?>)._notSet(),
    FieldKind.req || FieldKind.opt => null,
  };
}

/// The metadata of one case of a [TaggedUnionModel].
final class CaseSpec(
  /// The JSON key, which is also the case name.
  final String key,

  /// The version that introduced the case.
  final Version added, {

  /// The payload type, or `null` for a valueless case.
  final WireType? type,
}) {
  /// Creates the spec of the case [key].
  this;

  /// Whether the case has no payload.
  bool get valueless => type == null;

  WireType get _payloadType => type ?? const LiteralTrueType();
}

/// The metadata of a generated model class, which the runtime codec reads.
sealed class ModelSchema<M extends WireModel>._({
  /// The class name.
  required final String name,

  /// The `type_identifier` that the JSON carries.
  required final String typeId,

  /// The version this library implements.
  required final Version version,
  required final M Function() _create,
}) {
  /// Decodes [json] into a model, resolving presets through [context].
  ///
  /// Throws [ModelValidationError] if the JSON doesn't match the model, and
  /// [DocumentVersionError] if it declares a newer major version.
  M fromJson(Object? json, [WireContext? context]) {
    final decoder = _Decoder(context ?? WireContext());
    final value = decoder._model(this, json, const []);
    if (decoder.issues.isNotEmpty || value is _Invalid) {
      throw ModelValidationError(name, decoder.issues);
    }
    return value! as M;
  }

  bool _accepts(Object? value) => value is M;
}

/// The schema of an [ObjectModel].
final class ObjectSchema<M extends ObjectModel>({
  required super.name,
  required super.typeId,
  required super.version,
  required super.create,

  /// The fields, in declaration order.
  required final List<FieldSpec> fields,
}) extends ModelSchema<M> {
  /// Creates the schema.
  this : super._();

  late final Map<String, FieldSpec> _byKey = {for (final f in fields) f.key: f};

  /// Returns the spec of the field [key], or `null`.
  FieldSpec? field(String key) => _byKey[key];
}

/// The schema of a [TaggedUnionModel].
final class UnionSchema<M extends TaggedUnionModel>({
  required super.name,
  required super.typeId,
  required super.version,
  required super.create,

  /// The cases, in declaration order.
  required final List<CaseSpec> cases,
}) extends ModelSchema<M> {
  /// Creates the schema.
  this : super._();

  late final Map<String, CaseSpec> _byKey = {for (final c in cases) c.key: c};

  /// Returns the spec of the case [key], or `null`.
  CaseSpec? caseSpec(String key) => _byKey[key];
}

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

/// The options that decoding and encoding pass down to every nested model.
///
/// It replaces upstream's Pydantic `context` dictionary.
final class WireContext {
  /// Creates a context. [presets] resolves `preset_identifier` adoptions;
  /// [strictPresets] skips validating a preset's values before filling them.
  new({this.presets, this.strictPresets = false})
    : gateDepth = 0,
      _sink = _VersionErrorSink();

  new _gate(WireContext parent, {required this.gateDepth})
    : presets = parent.presets,
      strictPresets = parent.strictPresets || gateDepth >= _maxPresetGateDepth,
      _sink = parent._sink;

  /// The registry that resolves preset adoptions, or `null` for none.
  final PresetRegistry? presets;

  /// Whether preset values fill fields without being validated first.
  final bool strictPresets;

  /// How many preset gates this context is nested in.
  @internal
  final int gateDepth;

  final _VersionErrorSink _sink;

  /// The first [DocumentVersionError] that encoding hit for a union whose
  /// only cases are newer than this library, if any.
  DocumentVersionError? get versionError => _sink.error;
}

final class _VersionErrorSink() {
  DocumentVersionError? error;
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// The base of every generated model.
///
/// Besides the fields, the JSON carries an envelope that keeps documents
/// compatible across versions, backward and forward. [toJson] writes its
/// `type_identifier` and `version` itself, so neither is a field.
///
/// Unknown keys are preserved in [extras] and written back in order. A setter
/// validates as strictly as construction does. A change in place, such as
/// `m.items.add(bad)`, skips validation; reassign the whole field to
/// revalidate it.
abstract class WireModel._blank(
  /// The metadata the codec reads.
  final ModelSchema<WireModel> wireSchema,
) {
  Map<String, Object?> _values = {};
  String _presetIdentifier = '';
  Map<String, Object?> _extras = {};
  Set<String> _fieldsSet = {};
  _WireFloor _floor = _WireFloor.none;

  /// The identifier of the preset this object adopts, or the empty string.
  String get presetIdentifier => _presetIdentifier;

  set presetIdentifier(String value) {
    _presetIdentifier = value;
    _fieldsSet.add('preset_identifier');
  }

  /// The keys that the JSON held but this library doesn't know, in order.
  ///
  /// Changing the map changes what [toJson] writes.
  Map<String, Object?> get extras => _extras;

  /// The fields that were explicitly set, by construction, decoding, or
  /// assignment, by wire key.
  ///
  /// Like Pydantic's `model_fields_set`, it also holds the unknown keys that
  /// decoding kept in [extras], and, on an object that a preset filled when
  /// it was decoded, upstream's internal `'\u0000wire_filled'` key.
  Set<String> get fieldsSet => UnmodifiableSetView(_fieldsSet);

  /// Encodes the model as JSON, factoring out values that the adopted preset
  /// supplies through [context].
  ///
  /// Throws [StateError] for a union with no case to write, and, as
  /// Pydantic's serializer limits it, for a value nested more than 256
  /// levels deep, counting this model as 1 and each model, list, map, and
  /// value inside it as one level deeper.
  Object toJson([WireContext? context]);

  /// Returns a deep copy that keeps every piece of private state.
  WireModel deepCopy() => _copyModel(this, Map.identity());

  /// Returns the value of the field or case whose wire key is [key].
  ///
  /// The typed getters of the generated classes call it; prefer them.
  Object? wireGet(String key) => _values[key];

  /// Validates [value], stores it in the field or case whose wire key is
  /// [key], and marks the field set.
  ///
  /// It validates as upstream's `setattr` does, as strictly as decoding: a
  /// float field takes an `int` and stores a `double`, an override field
  /// wraps a bare value and reads `null` as cleared, an enum field that
  /// accepts wire strings converts one, and a model field takes the model or
  /// its JSON. The typed setters of the generated classes call it; prefer
  /// them. Throws [ModelValidationError] if [value] doesn't match the field's
  /// type or breaks one of its constraints.
  void wireSet(String key, Object? value);

  String get _name => wireSchema.name;

  @override
  String toString() {
    final parts = [
      if (_presetIdentifier.isNotEmpty)
        'preset_identifier: ${_repr(_presetIdentifier)}',
      for (final e in _values.entries) '${e.key}: ${_repr(e.value)}',
      for (final e in _extras.entries) '${e.key}: ${_repr(e.value)}',
    ];
    return '$_name(${parts.join(', ')})';
  }
}

/// The base for the model of every object that isn't a tagged union.
abstract class ObjectModel extends WireModel {
  /// Creates an empty model for the decoder.
  @protected
  new blank(ObjectSchema<ObjectModel> super.schema) : super._blank();

  /// Creates a model from constructor arguments. A `null` argument means the
  /// argument wasn't passed.
  @protected
  new construct(
    ObjectSchema<ObjectModel> schema,
    Map<String, Object?> args, {
    String? presetIdentifier,
  }) : super._blank(schema) {
    final issues = <ValidationIssue>[];
    for (final spec in schema.fields) {
      final value = args[spec.key];
      if (value == null) {
        _values[spec.key] = spec._initial();
        if (spec.intDefault) {
          _intDefaults.add(spec.key);
        }
        if (spec.kind == FieldKind.req) {
          issues.add(
            ValidationIssue([spec.key], 'Field required', type: 'missing'),
          );
        }
        continue;
      }
      _checkConstraints(spec, value, [spec.key], issues);
      _values[spec.key] = _ownLists(value);
      _fieldsSet.add(spec.key);
    }
    if (presetIdentifier != null) {
      this.presetIdentifier = presetIdentifier;
    }
    if (issues.isNotEmpty) {
      throw ModelValidationError(schema.name, issues);
    }
  }

  _PresetFilled _filled = _PresetFilled.none;

  // The fields that still hold an int default, by wire key. See
  // [FieldSpec.intDefault].
  Set<String> _intDefaults = {};

  ObjectSchema<ObjectModel> get _schema =>
      wireSchema as ObjectSchema<ObjectModel>;

  @override
  Map<String, Object?> toJson([WireContext? context]) =>
      _nested(() => _ObjectEncoder(this, context).encode());

  @override
  void wireSet(String key, Object? value) {
    final spec = _schema.field(key);
    if (spec == null) {
      throw ArgumentError.value(key, 'key', '$_name has no field');
    }
    final decoder = _Decoder(WireContext());
    final validated = decoder._field(spec, value, [key]);
    if (validated is _Invalid) {
      throw ModelValidationError(_name, decoder.issues);
    }
    _values[key] = validated;
    _intDefaults.remove(key);
    _fieldsSet.add(key);
  }

  @override
  bool operator ==(Object other) =>
      other is ObjectModel &&
      identical(other.wireSchema, wireSchema) &&
      other._presetIdentifier == _presetIdentifier &&
      pyEquals(other._values, _values) &&
      pyEquals(other._extras, _extras);

  @override
  int get hashCode => Object.hash(
    wireSchema,
    _presetIdentifier,
    pyHash(_values),
    pyHash(_extras),
  );
}

/// One case of a [TaggedUnionModel] with its payload.
///
/// Each generated union has a sealed subclass hierarchy, so a `switch` over
/// `unionPrimary()` is exhaustive.
abstract class const UnionCase() {
  /// Creates the case.
  this;

  /// The case name, as the JSON spells it.
  String get name;

  /// The payload, or `true` for a valueless case.
  Object get payload;

  @override
  bool operator ==(Object other) =>
      other is UnionCase &&
      other.name == name &&
      pyEquals(other.payload, payload);

  @override
  int get hashCode => Object.hash(name, pyHash(payload));

  @override
  String toString() => '($name, $payload)';
}

/// The base for every tagged union, a property that holds one of several
/// cases.
///
/// A subclass declares one nullable property per case: the payload, or a
/// `bool` for a case with no payload. A document can also hold a second case,
/// such as a newer encoding beside an older one. The primary case is the one a
/// reader acts on, and editing only the primary leaves the others stale.
///
/// Read a value with a `switch` on `unionPrimary()`, so a case added later is
/// a compile error.
///
/// A union adopts a preset through [presetIdentifier], as an object does.
/// Without a designation, the preset can supply the primary, so pin it with
/// the generated `unionOf` constructor.
abstract class TaggedUnionModel extends WireModel {
  /// Creates an empty model for the decoder.
  @protected
  new blank(UnionSchema<TaggedUnionModel> super.schema) : super._blank() {
    for (final c in _schema.cases) {
      _values[c.key] = null;
    }
  }

  /// Creates a model from constructor arguments. A `null` argument means the
  /// case wasn't passed.
  @protected
  new construct(
    UnionSchema<TaggedUnionModel> schema,
    Map<String, Object?> cases, {
    String? presetIdentifier,
  }) : super._blank(schema) {
    final issues = <ValidationIssue>[];
    for (final c in schema.cases) {
      final value = cases[c.key];
      _values[c.key] = _ownLists(value);
      if (value != null) {
        _finite(c._payloadType, value, [c.key], issues);
        _fieldsSet.add(c.key);
      }
    }
    if (issues.isNotEmpty) {
      throw ModelValidationError(schema.name, issues);
    }
    if (presetIdentifier != null) {
      this.presetIdentifier = presetIdentifier;
    }
    if (_presetIdentifier.isEmpty && !_hasCase) {
      throw ModelValidationError(schema.name, [
        ValidationIssue(
          const [],
          'Value error, ${schema.name}: no case present',
          type: 'value_error',
        ),
      ]);
    }
  }

  Object? _primary;

  UnionSchema<TaggedUnionModel> get _schema =>
      wireSchema as UnionSchema<TaggedUnionModel>;

  bool get _hasCase => _values.values.any((v) => v != null);

  /// Validates that [primary] names a case of [schema], then designates it
  /// the primary case of the model that [build] creates.
  @protected
  static M designate<M extends TaggedUnionModel>(
    UnionSchema<M> schema,
    String primary,
    M Function() build,
  ) {
    if (schema.caseSpec(primary) == null) {
      throw ArgumentError.value(
        primary,
        'primary',
        '${schema.name}: unknown primary case',
      );
    }
    return build().._primary = primary;
  }

  @override
  Object toJson([WireContext? context]) =>
      _nested(() => _UnionEncoder(this, context).encode());

  @override
  void wireSet(String key, Object? value) {
    final spec = _schema.caseSpec(key);
    if (spec == null) {
      throw ArgumentError.value(key, 'key', '$_name has no case');
    }
    final decoder = _Decoder(WireContext());
    final validated = decoder.value(NullableType(spec._payloadType), value, [
      key,
    ], lax: false);
    if (validated is _Invalid) {
      throw ModelValidationError(_name, decoder.issues);
    }
    _values[key] = validated;
    _fieldsSet.add(key);
  }

  /// Returns the typed case for [name] and [payload].
  @protected
  UnionCase wireCase(String name, Object payload);

  /// Returns the cases that the value holds, primary first, then the others
  /// by name, as `(case name, payload)` pairs.
  ///
  /// The primary is the designated case, else the newest. Cases this library
  /// doesn't know are left out, though a round trip still preserves them. The
  /// result is empty only for a value with no case set.
  List<(String, Object)> unionCaseEntries() {
    final present = <(String, Object)>[
      for (final c in _schema.cases)
        if (_values[c.key] case final Object value) (c.key, value),
    ];
    if (present.isEmpty) {
      return const [];
    }
    final names = [for (final (n, _) in present) n];
    final String primary;
    if (_primary case final String p when names.contains(p)) {
      primary = p;
    } else {
      final added = {for (final c in _schema.cases) c.key: c.added};
      primary = _newestCase([for (final n in names) (n, added[n]!)]);
    }
    return present..sort((a, b) => _primaryFirst(a.$1, b.$1, primary));
  }

  /// Returns the cases that the value holds, primary first, then the others
  /// by name.
  List<UnionCase> unionCases() => [
    for (final (name, payload) in unionCaseEntries()) wireCase(name, payload),
  ];

  /// Returns the case that a reader acts on, with its payload, or `null` if
  /// no case is set.
  UnionCase? unionPrimary() {
    final entries = unionCaseEntries();
    return entries.isEmpty ? null : wireCase(entries[0].$1, entries[0].$2);
  }

  /// Returns the name of the case that a reader acts on, or `null` if no case
  /// is set.
  String? unionPrimaryName() => unionCaseEntries().firstOrNull?.$1;

  String? _designatedPrimary(Iterable<String> cases, Iterable<String> unknown) {
    final designated = _primary;
    if (designated is! String || designated.isEmpty) {
      return null;
    }
    if (unknown.contains(designated) || cases.contains(designated)) {
      return designated;
    }
    return null;
  }

  (String?, String?) _readPrimary() {
    final shown = unionPrimaryName();
    final name = _designatedPrimary([
      for (final c in _schema.cases) c.key,
    ], _extras.keys);
    return (shown, name == shown ? null : name);
  }

  @override
  bool operator ==(Object other) =>
      other is TaggedUnionModel &&
      identical(other.wireSchema, wireSchema) &&
      other._presetIdentifier == _presetIdentifier &&
      pyEquals(other._values, _values) &&
      pyEquals(other._extras, _extras) &&
      other._readPrimary() == _readPrimary();

  @override
  int get hashCode => Object.hash(
    wireSchema,
    _presetIdentifier,
    pyHash(_values),
    pyHash(_extras),
  );
}

int _primaryFirst(String a, String b, String primary) {
  final aFirst = a == primary ? 0 : 1;
  final bFirst = b == primary ? 0 : 1;
  return aFirst != bFirst ? aFirst - bFirst : a.compareTo(b);
}

String _newestCase(Iterable<(String, Version)> cases) {
  (String, Version)? best;
  for (final c in cases) {
    if (best == null ||
        c.$2 > best.$2 ||
        (c.$2 == best.$2 && c.$1.compareTo(best.$1) < 0)) {
      best = c;
    }
  }
  return best!.$1;
}

/// Decodes [json] as a value of [type], the way upstream validates a value
/// assigned to a field: strictly, and with constraints left to the setter.
///
/// Throws [ModelValidationError] if [json] doesn't match [type].
@internal
Object? decodeWireValue(WireType type, Object? json, [WireContext? context]) {
  final decoder = _Decoder(context ?? WireContext());
  final value = decoder.value(type, json, const [], lax: false);
  if (decoder.issues.isNotEmpty || value is _Invalid) {
    throw ModelValidationError('$type', decoder.issues);
  }
  return value;
}

/// Revalidates the values that [model] holds against its declaration, as
/// upstream's `validate_field_types` revalidates `model.__dict__`.
///
/// It checks each field's type and constraints, or each case's type and that
/// a union without a `preset_identifier` holds a case, which a union with a
/// valueless case always does upstream. A nested model is
/// taken as it is, and the unknown keys aren't checked. Returns the issues
/// in field order, with locations relative to [model].
@internal
List<ValidationIssue> revalidateWireModel(WireModel model) {
  final decoder = _Decoder(WireContext());
  switch (model) {
    case final ObjectModel m:
      for (final spec in m._schema.fields) {
        decoder._field(spec, m._values[spec.key], [spec.key]);
      }
    case final TaggedUnionModel m:
      for (final c in m._schema.cases) {
        if (m._values[c.key] case final Object v) {
          decoder.value(c._payloadType, v, [c.key], lax: false);
        }
      }
      // Upstream revalidates every case key, and decoding reads a valueless
      // case's `None` as present, so a union with one never lacks a case.
      if (decoder.issues.isEmpty &&
          !m._hasCase &&
          m._presetIdentifier == '' &&
          !m._schema.cases.any((c) => c.valueless)) {
        decoder._fail(
          const [],
          'value_error',
          'Value error, ${m._name}: no case present',
        );
      }
  }
  return decoder.issues;
}

/// Returns the primary case that [model] was designated with, by decoding
/// or by `unionOf`, as it was given: possibly a name this library doesn't
/// know, or not a string at all. Returns `null` if none was.
@internal
Object? designatedPrimaryCase(TaggedUnionModel model) => model._primary;

// ---------------------------------------------------------------------------
// Constraints
// ---------------------------------------------------------------------------

void _checkConstraints(
  FieldSpec spec,
  Object? value,
  List<Object> loc,
  List<ValidationIssue> issues,
) {
  if (_tooLong(spec, value, loc, issues) ||
      !_finite(spec.type, value, loc, issues)) {
    return;
  }
  final inner = value is Override ? value.get() : value;
  if (inner is num) {
    _checkBounds(spec, inner, loc, issues);
  } else if (inner is List<Object?>) {
    _checkLength(spec, inner, loc, issues);
  }
}

bool _finite(
  WireType type,
  Object? value,
  List<Object> loc,
  List<ValidationIssue> issues,
) {
  switch (type) {
    case FloatType() when value is double && !value.isFinite:
      issues.add(
        ValidationIssue(
          loc,
          'Input should be a finite number',
          type: 'finite_number',
        ),
      );
      return false;
    case NullableType(:final of):
      return value == null || _finite(of, value, loc, issues);
    case OverrideType(:final of):
      return value is! OverrideValue || _finite(of, value.value, loc, issues);
    case ListType(:final of) when value is List<Object?>:
      var ok = true;
      for (var i = 0; i < value.length; i++) {
        ok = _finite(of, value[i], [...loc, i], issues) && ok;
      }
      return ok;
    default:
      return true;
  }
}

void _checkBounds(
  FieldSpec spec,
  num value,
  List<Object> loc,
  List<ValidationIssue> issues,
) {
  void add(String type, String message) =>
      issues.add(ValidationIssue(loc, message, type: type));
  if (spec.ge case final ge? when !(value >= ge)) {
    add('greater_than_equal', 'Input should be greater than or equal to $ge');
  }
  if (spec.gt case final gt? when !(value > gt)) {
    add('greater_than', 'Input should be greater than $gt');
  }
  if (spec.le case final le? when !(value <= le)) {
    add('less_than_equal', 'Input should be less than or equal to $le');
  }
  if (spec.lt case final lt? when !(value < lt)) {
    add('less_than', 'Input should be less than $lt');
  }
}

void _checkLength(
  FieldSpec spec,
  List<Object?> value,
  List<Object> loc,
  List<ValidationIssue> issues,
) {
  final n = value.length;
  if (spec.minLength case final min? when n < min) {
    issues.add(
      ValidationIssue(
        loc,
        'List should have at least $min item${min == 1 ? '' : 's'} after '
        'validation, not $n',
        type: 'too_short',
      ),
    );
  }
  if (spec.maxLength case final max? when n > max) {
    issues.add(_tooLongIssue(max, n, loc));
  }
}

// pydantic-core counts a list's items as it validates them, and stops at the
// first one past `max_length`. That issue replaces the issues of the items
// before it, so a list that is too long reports only `too_long`, whatever its
// items hold. Records the issue and returns `true` for such a list.
bool _tooLong(
  FieldSpec spec,
  Object? value,
  List<Object> loc,
  List<ValidationIssue> issues,
) {
  final list = value is OverrideValue ? value.value : value;
  if (spec.maxLength case final max?
      when list is List<Object?> && list.length > max) {
    issues.add(_tooLongIssue(max, list.length, loc));
    return true;
  }
  return false;
}

ValidationIssue _tooLongIssue(int max, int n, List<Object> loc) =>
    ValidationIssue(
      loc,
      'List should have at most $max item${max == 1 ? '' : 's'} after '
      'validation, not $n',
      type: 'too_long',
    );

// ---------------------------------------------------------------------------
// Preset fill
// ---------------------------------------------------------------------------

// The key under which upstream's `_wire_before` passes the filled fields to
// `_wire_inherited`, through the validated data.
const _filledKey = '\u0000wire_filled';

// `_PresetFilled`: the fields that a preset filled when the object was
// decoded. Upstream hands them over under [_filledKey] among the input's
// keys, so an input that adopts a preset and holds that key itself, with no
// field filled, sets the value instead. Testing a field against it then
// follows Python's `in`: a list or an object by member, a string by
// substring, and a number or a Boolean raises `TypeError`.
final class const _PresetFilled(final Object keys) {
  static const none = _PresetFilled(<String>{});

  bool contains(String key) => switch (keys) {
    final Set<Object?> s => s.contains(key),
    final List<Object?> l => l.contains(key),
    final Map<Object?, Object?> m => m.containsKey(key),
    final String s => s.contains(key),
    _ => throw ArgumentError(
      "argument of type '${pyTypeName(keys)}' is not iterable",
    ),
  };
}

// ---------------------------------------------------------------------------
// Version floor
// ---------------------------------------------------------------------------

// The version a model with unknown keys was decoded at. While the model stays
// as decoded, encoding keeps that version, so a newer reader still reads the
// unknown keys.
final class const _WireFloor._(
  final Version? version,
  final _OwnShape? decoded,
) {
  factory at(Version? stamp, Version schema, WireModel model) {
    if (stamp == null || stamp <= schema || model._extras.isEmpty) {
      return none;
    }
    return _WireFloor._(stamp, _ownShape(model));
  }

  static const none = _WireFloor._(null, null);

  bool holds(WireModel model) {
    final version = this.version;
    if (version == null || model._extras.isEmpty) {
      return false;
    }
    if (_sameValue(_ownShape(model), decoded)) {
      return true;
    }
    final keys = model._extras.keys.toList()..sort(compareCodePoints);
    _log.warning(
      '${model._name}: edited after decoding at $version. Its unknown keys '
      '[${keys.map(_repr).join(', ')}] are kept, but a newer reader ignores '
      'any that are newer than the version written.',
    );
    return false;
  }

  _WireFloor _copy(Map<WireModel, WireModel> memo) =>
      decoded == null ? this : _WireFloor._(version, decoded!._copy(memo));
}

// What an edit changes: the fields and unknown keys, with nested models by
// identity, and which fields are set.
final class _OwnShape(
  final Object? fields,
  final Object? extras,
  final Set<String> fieldsSet,
) {
  _OwnShape _copy(Map<WireModel, WireModel> memo) => _OwnShape(
    _copyShape(fields, memo),
    _copyShape(extras, memo),
    Set.of(fieldsSet),
  );
}

final class _Same(final WireModel model);

final class _OverrideShape(final int state, final Object? value);

_OwnShape _ownShape(WireModel model) => _OwnShape(
  _editShape({'preset_identifier': model._presetIdentifier, ...model._values}),
  _editShape(model._extras),
  Set.of(model._fieldsSet),
);

Object? _editShape(Object? value) => switch (value) {
  final WireModel m => _Same(m),
  OverrideNotSet() => _OverrideShape(0, null),
  OverrideCleared() => _OverrideShape(1, null),
  OverrideValue(:final value) => _OverrideShape(2, _editShape(value)),
  final List<Object?> list => [for (final v in list) _editShape(v)],
  final Map<Object?, Object?> map => {
    for (final e in map.entries) e.key: _editShape(e.value),
  },
  _ => value,
};

Object? _copyShape(Object? shape, Map<WireModel, WireModel> memo) =>
    switch (shape) {
      final _Same s => _Same(_copyModel(s.model, memo)),
      final _OverrideShape o => _OverrideShape(
        o.state,
        _copyShape(o.value, memo),
      ),
      final List<Object?> list => [for (final v in list) _copyShape(v, memo)],
      final Map<Object?, Object?> map => {
        for (final e in map.entries) e.key: _copyShape(e.value, memo),
      },
      _ => shape,
    };

// ---------------------------------------------------------------------------
// Deep copy
// ---------------------------------------------------------------------------

M _copyModel<M extends WireModel>(M model, Map<WireModel, WireModel> memo) {
  if (memo[model] case final M existing) {
    return existing;
  }
  final copy = model.wireSchema._create() as M;
  memo[model] = copy;
  copy
    .._values = {
      for (final e in model._values.entries) e.key: _copyValue(e.value, memo),
    }
    .._presetIdentifier = model._presetIdentifier
    .._extras = {
      for (final e in model._extras.entries) e.key: _copyValue(e.value, memo),
    }
    .._fieldsSet = Set.of(model._fieldsSet);
  if (model is ObjectModel) {
    (copy as ObjectModel)
      .._filled = model._filled
      .._intDefaults = Set.of(model._intDefaults);
  } else if (model is TaggedUnionModel) {
    (copy as TaggedUnionModel)._primary = _copyValue(model._primary, memo);
  }
  copy._floor = model._floor._copy(memo);
  return copy;
}

Object? _copyValue(Object? value, Map<WireModel, WireModel> memo) {
  switch (value) {
    case final WireModel m:
      return _copyModel(m, memo);
    case final OverrideValue<Object?> o:
      return o.withValue(_copyValue(o.value, memo));
    case final List<Object?> list:
      // `toList` keeps the list's element type.
      final copy = list.toList();
      for (var i = 0; i < copy.length; i++) {
        copy[i] = _copyValue(copy[i], memo);
      }
      return copy;
    case final Map<String, Object?> map:
      return <String, Object?>{
        for (final e in map.entries) e.key: _copyValue(e.value, memo),
      };
    case final Map<Object?, Object?> map:
      return <Object?, Object?>{
        for (final e in map.entries) e.key: _copyValue(e.value, memo),
      };
  }
  return value;
}

// Pydantic's strict validation builds a new list, so a model never shares one
// with the caller, and a later change to the caller's list doesn't reach the
// model. Models inside stay shared, as Pydantic doesn't revalidate them.
Object? _ownLists(Object? value) {
  switch (value) {
    case final OverrideValue<Object?> o when o.value is List<Object?>:
      return o.withValue(_ownLists(o.value));
    case final List<Object?> list:
      // `toList` keeps the list's element type.
      final copy = list.toList();
      for (var i = 0; i < copy.length; i++) {
        copy[i] = _ownLists(copy[i]);
      }
      return copy;
  }
  return value;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Python's `repr` for the values that messages quote.
String _repr(Object? value) => switch (value) {
  final WireEnum e => pyStringRepr(e.wireValue),
  final List<Object?> l => '[${l.map(_repr).join(', ')}]',
  final Map<Object?, Object?> m =>
    '{${m.entries.map((e) => '${_repr(e.key)}: ${_repr(e.value)}').join(', ')}}',
  _ => pyRepr(value),
};

// Python truthiness of a JSON value.
bool _truthy(Object? value) => switch (value) {
  null || false => false,
  final num n => n != 0,
  final BigInt n => n != BigInt.zero,
  final String s => s.isNotEmpty,
  final List<Object?> l => l.isNotEmpty,
  final Map<Object?, Object?> m => m.isNotEmpty,
  _ => true,
};
