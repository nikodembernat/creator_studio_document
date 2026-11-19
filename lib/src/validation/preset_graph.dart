// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'dart:collection';

import 'package:creator_studio_document/src/core/json.dart';
import 'package:creator_studio_document/src/core/preset.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/validation/errors.dart';

/// Checks that every preset has a unique, nonempty identifier, that every
/// `parent_identifier` names a preset, and that no preset reaches itself
/// through parents or through a `preset_identifier` nested in its
/// properties.
///
/// It reads each preset's entry as [Preset.toJson] holds it, as upstream
/// reads a `Preset`'s attributes, so an identifier that isn't a string, from
/// a `Preset.fromJson` entry, is checked as upstream checks it.
///
/// Throws [DocumentValueError] for an empty or duplicate identifier or a
/// cycle, and [DocumentReferenceError] for a parent that matches no preset.
/// Throws [ArgumentError] where upstream raises `TypeError` or
/// `AttributeError`: for an identifier or `parent_identifier` that's a
/// nonempty list or object, `properties` that aren't an object, duplicate or
/// parent-adopting identifiers that mix strings and numbers, or a cycle
/// through an identifier that isn't a string.
void validatePresetGraph(List<Preset> presets) =>
    _detectCycle(_buildPresetEdges(presets));

// Python's truthiness of a JSON value.
bool _truthy(Object? value) => switch (value) {
  null || false => false,
  final num n => n != 0,
  final BigInt n => n != BigInt.zero,
  final String s => s.isNotEmpty,
  final List<Object?> l => l.isNotEmpty,
  final Map<Object?, Object?> m => m.isNotEmpty,
  _ => true,
};

// The key that [value] hashes as in a Python dict or set, where `True`,
// `1`, and `1.0` are one key. Throws [ArgumentError] for a list or an
// object, which Python can't hash.
Object _pyKey(Object value) => switch (value) {
  List<Object?>() || Map<Object?, Object?>() => throw ArgumentError(
    "unhashable type: '${pyTypeName(value)}'",
  ),
  true => 1,
  false => 0,
  final double d when d.isFinite && d == d.truncateToDouble() => _intKey(
    BigInt.from(d),
  ),
  final BigInt n => _intKey(n),
  _ => value,
};

// An integer key: an [int] where one holds it, so that it matches the same
// integer spelled as an [int].
Object _intKey(BigInt n) => n.isValidInt ? n.toInt() : n;

// Python's `sorted` of identifiers, which are strings, numbers, or
// booleans; comparing a string with a number raises `TypeError`. Upstream
// sorts a set, whose order Python's string hashing varies, so which pair
// the message names can differ between its runs.
List<Object> _pySorted(Iterable<Object> values) {
  final list = values.toList();
  for (var j = 1; j < list.length; j++) {
    for (var i = 0; i < j; i++) {
      if ((list[i] is String) != (list[j] is String)) {
        throw ArgumentError(
          "'<' not supported between instances of "
          "'${pyTypeName(list[j])}' and '${pyTypeName(list[i])}'",
        );
      }
    }
  }
  Object asNum(Object v) => v is bool ? (v ? 1 : 0) : v;
  return list..sort(
    (a, b) => a is String
        ? compareCodePoints(a, b as String)
        : pyNumCompare(asNum(a), asNum(b)),
  );
}

// The preset graph, keyed by `_pyKey`, with the identifier each key was
// first spelled as.
typedef _Edges = ({Map<Object, Set<Object>> edges, Map<Object, Object> names});

