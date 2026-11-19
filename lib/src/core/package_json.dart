// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// The JSON reading and writing of a package's parts, as upstream does it
/// with Python's `json` module.
///
/// `dart:convert` differs from Python's `json` in what it accepts and writes:
/// Python reads `NaN`, `Infinity`, and `-Infinity`, detects UTF-16 and UTF-32
/// input, keeps a lone surrogate that the bytes or an escape spell, and
/// rejects an integer of more than 4300 digits. Writing quotes only what JSON
/// requires and keeps every other character as it is, as
/// `json.dumps(value, separators=(",", ":"), ensure_ascii=False)` does, and
/// fails for a lone surrogate, which UTF-8 can't encode.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:meta/meta.dart';

/// A part that isn't valid JSON, as Python's `json.loads` rejects it.
///
/// It's the counterpart of Python's `JSONDecodeError` and of the
/// `UnicodeDecodeError` that undecodable bytes raise, both `ValueError`s.
@internal
final class PyJsonError(
  /// The text that [toString] returns, in Python's words.
  final String message,
) implements Exception {
  /// Creates an error.
  this;

  @override
  String toString() => message;
}

/// JSON nested deeper than [maxJsonDepth] containers, which Python's
/// `json.loads` rejects with a `RecursionError` rather than a `ValueError`.
@internal
final class PyJsonDepthError(super.message) extends PyJsonError {
  /// Creates an error.
  this;
}

/// The most arrays and objects that a JSON value nests, one inside another,
/// that the reader accepts.
///
/// Python's `json.loads` recurses for each, and with Python 3.13's default
/// limits reaches its `RecursionError` at one more, or a little earlier when
/// it's called from deep in the call stack.
@internal
const maxJsonDepth = 9998;

/// Decodes [bytes] as Python's `json.loads` does.
///
/// An integer literal that doesn't fit in an [int] decodes as the exact
/// [BigInt], as Python reads it, where `dart:convert` decodes a [double].
/// Throws [PyJsonError] for bytes that `json.loads` rejects, and
/// [PyJsonDepthError] for a value that nests more than [maxJsonDepth] arrays
/// and objects.
@internal
Object? pyJsonLoads(Uint8List bytes) =>
    _PyJsonParser(_decodeDocument(bytes)).parse();

/// Encodes [value] as compact UTF-8 JSON, as upstream's `_dumps` does.
///
/// Throws [StateError] for a string that holds a lone surrogate, as Python's
/// UTF-8 encoder does, and [ArgumentError] for a value that isn't JSON or for
/// a list or map that contains itself.
@internal
Uint8List pyJsonDumps(Object? value) {
  final out = StringBuffer();
  _dump(value, out);
  final text = out.toString();
  if (pyUtf8EncodeError(text) case final message?) {
    throw StateError(message);
  }
  return utf8.encode(text);
}

// ---------------------------------------------------------------------------
// Bytes to text
// ---------------------------------------------------------------------------

