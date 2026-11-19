// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:meta/meta.dart';

final _versionString = RegExp(r'^(\d+)(?:\.(\d+))?$');

/// A version number in major.minor form, as the file writes it.
///
/// The value is either an object's `version` or the manifest's
/// `package_version`. [Version.parse] accepts a `"major.minor"` or `"major"`
/// string, a `{"major": ..., "minor": ...}` map, where `minor` is optional, or
/// a [Version]. A missing minor reads as 0, and [Version.parse] ignores
/// leading zeros.
///
/// Like upstream's, a parsed version has no size limit. A part too large for
/// an [int] reads as the largest [int] through [major] or [minor], while
/// comparisons, equality, and [toString] use the exact value.
@immutable
class Version implements Comparable<Version> {
  /// Creates a version. [major] is the version a reader must implement to read
  /// the value; [minor] is one a reader can be older than.
  const new(this.major, [this.minor = 0]) : _bigMajor = null, _bigMinor = null;

  // `BigInt.toInt` clamps a value too large for an int.
  new _big(BigInt major, BigInt minor)
    : major = major.toInt(),
      minor = minor.toInt(),
      _bigMajor = major,
      _bigMinor = minor;

  // A version whose parts may not fit in an int.
  factory _exact(BigInt major, BigInt minor) =>
      major.isValidInt && minor.isValidInt
      ? Version(major.toInt(), minor.toInt())
      : Version._big(major, minor);

  /// The major version, which a reader must implement to read the value.
  final int major;

  /// The minor version, which a reader can be older than.
  final int minor;

  // The exact parts, set only when one of them doesn't fit in an int.
  final BigInt? _bigMajor;
  final BigInt? _bigMinor;

  bool get _isBig => _bigMajor != null;

  BigInt get _exactMajor => _bigMajor ?? BigInt.from(major);

  BigInt get _exactMinor => _bigMinor ?? BigInt.from(minor);

  /// Returns the version that [value] spells, or `null` if [value] isn't in an
  /// accepted form.
  ///
  /// A map part must be a non-negative [int] or [BigInt]. Like upstream, which
  /// requires a Python `int`, a [double] part is rejected even when it's
  /// whole, such as `1.0` or `1e19`. A package reads an integer literal beyond
  /// 64 bits as a [BigInt], but `dart:convert` decodes one as a [double], so
  /// a map version with such a part that `jsonDecode` read is rejected where
  /// upstream reads it; the string forms have no size limit.
  static Version? parse(Object? value) {
    switch (value) {
      case Version():
        return value;
      case Map<Object?, Object?>():
        final major = _part(value['major']);
        if (major == null) {
          return null;
        }
        final minor = _part(value['minor'] ?? 0);
        if (minor == null) {
          return null;
        }
        return Version._exact(major, minor);
      case String():
        final match = _versionString.firstMatch(value);
        if (match == null) {
          return null;
        }
        final minorText = match.group(2);
        return Version._exact(
          BigInt.parse(match.group(1)!),
          minorText == null ? BigInt.zero : BigInt.parse(minorText),
        );
    }
    return null;
  }

  static BigInt? _part(Object? value) => switch (value) {
    final int n when n >= 0 => BigInt.from(n),
    final BigInt n when !n.isNegative => n,
    _ => null,
  };

  @override
  int compareTo(Version other) {
    if (!_isBig && !other._isBig) {
      return major != other.major
          ? major.compareTo(other.major)
          : minor.compareTo(other.minor);
    }
    final byMajor = _exactMajor.compareTo(other._exactMajor);
    return byMajor != 0 ? byMajor : _exactMinor.compareTo(other._exactMinor);
  }

  /// Whether this version is older than [other].
  bool operator <(Version other) => compareTo(other) < 0;

  /// Whether this version is older than or the same as [other].
  bool operator <=(Version other) => compareTo(other) <= 0;

  /// Whether this version is newer than [other].
  bool operator >(Version other) => compareTo(other) > 0;

  /// Whether this version is newer than or the same as [other].
  bool operator >=(Version other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) => other is Version && compareTo(other) == 0;

  @override
  int get hashCode => _isBig
      ? Object.hash(_exactMajor, _exactMinor)
      : Object.hash(major, minor);

  @override
  String toString() => _isBig ? '$_exactMajor.$_exactMinor' : '$major.$minor';
}
