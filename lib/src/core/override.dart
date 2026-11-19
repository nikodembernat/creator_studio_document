// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:creator_studio_document/src/core/json.dart';
import 'package:meta/meta.dart';

/// A property value that tells an omitted property, a null, and a value
/// apart.
///
/// - [Override.notSet]: omitted from the JSON, so the property can inherit a
///   value.
/// - [Override.cleared]: an explicit null, which blocks inheritance and clears
///   the value.
/// - [Override.value]: the value.
///
/// A field uses [Override] because `T?` can't tell an omitted property from a
/// null one. The JSON keeps the two apart.
///
/// The three states are the subclasses [OverrideNotSet], [OverrideCleared],
/// and [OverrideValue], so a `switch` over an override is exhaustive.
@immutable
sealed class const Override<T>._() {
  /// Returns an override for an omitted property, which leaves the property
  /// free to inherit a value.
  const factory notSet() = OverrideNotSet<T>;

  /// Returns an override for an explicit null, which blocks inheritance and
  /// clears the value.
  const factory cleared() = OverrideCleared<T>;

  /// Returns an override that holds [value].
  const factory value(T value) = OverrideValue<T>;

  /// Whether the property is omitted.
  bool get isNotSet => this is OverrideNotSet<T>;

  /// Whether the property is an explicit null.
  bool get isCleared => this is OverrideCleared<T>;

  /// Whether the property has a value.
  bool get isValue => this is OverrideValue<T>;

  /// Returns the property's value, or `null` if the property is omitted or
  /// cleared.
  T? get();
}

/// An [Override] for an omitted property.
final class const OverrideNotSet<T>() extends Override<T> {
  /// Creates the override.
  this : super._();

  @override
  T? get() => null;

  @override
  bool operator ==(Object other) => other is OverrideNotSet;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'Override.notSet()';
}

/// An [Override] for an explicit null.
final class const OverrideCleared<T>() extends Override<T> {
  /// Creates the override.
  this : super._();

  @override
  T? get() => null;

  @override
  bool operator ==(Object other) => other is OverrideCleared;

  @override
  int get hashCode => 2;

  @override
  String toString() => 'Override.cleared()';
}

/// An [Override] that holds a value.
final class const OverrideValue<T>(
  /// The property's value.
  final T value,
) extends Override<T> {
  /// Creates the override for [value].
  this : super._();

  @override
  T get() => value;

  /// Returns an override of the same type that holds [value].
  @internal
  OverrideValue<T> withValue(Object? value) => OverrideValue<T>(value as T);

  @override
  bool operator ==(Object other) =>
      other is OverrideValue && pyEquals(value, other.value);

  @override
  int get hashCode => Object.hash(3, pyHash(value));

  @override
  String toString() => 'Override.value($value)';
}
