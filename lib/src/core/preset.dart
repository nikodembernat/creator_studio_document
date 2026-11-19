// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'dart:collection';

import 'package:creator_studio_document/src/core/errors.dart';
import 'package:creator_studio_document/src/core/json.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:meta/meta.dart';

/// A preset, as one entry in the presets file stores it.
///
/// [PresetRegistry] resolves inheritance along [parentIdentifier].
class Preset {
  /// Creates a preset.
  ///
  /// [identifier] is the name that an adopting object's `preset_identifier`
  /// refers to, and [properties] are the properties that adopting objects
  /// inherit, as raw JSON.
  new(
    String this._identifier,
    Map<String, Object?> this._properties, {
    String? this._displayName,
    String? this._parentIdentifier,
  });

  new _raw(
    this._identifier,
    this._properties,
    this._displayName,
    this._parentIdentifier,
  );

  /// Creates a preset from a decoded entry of the presets file.
  ///
  /// Like upstream's `Preset.from_dict`, it checks no types: every value is
  /// kept as the entry holds it, so [toJson] writes it back unchanged. A
  /// `properties` value that isn't an object fails only when a resolution
  /// reaches the preset, and an `identifier` that isn't a string names no
  /// preset that an object can adopt.
  ///
  /// Throws [ArgumentError] if [data] has no `identifier` key or no
  /// `properties` key.
  factory fromJson(Map<String, Object?> data) {
    if (!data.containsKey('identifier')) {
      throw ArgumentError.value(data, 'data', 'no `identifier`');
    }
    if (!data.containsKey('properties')) {
      throw ArgumentError.value(data, 'data', 'no `properties`');
    }
    return Preset._raw(
      data['identifier'],
      switch (data['properties']) {
        final Map<String, Object?> m => m,
        final Map<Object?, Object?> m when m.keys.every((k) => k is String) =>
          m.cast<String, Object?>(),
        final other => other,
      },
      data['display_name'],
      data['parent_identifier'],
    );
  }

  // As the entry held them: a value of an unexpected type is kept for
  // `toJson` and, for the identifiers, still looked up.
  Object? _identifier;
  Object? _properties;
  Object? _displayName;
  Object? _parentIdentifier;

  /// The name that an adopting object's `preset_identifier` refers to, or
  /// `null` if the entry holds one that isn't a string.
  String? get identifier => switch (_identifier) {
    final String s => s,
    _ => null,
  };

  set identifier(String? value) => _identifier = value;

  /// The properties that adopting objects inherit, as raw JSON, or `null` if
  /// the entry holds a value that isn't an object.
  ///
  /// Resolving a preset whose properties aren't an object throws
  /// [ArgumentError], as upstream raises `TypeError`.
  Map<String, Object?>? get properties => switch (_properties) {
    final Map<String, Object?> m => m,
    _ => null,
  };

  set properties(Map<String, Object?>? value) => _properties = value;

  /// The name that Keynote shows, or `null` if the entry holds none or holds
  /// one that isn't a string.
  String? get displayName => switch (_displayName) {
    final String s => s,
    _ => null,
  };

  set displayName(String? value) => _displayName = value;

  /// The identifier of the preset this one inherits from, or `null` if the
  /// entry holds none or holds one that isn't a string.
  ///
  /// A parent identifier that isn't a string names no preset unless an entry
  /// holds the same non-string identifier, so resolving usually adds a
  /// warning for it.
  String? get parentIdentifier => switch (_parentIdentifier) {
    final String s => s,
    _ => null,
  };

  set parentIdentifier(String? value) => _parentIdentifier = value;

  /// Returns the preset in the form that the presets file stores, without any
  /// optional key that holds `null`.
  Map<String, Object?> toJson() => {
    'identifier': _identifier,
    if (_displayName != null) 'display_name': _displayName,
    if (_parentIdentifier != null) 'parent_identifier': _parentIdentifier,
    'properties': _properties,
  };

  @override
  String toString() => 'Preset($_identifier)';
}

