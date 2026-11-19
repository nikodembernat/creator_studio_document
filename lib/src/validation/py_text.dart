// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// The Python string predicates that the validators rely on, which Dart's
/// own differ from.
library;

import 'package:creator_studio_document/src/core/py_repr.dart';

/// Whether [cp] is whitespace, as Python's `str.isspace` and the regular
/// expression `\s` decide it.
///
/// Unlike Dart's [String.trim], it counts U+001C to U+001F and not U+FEFF.
bool pyIsSpace(int cp) => switch (cp) {
  >= 0x09 && <= 0x0d || >= 0x1c && <= 0x20 => true,
  0x85 || 0xa0 || 0x1680 || 0x2028 || 0x2029 || 0x202f || 0x205f => true,
  >= 0x2000 && <= 0x200a || 0x3000 => true,
  _ => false,
};

/// Whether [s] is empty or holds only whitespace, as Python's
/// `not s or not s.strip()` decides it.
bool pyIsBlank(String s) => s.runes.every(pyIsSpace);

/// Whether every character of [s] is ASCII, as Python's `str.isascii`.
bool pyIsAscii(String s) => s.codeUnits.every((c) => c < 0x80);

/// Returns [s] without its whitespace, as Python's `"".join(s.split())`.
String pyRemoveSpace(String s) =>
    String.fromCharCodes(s.runes.where((c) => !pyIsSpace(c)));

/// Returns the first [n] code points of [s], as Python's `s[:n]`.
String pyPrefix(String s, int n) => String.fromCharCodes(s.runes.take(n));

/// The number of code points in [s], as Python's `len(s)`.
int pyLength(String s) => s.runes.length;

/// Returns [text], or its first [limit] code points followed by the full
/// count of code points, as the validators shorten a quoted value.
String pyShorten(String text, int limit) {
  final length = pyLength(text);
  return length <= limit
      ? text
      : '${pyPrefix(text, limit)}… ($length characters)';
}

/// Returns Python's `repr` of a sorted list of strings, as
/// `repr(sorted(values))` writes it.
String pySortedRepr(Iterable<String> values) =>
    pyRepr(values.toList()..sort(compareCodePoints));
