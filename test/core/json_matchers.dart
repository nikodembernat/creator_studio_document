// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:test/test.dart';

/// Matches a JSON value that is [sameJson] with [expected] and also lists
/// every object's keys in the same order, as upstream writes them.
Matcher sameJsonInOrder(Object? expected) => _SameJsonInOrder(expected);

final class _SameJsonInOrder(final Object? expected) extends Matcher {
  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) {
    final problem = _difference(item, expected, r'$');
    if (problem != null) {
      matchState['problem'] = problem;
    }
    return problem == null;
  }

  @override
  Description describe(Description description) =>
      description.add('the same JSON, with keys in the same order');

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) => mismatchDescription.add('${matchState['problem']}');
}

String _short(Object? v) {
  final text = jsonEncode(v);
  return text.length > 300 ? '${text.substring(0, 300)}…' : text;
}

String? _difference(Object? actual, Object? expected, String path) {
  if (actual is Map<Object?, Object?> && expected is Map<Object?, Object?>) {
    final a = actual.keys.toList();
    final e = expected.keys.toList();
    if (a.length != e.length || !a.every(e.contains)) {
      return '$path: keys ${_short(a)} != ${_short(e)}';
    }
    for (final key in e) {
      final d = _difference(actual[key], expected[key], '$path.$key');
      if (d != null) {
        return d;
      }
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != e[i]) {
        return '$path: key order ${_short(a)} != ${_short(e)}';
      }
    }
    return null;
  }
  if (actual is List<Object?> && expected is List<Object?>) {
    if (actual.length != expected.length) {
      return '$path: length ${actual.length} != ${expected.length}';
    }
    for (var i = 0; i < actual.length; i++) {
      final d = _difference(actual[i], expected[i], '$path[$i]');
      if (d != null) {
        return d;
      }
    }
    return null;
  }
  return sameJson(actual, expected)
      ? null
      : '$path: ${_short(actual)} != ${_short(expected)}';
}
