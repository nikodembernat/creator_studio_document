// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from Python 3.13's `urllib.parse.urlparse` and `ipaddress`, which
// upstream's `Hyperlink.url` check relies on.

/// The URL parsing that upstream's `Hyperlink.url` check relies on: Python
/// 3.13's `urllib.parse.urlparse`, reduced to the scheme it returns and the
/// errors it raises.
library;

import 'package:creator_studio_document/src/authoring/layout_name_key.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/validation/py_text.dart';

/// A URL that Python's `urllib.parse.urlparse` refuses, with the message of
/// its `ValueError`.
final class const PyUrlError(
  /// The message of Python's `ValueError`.
  final String message,
) implements Exception {
  /// Creates an error.
  this;

  @override
  String toString() => message;
}

const _schemeChars =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-.';

/// Returns the scheme that Python's `urllib.parse.urlparse(url)` finds in
/// [url], lowercased, or `''` for none.
///
/// Throws [PyUrlError] where Python raises `ValueError`: a bracketed host
/// that isn't an IPv6 address or a valid IPvFuture one, unbalanced
/// brackets, or a host that NFKC normalization gives a URL delimiter.
String pyUrlScheme(String url) {
  var rest = _lstripC0(url).replaceAll(RegExp('[\t\r\n]'), '');
  var scheme = '';
  final i = rest.indexOf(':');
  if (i > 0 && _isAsciiLetter(rest.codeUnitAt(0))) {
    final candidate = rest.substring(0, i);
    if (candidate.codeUnits.every(_schemeChars.codeUnits.contains)) {
      scheme = candidate.toLowerCase();
      rest = rest.substring(i + 1);
    }
  }
  var netloc = '';
  if (rest.startsWith('//')) {
    var delim = rest.length;
    for (final c in const ['/', '?', '#']) {
      final w = rest.indexOf(c, 2);
      if (w >= 0 && w < delim) {
        delim = w;
      }
    }
    netloc = rest.substring(2, delim);
    final open = netloc.contains('[');
    final close = netloc.contains(']');
    if (open != close) {
      throw const PyUrlError('Invalid IPv6 URL');
    }
    if (open && close) {
      _checkBracketedNetloc(netloc);
    }
  }
  _checkNetloc(netloc);
  return scheme;
}

bool _isAsciiLetter(int c) => (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7a;

String _lstripC0(String s) {
  var i = 0;
  while (i < s.length && s.codeUnitAt(i) <= 0x20) {
    i++;
  }
  return s.substring(i);
}

// Python's `str.partition`.
(String, bool, String) _partition(String s, String sep) {
  final i = s.indexOf(sep);
  return i < 0
      ? (s, false, '')
      : (s.substring(0, i), true, s.substring(i + sep.length));
}

void _checkBracketedNetloc(String netloc) {
  final hostAndPort = netloc.substring(netloc.lastIndexOf('@') + 1);
  final (before, hasOpen, bracketed) = _partition(hostAndPort, '[');
  final String hostname;
  if (hasOpen) {
    if (before.isNotEmpty) {
      throw const PyUrlError('Invalid IPv6 URL');
    }
    final (host, _, port) = _partition(bracketed, ']');
    if (port.isNotEmpty && !port.startsWith(':')) {
      throw const PyUrlError('Invalid IPv6 URL');
    }
    hostname = host;
  } else {
    hostname = _partition(hostAndPort, ':').$1;
  }
  _checkBracketedHost(hostname);
}

final _ipvFuture = RegExp(r'^v[a-fA-F0-9]+\..+$', dotAll: true);

void _checkBracketedHost(String hostname) {
  if (hostname.startsWith('v')) {
    if (!_ipvFuture.hasMatch(hostname)) {
      throw const PyUrlError('IPvFuture address is invalid');
    }
  } else if (isIPv4Address(hostname)) {
    throw const PyUrlError('An IPv4 address cannot be in brackets');
  } else if (!isIPv6Address(hostname)) {
    throw PyUrlError(
      '${pyStringRepr(hostname)} does not appear to be an IPv4 or IPv6 '
      'address',
    );
  }
}

void _checkNetloc(String netloc) {
  if (netloc.isEmpty || pyIsAscii(netloc)) {
    return;
  }
  final n = netloc
      .replaceAll('@', '')
      .replaceAll(':', '')
      .replaceAll('#', '')
      .replaceAll('?', '');
  final normalized = nfkc(n);
  if (n == normalized) {
    return;
  }
  for (final c in const ['/', '?', '#', '@', ':']) {
    if (normalized.contains(c)) {
      throw PyUrlError(
        "netloc '$netloc' contains invalid characters under NFKC "
        'normalization',
      );
    }
  }
}

bool _isAsciiDigits(String s) =>
    s.isNotEmpty && s.codeUnits.every((c) => c >= 0x30 && c <= 0x39);

/// Whether Python's `ipaddress.IPv4Address` accepts [s].
bool isIPv4Address(String s) {
  if (s.isEmpty || s.contains('/')) {
    return false;
  }
  final octets = s.split('.');
  if (octets.length != 4) {
    return false;
  }
  for (final octet in octets) {
    if (!_isAsciiDigits(octet) || octet.length > 3) {
      return false;
    }
    if (octet != '0' && octet.startsWith('0')) {
      return false;
    }
    if (int.parse(octet) > 255) {
      return false;
    }
  }
  return true;
}

bool _isHextet(String s) =>
    s.isNotEmpty &&
    s.length <= 4 &&
    s.codeUnits.every(
      (c) =>
          (c >= 0x30 && c <= 0x39) ||
          (c >= 0x41 && c <= 0x46) ||
          (c >= 0x61 && c <= 0x66),
    );

/// Whether Python's `ipaddress.IPv6Address` accepts [s], with an optional
/// `%` scope.
bool isIPv6Address(String s) {
  if (s.contains('/')) {
    return false;
  }
  final (addr, hasScope, scope) = _partition(s, '%');
  if (hasScope && (scope.isEmpty || scope.contains('%'))) {
    return false;
  }
  if (addr.isEmpty || pyLength(addr) > 45) {
    return false;
  }
  final parts = addr.split(':');
  if (parts.length < 3) {
    return false;
  }
  if (parts.last.contains('.')) {
    if (!isIPv4Address(parts.removeLast())) {
      return false;
    }
    parts.addAll(['0', '0']);
  }
  if (parts.length > 9) {
    return false;
  }
  int? skip;
  for (var i = 1; i < parts.length - 1; i++) {
    if (parts[i].isEmpty) {
      if (skip != null) {
        return false;
      }
      skip = i;
    }
  }
  final int hi;
  final int lo;
  if (skip != null) {
    var partsHi = skip;
    var partsLo = parts.length - skip - 1;
    if (parts.first.isEmpty) {
      partsHi--;
      if (partsHi != 0) {
        return false;
      }
    }
    if (parts.last.isEmpty) {
      partsLo--;
      if (partsLo != 0) {
        return false;
      }
    }
    if (8 - (partsHi + partsLo) < 1) {
      return false;
    }
    hi = partsHi;
    lo = partsLo;
  } else {
    if (parts.length != 8 || parts.first.isEmpty || parts.last.isEmpty) {
      return false;
    }
    hi = parts.length;
    lo = 0;
  }
  return [...parts.take(hi), ...parts.skip(parts.length - lo)].every(_isHextet);
}
