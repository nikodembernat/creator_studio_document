// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// Iterates depth-first over a tree of models.
///
/// A child model can sit in a plain field, a list, a map, an [Override]
/// wrapper, or a [TaggedUnionModel] union case, so walking the tree by hand
/// takes care.
library;

import 'dart:collection';

import 'package:creator_studio_document/src/core/override.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/core/wire.dart';

/// One model the iteration yields, with lazy access to its position in the
/// tree.
///
/// Each read of [ancestors], [indexPath], or [path] costs O(depth). Caching
/// the value can speed up a hot loop.
///
/// An [IteratedModel] compares and hashes by identity, so it can go in a set.
/// A model yielded twice gives two [IteratedModel] instances, and they compare
/// unequal.
///
/// You don't create an [IteratedModel] directly. [iterateModels] yields them.
final class IteratedModel._(
  /// The model at this position in the tree.
  final WireModel model, {

  /// The position of the enclosing model, or `null` for the root.
  final IteratedModel? parent,

  /// The index of [model] in the list that holds it, or `null` if no list
  /// holds it.
  final int? listIndex,

  /// The wire key of the field or union case of [parent] that holds [model],
  /// or `null` for the root.
  final String? fieldName,

  /// The key of [model] in the map that holds it, or `null` if no map holds
  /// it.
  final Object? dictKey,
}) {
  /// The enclosing models, outermost first. It's empty for the root.
  List<WireModel> get ancestors {
    final out = <WireModel>[];
    for (var cur = parent; cur != null; cur = cur.parent) {
      out.add(cur.model);
    }
    return List.unmodifiable(out.reversed);
  }

  /// The list indices along the path from the root, without field names.
  ///
  /// For example, iterating a slide gives `[2, 3]` for
  /// `contents[2].object.group.children[3]`, and `[]` for the root. Read
  /// [ancestors] or [path] when field names matter.
  List<int> get indexPath {
    final out = <int>[];
    for (IteratedModel? cur = this; cur != null; cur = cur.parent) {
      if (cur.listIndex case final index?) {
        out.add(index);
      }
    }
    return List.unmodifiable(out.reversed);
  }

  /// The dotted path from the root. It's `''` for the root.
  ///
  /// For example, iterating a slide gives `contents[0].object.shape.text`. A
  /// map key is written as Python's `repr` writes it, so `field['a']` and
  /// `field[3]` stay distinct.
  String get path {
    final segments = <String>[];
    for (IteratedModel? cur = this; cur != null; cur = cur.parent) {
      final name = cur.fieldName;
      if (name == null) {
        break;
      }
      if (cur.listIndex case final index?) {
        segments.add('$name[$index]');
      } else if (cur.dictKey case final key?) {
        segments.add('$name[${pyRepr(key)}]');
      } else {
        segments.add(name);
      }
    }
    return segments.reversed.join('.');
  }

  @override
  String toString() => 'IteratedModel(model: $model)';
}

/// Yields [root], then every model reachable from it, in depth-first
/// pre-order.
///
/// The iteration descends the fields of an [ObjectModel] and the cases of a
/// [TaggedUnionModel], in declaration order, into a model, a list of models,
/// or a map with model values, including a model held in an [Override]. An
/// [Override] that is unset or cleared holds no model and is skipped. Unknown
/// keys kept in [WireModel.extras] hold JSON, not models, and aren't
/// descended.
///
/// Each [IteratedModel] comes before those of its descendants. A model under
/// two parents appears once for each. A model that holds itself, directly or
/// further down, is yielded once on that path, and the cycle is cut silently.
///
/// The iteration is lazy: it reads the tree as it goes, and each new iterator
/// starts over.
Iterable<IteratedModel> iterateModels(WireModel root) sync* {
  final onPath = HashSet<WireModel>.identity();
  yield* _iterate(IteratedModel._(root), onPath);
}

Iterable<IteratedModel> _iterate(
  IteratedModel here,
  Set<WireModel> onPath,
) sync* {
  final model = here.model;
  if (!onPath.add(model)) {
    return;
  }
  yield here;
  try {
    for (final name in _fieldNames(model.wireSchema)) {
      var value = model.wireGet(name);
      if (value is Override<Object?>) {
        if (!value.isValue) {
          continue;
        }
        value = value.get();
      }
      switch (value) {
        case final WireModel child:
          yield* _iterate(
            IteratedModel._(child, parent: here, fieldName: name),
            onPath,
          );
        case final List<Object?> items:
          for (var i = 0; i < items.length; i++) {
            if (items[i] case final WireModel child) {
              yield* _iterate(
                IteratedModel._(
                  child,
                  parent: here,
                  fieldName: name,
                  listIndex: i,
                ),
                onPath,
              );
            }
          }
        case final Map<Object?, Object?> entries:
          for (final MapEntry(:key, value: item) in entries.entries) {
            if (item case final WireModel child) {
              yield* _iterate(
                IteratedModel._(
                  child,
                  parent: here,
                  fieldName: name,
                  dictKey: key,
                ),
                onPath,
              );
            }
          }
      }
    }
  } finally {
    onPath.remove(model);
  }
}

Iterable<String> _fieldNames(ModelSchema<WireModel> schema) => switch (schema) {
  ObjectSchema(:final fields) => [for (final f in fields) f.key],
  UnionSchema(:final cases) => [for (final c in cases) c.key],
};