_Edges _buildPresetEdges(List<Preset> presets) {
  final edges = <Object, Set<Object>>{};
  final names = <Object, Object>{};
  final parents = <Object, Object>{};
  final dupes = <Object, Object>{};
  for (var i = 0; i < presets.length; i++) {
    final json = presets[i].toJson();
    final identifier = json['identifier'];
    if (identifier == null || !_truthy(identifier)) {
      throw DocumentValueError(
        '`Preset.identifier` is empty (at presets[$i]). Every `Preset` needs '
        'a nonempty `identifier`.',
      );
    }
    final key = _pyKey(identifier);
    if (edges.containsKey(key)) {
      dupes.putIfAbsent(key, () => identifier);
      continue;
    }
    // Upstream's set of neighbors iterates in hash order. Insertion order
    // here, parent first, makes the cycle reported deterministic.
    final neighbors = <Object>{};
    final parent = json['parent_identifier'];
    if (parent != null && _truthy(parent)) {
      neighbors.add(_pyKey(parent));
      parents[key] = parent;
    }
    final properties = json['properties'];
    if (properties is! Map<Object?, Object?>) {
      throw ArgumentError(
        "'${pyTypeName(properties)}' object has no attribute 'values'",
      );
    }
    neighbors.addAll(_collectNestedPresetRefs(properties));
    edges[key] = neighbors;
    names[key] = identifier;
  }
  if (dupes.isNotEmpty) {
    throw DocumentValueError(
      '`Preset.identifier` values ${pyRepr(_pySorted(dupes.values))} are '
      'duplicates (at presets). Each `Preset.identifier` must be unique.',
    );
  }
  // Sorting the (child, parent) pairs compares the children, which are
  // unique keys.
  final children = _pySorted(parents.keys.map((k) => names[k]!));
  for (final child in children) {
    final parent = parents[_pyKey(child)]!;
    if (!edges.containsKey(_pyKey(parent))) {
      throw DocumentReferenceError(
        '`Preset.parent_identifier` ${pyRepr(parent)} matches no preset (at '
        'preset ${pyRepr(child)})',
      );
    }
  }
  return (edges: edges, names: names);
}

final class _NodeInfo() {
  final List<Object> successors = [];
}

// `graphlib.TopologicalSorter.prepare`, which reports the first cycle its
// depth-first search meets.
void _detectCycle(_Edges graph) {
  final (:edges, :names) = graph;
  final n2i = <Object, _NodeInfo>{};
  for (final MapEntry(key: node, value: neighbors) in edges.entries) {
    n2i.putIfAbsent(node, _NodeInfo.new);
    for (final pred in neighbors) {
      if (edges.containsKey(pred)) {
        n2i.putIfAbsent(pred, _NodeInfo.new).successors.add(node);
      }
    }
  }
  if (_findCycle(n2i) case final cycle?) {
    // Upstream joins the identifiers, which must be strings.
    final spelled = [for (final node in cycle.reversed) names[node]!];
    for (var i = 0; i < spelled.length; i++) {
      if (spelled[i] is! String) {
        throw ArgumentError(
          'sequence item $i: expected str instance, '
          '${pyTypeName(spelled[i])} found',
        );
      }
    }
    throw DocumentValueError(
      'Presets form a cycle: ${spelled.join(' -> ')} (at presets)',
    );
  }
}

List<Object>? _findCycle(Map<Object, _NodeInfo> n2i) {
  final stack = <Object>[];
  final itstack = <Iterator<Object>>[];
  final seen = <Object>{};
  final node2stacki = <Object, int>{};
  for (final start in n2i.keys) {
    if (seen.contains(start)) {
      continue;
    }
    var node = start;
    while (true) {
      if (seen.contains(node)) {
        if (node2stacki[node] case final i?) {
          return [...stack.sublist(i), node];
        }
      } else {
        seen.add(node);
        itstack.add(n2i[node]!.successors.iterator);
        node2stacki[node] = stack.length;
        stack.add(node);
      }
      var advanced = false;
      while (stack.isNotEmpty) {
        if (itstack.last.moveNext()) {
          node = itstack.last.current;
          advanced = true;
          break;
        }
        node2stacki.remove(stack.removeLast());
        itstack.removeLast();
      }
      if (!advanced) {
        break;
      }
    }
  }
  return null;
}

Iterable<String> _collectNestedPresetRefs(Map<Object?, Object?> properties) {
  final seen = HashSet<Object>.identity()..add(properties);
  return [for (final v in properties.values) ..._walkForRefs(v, seen)];
}

Iterable<String> _walkForRefs(Object? value, Set<Object> seen) sync* {
  switch (value) {
    case final Map<Object?, Object?> map:
      if (!seen.add(map)) {
        return;
      }
      if (map['preset_identifier'] case final String ref when ref.isNotEmpty) {
        yield ref;
      }
      for (final v in map.values) {
        yield* _walkForRefs(v, seen);
      }
    case final List<Object?> list:
      if (!seen.add(list)) {
        return;
      }
      for (final v in list) {
        yield* _walkForRefs(v, seen);
      }
  }
}
