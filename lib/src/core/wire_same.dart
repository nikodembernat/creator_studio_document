// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python): `_same_value` and
// `_same_as_preset` from `_wire.py`.

part of 'wire.dart';

// `_same_value`: equality that, unlike `==`, never matches `true` with `1` or
// `1` with `1.0`, and compares models field by field.
bool _sameValue(Object? a, Object? b) {
  if (a is bool || b is bool) {
    return a is bool && b is bool && a == b;
  }
  if (isPyNumber(a) && isPyNumber(b)) {
    return isPyInt(a) == isPyInt(b) && pyNumEquals(a!, b!);
  }
  if (a is WireModel && b is WireModel) {
    return _sameModel(a, b);
  }
  if (a is Override && b is Override) {
    return _overrideState(a) == _overrideState(b) &&
        _sameValue(a.get(), b.get());
  }
  if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _sameValue(a[k], b[k]));
  }
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!_sameValue(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  return _sameFallback(a, b);
}

// `type(a) is type(b) and a == b`, plus the shapes that `_WireFloor` compares.
bool _sameFallback(Object? a, Object? b) => switch ((a, b)) {
  (null, null) => true,
  (final String x, final String y) => x == y,
  (final _Same x, final _Same y) => identical(x.model, y.model),
  (final _OverrideShape x, final _OverrideShape y) =>
    x.state == y.state && _sameValue(x.value, y.value),
  (final _OwnShape x, final _OwnShape y) =>
    _sameValue(x.fields, y.fields) &&
        _sameValue(x.extras, y.extras) &&
        const SetEquality<String>().equals(x.fieldsSet, y.fieldsSet),
  (final Set<Object?> x, final Set<Object?> y) =>
    const SetEquality<Object?>().equals(x, y),
  (final WireEnum x, final WireEnum y) => identical(x, y),
  (final Object x, final Object y) => x.runtimeType == y.runtimeType && x == y,
  _ => false,
};

int _overrideState(Override<Object?> o) => switch (o) {
  OverrideNotSet() => 0,
  OverrideCleared() => 1,
  OverrideValue() => 2,
};

bool _sameModel(WireModel a, WireModel b) {
  if (!identical(a.wireSchema, b.wireSchema) ||
      a._presetIdentifier != b._presetIdentifier ||
      !_sameValue(a._values, b._values) ||
      !_sameValue(a._extras, b._extras)) {
    return false;
  }
  if (a is TaggedUnionModel && b is TaggedUnionModel) {
    return a._readPrimary() == b._readPrimary();
  }
  // The private state of an object model (`_wire_filled`, `_wire_floor`)
  // always compares equal. A field that keeps an int default holds an int
  // upstream, though, and an int never matches a float.
  return a is! ObjectModel ||
      b is! ObjectModel ||
      const SetEquality<String>().equals(a._intDefaults, b._intDefaults);
}

// The sentinel for "the field isn't in the fields set".
final class const _NotSet();

const _notSetJson = _NotSet();

// `_same_as_preset`.
bool _sameAsPreset(
  Object? value,
  Object? fill,
  Object? presetJson, [
  Object? ownJson = _notSetJson,
]) =>
    _sameValue(value, fill) &&
    (ownJson is _NotSet || sameJson(ownJson, presetJson));