// `json.detect_encoding`, then `bytes.decode(encoding, 'surrogatepass')`.
String _decodeDocument(Uint8List b) {
  bool startsWith(List<int> prefix) {
    if (b.length < prefix.length) {
      return false;
    }
    for (var i = 0; i < prefix.length; i++) {
      if (b[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }

  if (startsWith(const [0x00, 0x00, 0xfe, 0xff])) {
    return _decodeUtf32(b, 4, bigEndian: true, name: 'utf-32');
  }
  if (startsWith(const [0xff, 0xfe, 0x00, 0x00])) {
    return _decodeUtf32(b, 4, bigEndian: false, name: 'utf-32');
  }
  if (startsWith(const [0xfe, 0xff])) {
    return _decodeUtf16(b, 2, bigEndian: true, name: 'utf-16');
  }
  if (startsWith(const [0xff, 0xfe])) {
    return _decodeUtf16(b, 2, bigEndian: false, name: 'utf-16');
  }
  if (startsWith(const [0xef, 0xbb, 0xbf])) {
    return pyUtf8Decode(b, start: 3, surrogatePass: true, name: 'utf-8-sig');
  }
  if (b.length >= 4) {
    if (b[0] == 0) {
      return b[1] != 0
          ? _decodeUtf16(b, 0, bigEndian: true, name: 'utf-16-be')
          : _decodeUtf32(b, 0, bigEndian: true, name: 'utf-32-be');
    }
    if (b[1] == 0) {
      return b[2] != 0 || b[3] != 0
          ? _decodeUtf16(b, 0, bigEndian: false, name: 'utf-16-le')
          : _decodeUtf32(b, 0, bigEndian: false, name: 'utf-32-le');
    }
  } else if (b.length == 2) {
    if (b[0] == 0) {
      return _decodeUtf16(b, 0, bigEndian: true, name: 'utf-16-be');
    }
    if (b[1] == 0) {
      return _decodeUtf16(b, 0, bigEndian: false, name: 'utf-16-le');
    }
  }
  return pyUtf8Decode(b, surrogatePass: true);
}

/// Decodes [bytes] from [start] as Python's strict UTF-8 codec does.
///
/// Unlike `dart:convert`, it keeps a leading byte order mark. With
/// [surrogatePass], an encoded surrogate decodes to a lone surrogate, as the
/// `surrogatepass` error handler does; without it, it's an error. Throws
/// [PyJsonError] with Python's `UnicodeDecodeError` message.
@internal
String pyUtf8Decode(
  Uint8List bytes, {
  int start = 0,
  bool surrogatePass = false,
  String name = 'utf-8',
}) {
  final out = StringBuffer();
  var i = start;
  Never fail(int at, int end, String reason) {
    final where = end - at > 1
        ? 'bytes in position ${at - start}-${end - 1 - start}'
        : 'byte 0x${bytes[at].toRadixString(16).padLeft(2, '0')} in '
              'position ${at - start}';
    throw PyJsonError("'$name' codec can't decode $where: $reason");
  }

  while (i < bytes.length) {
    final b0 = bytes[i];
    if (b0 < 0x80) {
      out.writeCharCode(b0);
      i++;
      continue;
    }
    final int length;
    final int lowest;
    if (b0 >= 0xc2 && b0 <= 0xdf) {
      length = 2;
      lowest = 0x80;
    } else if (b0 >= 0xe0 && b0 <= 0xef) {
      length = 3;
      lowest = 0x800;
    } else if (b0 >= 0xf0 && b0 <= 0xf4) {
      length = 4;
      lowest = 0x10000;
    } else {
      fail(i, i + 1, 'invalid start byte');
    }
    var cp = b0 & (0xff >> (length + 1));
    var j = 1;
    for (; j < length; j++) {
      if (i + j >= bytes.length) {
        fail(i, i + j, 'unexpected end of data');
      }
      final b = bytes[i + j];
      // The second byte's range excludes overlong forms, code points past
      // U+10FFFF, and, unless they pass, surrogates.
      var lo = 0x80;
      var hi = 0xbf;
      if (j == 1) {
        if (b0 == 0xe0) {
          lo = 0xa0;
        } else if (b0 == 0xed && !surrogatePass) {
          hi = 0x9f;
        } else if (b0 == 0xf0) {
          lo = 0x90;
        } else if (b0 == 0xf4) {
          hi = 0x8f;
        }
      }
      if (b < lo || b > hi) {
        fail(i, i + j, 'invalid continuation byte');
      }
      cp = (cp << 6) | (b & 0x3f);
    }
    assert(cp >= lowest, 'overlong forms are rejected above');
    out.writeCharCode(cp);
    i += length;
  }
  return out.toString();
}

String _decodeUtf16(
  Uint8List b,
  int start, {
  required bool bigEndian,
  required String name,
}) {
  final out = StringBuffer();
  var i = start;
  for (; i + 1 < b.length; i += 2) {
    final unit = bigEndian ? (b[i] << 8) | b[i + 1] : b[i] | (b[i + 1] << 8);
    // `surrogatepass` keeps a lone surrogate; a pair forms one character.
    out.writeCharCode(unit);
  }
  if (i < b.length) {
    throw PyJsonError(
      "'$name' codec can't decode byte 0x"
      "${b[i].toRadixString(16).padLeft(2, '0')} in position ${i - start}: "
      'truncated data',
    );
  }
  // `writeCharCode` of two surrogates in a row joins them in the string.
  return out.toString();
}

String _decodeUtf32(
  Uint8List b,
  int start, {
  required bool bigEndian,
  required String name,
}) {
  final out = StringBuffer();
  var i = start;
  for (; i + 3 < b.length; i += 4) {
    final cp = bigEndian
        ? (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]
        : b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);
    if (cp > 0x10ffff) {
      throw PyJsonError(
        "'$name' codec can't decode bytes in position ${i - start}-"
        '${i - start + 3}: code point not in range(0x110000)',
      );
    }
    out.writeCharCode(cp);
  }
  if (i < b.length) {
    throw PyJsonError(
      "'$name' codec can't decode bytes in position ${i - start}-"
      '${b.length - 1 - start}: truncated data',
    );
  }
  return out.toString();
}

// ---------------------------------------------------------------------------
// Text to values
// ---------------------------------------------------------------------------

// An array or object that the reader is inside: the list, or the map and
// the key whose value it reads.
final class _Open {
  new array(List<Object?> this.list) : map = null;

  new object(Map<String, Object?> this.map, String this.key) : list = null;

  final List<Object?>? list;
  final Map<String, Object?>? map;
  String? key;
}

// Python's limit on the digits of an integer that `int()` converts.
const _maxIntDigits = 4300;

final class _PyJsonParser(final String s) {
  int _pos = 0;

  Never _fail(String message, int pos) {
    final before = s.substring(0, pos);
    final lineno = '\n'.allMatches(before).length + 1;
    // Positions count code points, as a Python `str` does.
    final char = before.runes.length;
    final lastNewline = before.lastIndexOf('\n');
    final colno = lastNewline < 0
        ? char + 1
        : char - before.substring(0, lastNewline).runes.length;
    throw PyJsonError('$message: line $lineno column $colno (char $char)');
  }

  int _char(int pos) => pos < s.length ? s.codeUnitAt(pos) : -1;

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d;

  void _skipSpace() {
    while (_pos < s.length && _isSpace(s.codeUnitAt(_pos))) {
      _pos++;
    }
  }

  bool _startsWith(String word) => s.startsWith(word, _pos);

  Object? parse() {
    _skipSpace();
    final value = _value();
    _skipSpace();
    if (_pos != s.length) {
      _fail('Extra data', _pos);
    }
    return value;
  }

  // Reads the value at [_pos], keeping the containers it's inside on a stack
  // of its own rather than on Dart's, which is smaller than Python's. Python
  // fails at the same depth that it reaches by recursion.
  Object? _value() {
    final stack = <_Open>[];
    while (true) {
      Object? value;
      final c = _char(_pos);
      if (c == 0x7b || c == 0x5b) {
        if (stack.length >= maxJsonDepth) {
          throw PyJsonDepthError(
            'maximum recursion depth exceeded while decoding a JSON '
            '${c == 0x7b ? 'object' : 'array'} from a unicode string',
          );
        }
        _pos++;
        _skipSpace();
        if (c == 0x7b) {
          if (_char(_pos) == 0x7d) {
            _pos++;
            value = <String, Object?>{};
          } else {
            stack.add(_Open.object(<String, Object?>{}, _key()));
            continue;
          }
        } else if (_char(_pos) == 0x5d) {
          _pos++;
          value = <Object?>[];
        } else {
          stack.add(_Open.array(<Object?>[]));
          continue;
        }
      } else {
        value = _scalar();
      }
      // Store the value, and close every container that it completes.
      while (true) {
        if (stack.isEmpty) {
          return value;
        }
        final open = stack.last;
        final map = open.map;
        final list = open.list;
        if (map != null) {
          // Python's `dict` keeps a repeated key where it first appeared,
          // with the last value.
          map[open.key!] = value;
        } else {
          list!.add(value);
        }
        final close = map != null ? 0x7d : 0x5d;
        _skipSpace();
        final next = _char(_pos);
        _pos++;
        if (next == close) {
          value = map ?? list;
          stack.removeLast();
          continue;
        }
        if (next != 0x2c) {
          _fail("Expecting ',' delimiter", _pos - 1);
        }
        final comma = _pos - 1;
        _skipSpace();
        if (_char(_pos) == close) {
          _fail(
            'Illegal trailing comma before end of '
            '${map != null ? 'object' : 'array'}',
            comma,
          );
        }
        if (map != null) {
          open.key = _key();
        }
        break;
      }
    }
  }

  // A key of an object, its `:`, and the space before its value.
  String _key() {
    if (_char(_pos) != 0x22) {
      _fail('Expecting property name enclosed in double quotes', _pos);
    }
    final key = _string();
    _skipSpace();
    if (_char(_pos) != 0x3a) {
      _fail("Expecting ':' delimiter", _pos);
    }
    _pos++;
    _skipSpace();
    return key;
  }

  Object? _scalar() {
    final c = _char(_pos);
    if (c == 0x22) {
      return _string();
    }
    if (c == 0x6e && _startsWith('null')) {
      _pos += 4;
      return null;
    }
    if (c == 0x74 && _startsWith('true')) {
      _pos += 4;
      return true;
    }
    if (c == 0x66 && _startsWith('false')) {
      _pos += 5;
      return false;
    }
    if (_number() case (final Object value,)) {
      return value;
    }
    if (c == 0x4e && _startsWith('NaN')) {
      _pos += 3;
      return double.nan;
    }
    if (c == 0x49 && _startsWith('Infinity')) {
      _pos += 8;
      return double.infinity;
    }
    if (c == 0x2d && _startsWith('-Infinity')) {
      _pos += 9;
      return double.negativeInfinity;
    }
    _fail('Expecting value', _pos);
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  // `-?(?:0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?`, or `null` for no
  // match.
  (Object,)? _number() {
    final start = _pos;
    var i = start;
    if (_char(i) == 0x2d) {
      i++;
    }
    if (_char(i) == 0x30) {
      i++;
    } else if (_char(i) >= 0x31 && _char(i) <= 0x39) {
      while (_isDigit(_char(i))) {
        i++;
      }
    } else {
      return null;
    }
    final intEnd = i;
    var isFloat = false;
    if (_char(i) == 0x2e && _isDigit(_char(i + 1))) {
      i += 2;
      while (_isDigit(_char(i))) {
        i++;
      }
      isFloat = true;
    }
    if (_char(i) == 0x65 || _char(i) == 0x45) {
      var j = i + 1;
      if (_char(j) == 0x2b || _char(j) == 0x2d) {
        j++;
      }
      if (_isDigit(_char(j))) {
        while (_isDigit(_char(j))) {
          j++;
        }
        i = j;
        isFloat = true;
      }
    }
    final text = s.substring(start, i);
    _pos = i;
    if (isFloat) {
      return (double.parse(text),);
    }
    final digits = intEnd - start - (s.codeUnitAt(start) == 0x2d ? 1 : 0);
    if (digits > _maxIntDigits) {
      throw PyJsonError(
        'Exceeds the limit ($_maxIntDigits digits) for integer string '
        'conversion: value has $digits digits; use '
        'sys.set_int_max_str_digits() to increase the limit',
      );
    }
    // An integer too large for an int reads as its exact value.
    return (int.tryParse(text) ?? BigInt.parse(text),);
  }

  String _string() {
    final begin = _pos;
    _pos++;
    final out = StringBuffer();
    while (true) {
      final chunkStart = _pos;
      while (_pos < s.length) {
        final c = s.codeUnitAt(_pos);
        if (c == 0x22 || c == 0x5c || c < 0x20) {
          break;
        }
        _pos++;
      }
      out.write(s.substring(chunkStart, _pos));
      if (_pos >= s.length) {
        _fail('Unterminated string starting at', begin);
      }
      final c = s.codeUnitAt(_pos);
      _pos++;
      if (c == 0x22) {
        return out.toString();
      }
      if (c != 0x5c) {
        _fail('Invalid control character at', _pos - 1);
      }
      if (_pos >= s.length) {
        _fail('Unterminated string starting at', begin);
      }
      final esc = s.codeUnitAt(_pos);
      if (esc != 0x75) {
        final char = switch (esc) {
          0x22 => '"',
          0x5c => r'\',
          0x2f => '/',
          0x62 => '\b',
          0x66 => '\f',
          0x6e => '\n',
          0x72 => '\r',
          0x74 => '\t',
          _ => null,
        };
        if (char == null) {
          _fail(r'Invalid \escape', _pos - 1);
        }
        out.write(char);
        _pos++;
        continue;
      }
      var uni = _hex4(_pos);
      _pos += 5;
      if (uni >= 0xd800 &&
          uni <= 0xdbff &&
          _char(_pos) == 0x5c &&
          _char(_pos + 1) == 0x75) {
        final uni2 = _hex4(_pos + 1);
        if (uni2 >= 0xdc00 && uni2 <= 0xdfff) {
          uni = 0x10000 + (((uni - 0xd800) << 10) | (uni2 - 0xdc00));
          _pos += 6;
        }
      }
      out.writeCharCode(uni);
    }
  }

  // The four hex digits after the `u` at [pos].
  int _hex4(int pos) {
    var value = 0;
    for (var k = 1; k <= 4; k++) {
      final c = _char(pos + k);
      final int digit;
      if (c >= 0x30 && c <= 0x39) {
        digit = c - 0x30;
      } else if (c >= 0x61 && c <= 0x66) {
        digit = c - 0x61 + 10;
      } else if (c >= 0x41 && c <= 0x46) {
        digit = c - 0x41 + 10;
      } else {
        _fail(r'Invalid \uXXXX escape', pos);
      }
      value = value * 16 + digit;
    }
    return value;
  }
}

// ---------------------------------------------------------------------------
// Values to text
// ---------------------------------------------------------------------------

// Writes [root], keeping the lists and maps it's inside on a stack of its
// own rather than on Dart's, so that it writes as deep a value as it reads.
void _dump(Object? root, StringBuffer out) {
  final active = Set<Object>.identity();
  final stack = <_Dumping>[];
  var value = root;
  while (true) {
    switch (value) {
      case null:
        out.write('null');
      case true:
        out.write('true');
      case false:
        out.write('false');
      case final String s:
        _dumpString(s, out);
      case final int n:
        out.write(n);
      case final BigInt n:
        out.write(n);
      case final double d:
        out.write(_floatText(d));
      case final List<Object?> list:
        if (!active.add(list)) {
          throw ArgumentError('Circular reference detected');
        }
        out.write('[');
        stack.add(_Dumping.list(list));
      case final Map<Object?, Object?> map:
        if (!active.add(map)) {
          throw ArgumentError('Circular reference detected');
        }
        out.write('{');
        stack.add(_Dumping.map(map));
      default:
        throw ArgumentError(
          'Object of type ${pyTypeName(value)} is not JSON serializable',
        );
    }
    // Move to the next value, closing every container that's done.
    while (true) {
      if (stack.isEmpty) {
        return;
      }
      final top = stack.last;
      if (top.next(out) case (final Object? item,)) {
        value = item;
        break;
      }
      out.write(top.list != null ? ']' : '}');
      active.remove(top.list ?? top.map!);
      stack.removeLast();
    }
  }
}

// A list or map that [_dump] is writing, and how far it got.
final class _Dumping {
  new list(List<Object?> this.list) : map = null, _entries = null;

  new map(Map<Object?, Object?> this.map)
    : list = null,
      _entries = map.entries.iterator;

  final List<Object?>? list;
  final Map<Object?, Object?>? map;
  final Iterator<MapEntry<Object?, Object?>>? _entries;
  int _index = 0;

  // Writes the separator and, for a map, the key of the next item, and
  // returns the item, or `null` when there's none left.
  (Object?,)? next(StringBuffer out) {
    final list = this.list;
    if (list != null) {
      if (_index >= list.length) {
        return null;
      }
      if (_index > 0) {
        out.write(',');
      }
      return (list[_index++],);
    }
    if (!_entries!.moveNext()) {
      return null;
    }
    if (_index++ > 0) {
      out.write(',');
    }
    final MapEntry(:key, :value) = _entries.current;
    _dumpString(_keyText(key), out);
    out.write(':');
    return (value,);
  }
}

// Python converts a key that isn't a string the way it writes the value.
String _keyText(Object? key) => switch (key) {
  final String s => s,
  null => 'null',
  true => 'true',
  false => 'false',
  final int n => '$n',
  final BigInt n => '$n',
  final double d => _floatText(d),
  _ => throw ArgumentError(
    'keys must be str, int, float, bool or None, not ${pyTypeName(key)}',
  ),
};

String _floatText(double d) {
  if (d.isNaN) {
    return 'NaN';
  }
  if (d.isInfinite) {
    return d > 0 ? 'Infinity' : '-Infinity';
  }
  return pyFloatRepr(d);
}

// `py_encode_basestring`: quotes, backslashes, and control characters are
// escaped; everything else stays as it is.
void _dumpString(String s, StringBuffer out) {
  out.write('"');
  var start = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0x20 && c != 0x22 && c != 0x5c) {
      continue;
    }
    out
      ..write(s.substring(start, i))
      ..write(switch (c) {
        0x22 => r'\"',
        0x5c => r'\\',
        0x0a => r'\n',
        0x0d => r'\r',
        0x09 => r'\t',
        0x08 => r'\b',
        0x0c => r'\f',
        _ => '\\u${c.toRadixString(16).padLeft(4, '0')}',
      });
    start = i + 1;
  }
  out
    ..write(s.substring(start))
    ..write('"');
}
