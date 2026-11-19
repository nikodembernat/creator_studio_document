// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// Returns whether two parsed JSON values are equal.
///
/// Two strings of JSON text compare only as strings, so parse the text first.
/// Key order doesn't matter, but array order does. Numbers compare by value, so
/// `1` equals `1.0`, and a [BigInt], which a package holds for an integer too
/// large for an [int], equals the number it spells exactly. `true` and `false`
/// never equal `1` and `0`. A `null` differs from an absent key.
bool sameJson(Object? a, Object? b) {
  if (a is bool || b is bool) {
    return a is bool && b is bool && a == b;
  }
  if (isPyNumber(a) && isPyNumber(b)) {
    return pyNumEquals(a!, b!);
  }
  if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && sameJson(a[k], b[k]));
  }
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!sameJson(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  if (a is Map<Object?, Object?> ||
      b is Map<Object?, Object?> ||
      a is List<Object?> ||
      b is List<Object?>) {
    return false;
  }
  if (a is String || b is String) {
    return a is String && b is String && a == b;
  }
  return a == b;
}

/// Python's `==` over the values a model holds: numbers compare by value,
/// `true` equals `1`, and lists and maps compare by content.
bool pyEquals(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if ((isPyNumber(a) || a is bool) && (isPyNumber(b) || b is bool)) {
    return pyNumEquals(_pyNum(a!), _pyNum(b!));
  }
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!pyEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && pyEquals(a[k], b[k]));
  }
  if (a is List<Object?> ||
      b is List<Object?> ||
      a is Map<Object?, Object?> ||
      b is Map<Object?, Object?>) {
    return false;
  }
  return a == b;
}

Object _pyNum(Object value) => switch (value) {
  true => 1,
  false => 0,
  _ => value,
};

/// Whether [value] is a JSON number: an [int], a [double], or a [BigInt],
/// which holds an integer too large for an [int].
bool isPyNumber(Object? value) => value is num || value is BigInt;

/// Whether [value] is what Python holds as an `int`: an [int] or a [BigInt].
bool isPyInt(Object? value) => value is int || value is BigInt;

/// Python's `==` between two numbers, each an [int], a [double], or a
/// [BigInt]: exact, as Python compares an `int` with a `float`.
bool pyNumEquals(Object a, Object b) {
  if (a is! BigInt && b is! BigInt) {
    return a == b;
  }
  final x = _exactInt(a);
  final y = _exactInt(b);
  return x != null && y != null && x == y;
}

/// Python's ordering of two numbers, each an [int], a [double], or a
/// [BigInt], as [Comparable.compareTo] reports it.
int pyNumCompare(Object a, Object b) {
  if (a is! BigInt && b is! BigInt) {
    return (a as num).compareTo(b as num);
  }
  final x = _floorInt(a);
  final y = _floorInt(b);
  if (x == null || y == null) {
    return _toDouble(a).compareTo(_toDouble(b));
  }
  final byInt = x.compareTo(y);
  return byInt != 0 ? byInt : _fraction(a).compareTo(_fraction(b));
}

BigInt? _exactInt(Object n) => switch (n) {
  final BigInt b => b,
  final int i => BigInt.from(i),
  final double d when d.isFinite && d == d.truncateToDouble() => BigInt.from(d),
  _ => null,
};

BigInt? _floorInt(Object n) => switch (n) {
  final BigInt b => b,
  final int i => BigInt.from(i),
  final double d when d.isFinite => BigInt.from(d.floorToDouble()),
  _ => null,
};

double _fraction(Object n) => n is double ? n - n.floorToDouble() : 0;

double _toDouble(Object n) => switch (n) {
  final BigInt b => b.toDouble(),
  final num x => x.toDouble(),
  _ => throw ArgumentError.value(n),
};

/// A hash code consistent with [pyEquals].
int pyHash(Object? value) => switch (value) {
  null => 0,
  final bool b => (b ? 1 : 0).hashCode,
  final num n => n.hashCode,
  // An equal [int] or [double], where one exists, hashes the same.
  final BigInt n => n.isValidInt ? n.toInt().hashCode : n.toDouble().hashCode,
  final List<Object?> list => Object.hashAll(list.map(pyHash)),
  final Map<Object?, Object?> map => Object.hashAllUnordered(
    map.entries.map((e) => Object.hash(pyHash(e.key), pyHash(e.value))),
  ),
  _ => value.hashCode,
};

/// Returns a deep copy of a JSON value: lists and maps are copied, and
/// everything else is shared.
Object? copyJson(Object? value) => switch (value) {
  final List<Object?> list => [for (final v in list) copyJson(v)],
  final Map<String, Object?> map => <String, Object?>{
    for (final e in map.entries) e.key: copyJson(e.value),
  },
  final Map<Object?, Object?> map => <Object?, Object?>{
    for (final e in map.entries) e.key: copyJson(e.value),
  },
  _ => value,
};
