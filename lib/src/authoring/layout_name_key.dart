// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// Unicode Normalization Form KD and full case folding, as Python's
/// `unicodedata.normalize("NFKD", s)` and `str.casefold` compute them.
///
/// The tables in `layout_name_key.g.dart` and `resources_nfc.g.dart` come from
/// the Python that ran `tool/extract_schema.py`, which checks that this
/// algorithm reproduces Python's for every code point.
library;

import 'dart:collection';

import 'package:creator_studio_document/src/authoring/layout_name_key.g.dart';
import 'package:creator_studio_document/src/core/resources_nfc.dart';
import 'package:creator_studio_document/src/core/resources_nfc.g.dart';
import 'package:meta/meta.dart';

/// Returns the NFKD form of [s].
///
/// A lone surrogate is kept as it is, as Python keeps one.
@internal
String nfkd(String s) {
  // No code point below U+00A0 decomposes.
  var simple = true;
  for (var i = 0; i < s.length; i++) {
    if (s.codeUnitAt(i) >= 0xa0) {
      simple = false;
      break;
    }
  }
  if (simple) {
    return s;
  }
  final out = <int>[];
  for (final cp in s.runes) {
    _decompose(cp, out);
  }
  _reorder(out);
  return String.fromCharCodes(out);
}

/// Returns [s] with every code point replaced by its full case folding, as
/// Python's `str.casefold` does.
@internal
String casefold(String s) {
  final out = <int>[];
  for (final cp in s.runes) {
    final folded = _tables.foldings[cp];
    if (folded == null) {
      out.add(cp);
    } else {
      out.addAll(folded);
    }
  }
  return String.fromCharCodes(out);
}

/// Returns the NFKC form of [s].
///
/// NFKC is NFKD followed by canonical composition, and NFC of an NFKD string
/// only composes it.
@internal
String nfkc(String s) => nfc(nfkd(s));

const _sBase = 0xac00;
const _lBase = 0x1100;
const _vBase = 0x1161;
const _tBase = 0x11a7;
const _vCount = 21;
const _tCount = 28;
const _nCount = _vCount * _tCount;
const _sCount = 19 * _nCount;

void _decompose(int cp, List<int> out) {
  final s = cp - _sBase;
  if (s >= 0 && s < _sCount) {
    out
      ..add(_lBase + s ~/ _nCount)
      ..add(_vBase + (s % _nCount) ~/ _tCount);
    if (s % _tCount != 0) {
      out.add(_tBase + s % _tCount);
    }
    return;
  }
  final parts = _tables.decompositions[cp];
  if (parts == null) {
    out.add(cp);
    return;
  }
  for (final p in parts) {
    _decompose(p, out);
  }
}

// The canonical ordering algorithm: a stable sort of every run of
// nonstarters by combining class.
void _reorder(List<int> cps) {
  for (var i = 1; i < cps.length; i++) {
    final cc = combiningClass(cps[i]);
    if (cc == 0) {
      continue;
    }
    var j = i;
    while (j > 0) {
      final prev = combiningClass(cps[j - 1]);
      if (prev == 0 || prev <= cc) {
        break;
      }
      final t = cps[j];
      cps[j] = cps[j - 1];
      cps[j - 1] = t;
      j--;
    }
  }
}

final class _Tables() {
  // The canonical and the compatibility decompositions, one level deep. No
  // code point has both.
  final Map<int, List<int>> decompositions = HashMap();

  final Map<int, List<int>> foldings = HashMap();
}

final _Tables _tables = () {
  final tables = _Tables();
  void parse(String table, Map<int, List<int>> into) {
    for (final token in table.split(' ')) {
      final [key, value] = token.split(':');
      into[int.parse(key, radix: 16)] = [
        for (final p in value.split('.')) int.parse(p, radix: 16),
      ];
    }
  }

  parse(canonicalDecompositions, tables.decompositions);
  parse(compatibilityDecompositions, tables.decompositions);
  parse(caseFoldings, tables.foldings);
  return tables;
}();
