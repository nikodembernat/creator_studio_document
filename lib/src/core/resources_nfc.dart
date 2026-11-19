// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// Unicode Normalization Form C, as Python's
/// `unicodedata.normalize("NFC", s)` computes it.
///
/// The tables in `resources_nfc.g.dart` come from the Python that ran
/// `tool/extract_schema.py`, so the result matches upstream's for every
/// string.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:creator_studio_document/src/core/resources_nfc.g.dart';
import 'package:meta/meta.dart';

/// Returns the NFC form of [s].
///
/// A lone surrogate is kept as it is, as Python keeps one.
@internal
String nfc(String s) {
  // Every code point below U+0300 is a starter that NFC leaves alone.
  var simple = true;
  for (var i = 0; i < s.length; i++) {
    if (s.codeUnitAt(i) >= 0x300) {
      simple = false;
      break;
    }
  }
  if (simple) {
    return s;
  }
  final decomposed = <int>[];
  for (final cp in s.runes) {
    _decompose(cp, decomposed);
  }
  _reorder(decomposed);
  return String.fromCharCodes(_compose(decomposed));
}

const _sBase = 0xac00;
const _lBase = 0x1100;
const _vBase = 0x1161;
const _tBase = 0x11a7;
const _lCount = 19;
const _vCount = 21;
const _tCount = 28;
const _nCount = _vCount * _tCount;
const _sCount = _lCount * _nCount;

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

List<int> _compose(List<int> cps) {
  final out = <int>[];
  var starter = -1;
  var lastClass = 0;
  for (final cp in cps) {
    final cc = combiningClass(cp);
    if (starter >= 0 && (out.length - 1 == starter || lastClass < cc)) {
      final composite = _composePair(out[starter], cp);
      if (composite != null) {
        out[starter] = composite;
        continue;
      }
    }
    if (cc == 0) {
      starter = out.length;
    }
    lastClass = cc;
    out.add(cp);
  }
  return out;
}

int? _composePair(int a, int b) {
  final l = a - _lBase;
  if (l >= 0 && l < _lCount) {
    final v = b - _vBase;
    if (v >= 0 && v < _vCount) {
      return _sBase + (l * _vCount + v) * _tCount;
    }
    return null;
  }
  final s = a - _sBase;
  if (s >= 0 && s < _sCount && s % _tCount == 0) {
    final t = b - _tBase;
    if (t > 0 && t < _tCount) {
      return a + t;
    }
    return null;
  }
  return _tables.compositions[(a << 21) | b];
}

/// Returns the canonical combining class of the code point [cp].
@internal
int combiningClass(int cp) {
  final ranges = _combining;
  var lo = 0;
  var hi = ranges.length ~/ 3 - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (cp < ranges[3 * mid]) {
      hi = mid - 1;
    } else if (cp > ranges[3 * mid + 1]) {
      lo = mid + 1;
    } else {
      return ranges[3 * mid + 2];
    }
  }
  return 0;
}

// [first, last, class, ...] in order.
final Uint32List _combining = () {
  final tokens = canonicalCombiningClasses.split(' ');
  final out = Uint32List(tokens.length * 3);
  for (var i = 0; i < tokens.length; i++) {
    final [range, cc] = tokens[i].split(':');
    final [first, ...rest] = range.split('-');
    out[3 * i] = int.parse(first, radix: 16);
    out[3 * i + 1] = int.parse(rest.isEmpty ? first : rest.single, radix: 16);
    out[3 * i + 2] = int.parse(cc, radix: 16);
  }
  return out;
}();

final class _Tables() {
  final Map<int, List<int>> decompositions = HashMap();

  // `first << 21 | second` to the primary composite.
  final Map<int, int> compositions = HashMap();
}

final _Tables _tables = () {
  final tables = _Tables();
  final excluded = {
    for (final t in compositionExclusions.split(' ')) int.parse(t, radix: 16),
  };
  for (final token in canonicalDecompositions.split(' ')) {
    final [key, value] = token.split(':');
    final cp = int.parse(key, radix: 16);
    final parts = [for (final p in value.split('.')) int.parse(p, radix: 16)];
    tables.decompositions[cp] = parts;
    // A singleton or a decomposition with a nonstarter never composes.
    if (parts.length == 2 &&
        !excluded.contains(cp) &&
        combiningClass(cp) == 0 &&
        combiningClass(parts[0]) == 0) {
      tables.compositions[(parts[0] << 21) | parts[1]] = cp;
    }
  }
  return tables;
}();