/// A resolver of preset inheritance for decoding and encoding.
///
/// The registry walks the `parent_identifier` chain and merges each child's
/// properties over its parent's. A cycle throws [PresetCycleError]. A missing
/// preset or parent adds an entry to [warnings] and contributes no
/// properties. A model takes the registry through `WireContext(presets: …)`.
///
/// ```dart
/// final registry = PresetRegistry([
///   Preset('base', {'text_wrap': true, 'vertical_alignment': 'top'}),
///   Preset('wrapped', {'vertical_alignment': 'middle'},
///       parentIdentifier: 'base'),
/// ]);
/// registry.resolvedProperties('wrapped');
/// // {text_wrap: true, vertical_alignment: middle}
/// ```
///
/// When the JSON omits a field, decoding takes its value from the preset.
/// Encoding with the same registry leaves out a value that still matches the
/// preset, so the value stays linked to it. A value that differs is written.
class PresetRegistry(Iterable<Preset> presets) {
  /// Creates a registry. A later preset replaces an earlier one with the same
  /// identifier.
  this;

  // Keyed as a Python dict is: `1`, `1.0`, and `true` are the same key.
  final Map<Object?, Preset> _byId = _index(presets);
  final Map<String, Map<String, Object?>> _cache = {};
  Object? _cycle;

  /// A note for each preset or parent that a resolution looked for and
  /// didn't find.
  final List<String> warnings = [];

  /// Validated preset values, shared by every model that the registry
  /// decodes or encodes.
  @internal
  final Map<Object, Object?> gateMemo = {};

  /// The identifier at which a resolution found a cycle, if any did.
  ///
  /// It's a [String] unless the cycle runs through an entry whose identifier
  /// isn't one.
  Object? get cycle => _cycle;

  static Map<Object?, Preset> _index(Iterable<Preset> presets) {
    final byId = HashMap<Object?, Preset>(equals: pyEquals, hashCode: pyHash);
    for (final p in presets) {
      _checkHashable(p._identifier);
      byId[p._identifier] = p;
    }
    return byId;
  }

  /// Returns the properties of the preset [identifier], merged over its
  /// ancestors' properties, or an empty map when the preset is missing.
  ///
  /// Every call for an identifier returns the same unmodifiable map. Throws
  /// [PresetCycleError] if the `parent_identifier` chain has a cycle, and
  /// [ArgumentError] if a preset in the chain holds `properties` that aren't
  /// an object.
  Map<String, Object?> resolvedProperties(String identifier) {
    final cached = _cache[identifier];
    if (cached != null) {
      return cached;
    }
    final resolved = UnmodifiableMapView(
      _resolve(identifier, HashSet(equals: pyEquals, hashCode: pyHash)),
    );
    _cache[identifier] = resolved;
    return resolved;
  }

  Map<String, Object?> _resolve(Object identifier, Set<Object?> visited) {
    _checkHashable(identifier);
    if (visited.contains(identifier)) {
      _cycle = identifier;
      throw PresetCycleError(identifier);
    }
    final preset = _byId[identifier];
    if (preset == null) {
      warnings.add('missing preset ${pyRepr(identifier)}');
      return {};
    }
    var parent = <String, Object?>{};
    if (preset._parentIdentifier case final Object parentId) {
      parent = _resolve(
        parentId,
        HashSet(equals: pyEquals, hashCode: pyHash)
          ..addAll(visited)
          ..add(identifier),
      );
    }
    return switch (preset._properties) {
      final Map<String, Object?> props => {...parent, ...props},
      final other => throw ArgumentError(
        "'${pyTypeName(other)}' object is not a mapping",
        'properties',
      ),
    };
  }
}

// Upstream keys a dict and a set by identifier, which raises `TypeError` for
// a list or an object.
void _checkHashable(Object? identifier) {
  if (identifier is List<Object?> || identifier is Map<Object?, Object?>) {
    throw ArgumentError(
      "unhashable type: '${identifier is List ? 'list' : 'dict'}'",
      'identifier',
    );
  }
}
