// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// Python's `repr` and string ordering, for the messages and warnings that
/// quote values the way upstream does.
library;

import 'dart:typed_data';

import 'package:creator_studio_document/src/core/py_repr.g.dart';

/// Returns Python's `repr` of a JSON-like [value].
///
/// A string is quoted and escaped as Python quotes it, a double prints in
/// Python's shortest form, and lists and maps recurse.
String pyRepr(Object? value) => switch (value) {
  null => 'None',
  true => 'True',
  false => 'False',
  final String s => pyStringRepr(s),
  final int n => '$n',
  final BigInt n => '$n',
  final double d => pyFloatRepr(d),
  final List<Object?> l => '[${l.map(pyRepr).join(', ')}]',
  final Map<Object?, Object?> m =>
    '{${m.entries.map((e) => '${pyRepr(e.key)}: ${pyRepr(e.value)}').join(', ')}}',
  _ => '$value',
};

/// Returns Python's `repr` of the string [s].
///
/// It's quoted with single quotes unless it holds a single quote and no
/// double quote. A backslash, the quote, `\t`, `\n`, `\r`, and every code
/// point that Python doesn't consider printable are escaped. A lone surrogate
/// is escaped too.
String pyStringRepr(String s) {
  final quote = s.contains("'") && !s.contains('"') ? '"' : "'";
  final out = StringBuffer(quote);
  for (final cp in s.runes) {
    switch (cp) {
      case 0x5c:
        out.write(r'\\');
      case 0x09:
        out.write(r'\t');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case _ when cp == quote.codeUnitAt(0):
        out.write('\\$quote');
      case _ when cp < 0x20 || cp == 0x7f:
        out.write('\\x${_hex(cp, 2)}');
      case _ when cp < 0x7f || _isPrintable(cp):
        out.writeCharCode(cp);
      case _ when cp <= 0xff:
        out.write('\\x${_hex(cp, 2)}');
      case _ when cp <= 0xffff:
        out.write('\\u${_hex(cp, 4)}');
      default:
        out.write('\\U${_hex(cp, 8)}');
    }
  }
  return (out..write(quote)).toString();
}

/// Returns Python's `repr` of the double [d]: the shortest digits that read
/// back as [d], in fixed notation when the decimal point falls within 16
/// digits and in exponent notation otherwise.
String pyFloatRepr(double d) {
  if (d.isNaN) {
    return 'nan';
  }
  if (d.isInfinite) {
    return d > 0 ? 'inf' : '-inf';
  }
  if (d == 0) {
    return d.isNegative ? '-0.0' : '0.0';
  }
  final sign = d < 0 ? '-' : '';
  // With no argument, `toStringAsExponential` gives the shortest digits.
  final [mantissa, exponent] = d.abs().toStringAsExponential().split('e');
  final digits = mantissa.replaceFirst('.', '');
  final exp = int.parse(exponent);
  // Python's decimal point position: the value is 0.<digits> * 10^point.
  final point = exp + 1;
  if (point > -4 && point <= 16) {
    if (point <= 0) {
      return '${sign}0.${'0' * -point}$digits';
    }
    if (point >= digits.length) {
      return '$sign$digits${'0' * (point - digits.length)}.0';
    }
    return '$sign${digits.substring(0, point)}.${digits.substring(point)}';
  }
  final fraction = digits.length > 1 ? '.${digits.substring(1)}' : '';
  final expSign = exp < 0 ? '-' : '+';
  return '$sign${digits[0]}${fraction}e$expSign'
      '${exp.abs().toString().padLeft(2, '0')}';
}

/// Returns the name of the Python type that the JSON-like [value] decodes
/// to, as Python's `TypeError` messages name it.
String pyTypeName(Object? value) => switch (value) {
  null => 'NoneType',
  bool() => 'bool',
  int() || BigInt() => 'int',
  double() => 'float',
  String() => 'str',
  List<Object?>() => 'list',
  Map<Object?, Object?>() => 'dict',
  _ => '${value.runtimeType}',
};

/// Compares [a] and [b] by code point, as Python orders strings.
///
/// Dart's [String.compareTo] compares UTF-16 code units, which puts a
/// character beyond U+FFFF before one in U+E000–U+FFFF.
int compareCodePoints(String a, String b) {
  final x = a.runes.iterator;
  final y = b.runes.iterator;
  while (true) {
    final hasX = x.moveNext();
    final hasY = y.moveNext();
    if (!hasX || !hasY) {
      return hasX ? 1 : (hasY ? -1 : 0);
    }
    if (x.current != y.current) {
      return x.current.compareTo(y.current);
    }
  }
}

/// Returns the first lone UTF-16 surrogate in [s] as `(index, code unit)`,
/// counting code points as Python does, or `null` if [s] has none.
///
/// Python holds such a string, but can't encode it as UTF-8.
(int, int)? loneSurrogate(String s) {
  var index = 0;
  for (final cp in s.runes) {
    if (cp >= 0xd800 && cp <= 0xdfff) {
      return (index, cp);
    }
    index++;
  }
  return null;
}

/// Returns the message of the `UnicodeEncodeError` that Python's strict
/// UTF-8 encoder raises for [s], or `null` if [s] holds no lone surrogate.
///
/// Like Python's, it names the first run of lone surrogates, counting code
/// points: one as `character '\ud800' in position 1`, and more as
/// `characters in position 1-2`.
String? pyUtf8EncodeError(String s) {
  var index = 0;
  int? start;
  var first = 0;
  for (final cp in s.runes) {
    final surrogate = cp >= 0xd800 && cp <= 0xdfff;
    if (start == null && surrogate) {
      start = index;
      first = cp;
    } else if (start != null && !surrogate) {
      break;
    }
    index++;
  }
  if (start == null) {
    return null;
  }
  final where = index - start == 1
      ? 'character ${pyStringRepr(String.fromCharCode(first))} in position '
            '$start'
      : 'characters in position $start-${index - 1}';
  return "'utf-8' codec can't encode $where: surrogates not allowed";
}

String _hex(int value, int width) =>
    value.toRadixString(16).padLeft(width, '0');

// The unprintable ranges, flattened to [first, last, first, last, ...].
final Uint32List _unprintable = () {
  final ranges = unprintableCodePoints.split(' ');
  final out = Uint32List(ranges.length * 2);
  for (var i = 0; i < ranges.length; i++) {
    final [first, ...rest] = ranges[i].split('-');
    out[2 * i] = int.parse(first, radix: 16);
    out[2 * i + 1] = int.parse(rest.isEmpty ? first : rest.single, radix: 16);
  }
  return out;
}();

bool _isPrintable(int cp) {
  final table = _unprintable;
  var lo = 0;
  var hi = table.length ~/ 2 - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (cp < table[2 * mid]) {
      hi = mid - 1;
    } else if (cp > table[2 * mid + 1]) {
      lo = mid + 1;
    } else {
      return false;
    }
  }
  return true;
}
