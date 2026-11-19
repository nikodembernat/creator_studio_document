// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

// Opens every archive of test/fixtures/package/codec_cases.json from its
// bytes and compares the outcome with upstream's, which
// tool/make_package_cases.py recorded: the error kind and message, or the
// CRC-32 and length of each resource. The archives hold a resource that is
// stored, deflated, bzip2, or LZMA data, intact, cut short, damaged, or with
// a wrong size or flags, so they check that a member reads as Python's
// `zipfile` and its decompressors read it.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:test/test.dart';

import 'messages.dart';

String _crc(List<int> data) =>
    '${getCrc32(data).toRadixString(16).padLeft(8, '0')}:${data.length}';

void main() {
  final cases = jsonDecode(
    File('test/fixtures/package/codec_cases.json').readAsStringSync(),
  ) as Map<String, Object?>;

  test('every case is present', () {
    expect(cases, hasLength(264));
  });

  for (final MapEntry(key: name, :value) in cases.entries) {
    final want = value! as Map<String, Object?>;
    test(name, () {
      final bytes = base64Decode(want['archive']! as String);
      final KeyxDocument doc;
      try {
        doc = KeyxDocument.fromBytes(bytes);
      } on DocumentPackageError catch (e) {
        expect(want['error'], e.kind.value, reason: '$e');
        expect(
          sameMessage(e.message, want['message']! as String),
          isTrue,
          reason: 'upstream: ${want['message']}\nport:     ${e.message}',
        );
        return;
      }
      expect(want['error'], isNull, reason: 'upstream: ${want['message']}');
      expect({
        for (final MapEntry(:key, :value) in doc.resources.entries)
          key: _crc(value),
      }, want['resources']);
    });
  }

  test('the merged zlib message matches either of zlib', () {
    const prefix = 'Error -3 while decompressing data: ';
    const merged = '${prefix}invalid literal/length/distance code';
    expect(sameMessage('${prefix}invalid distance code', merged), isTrue);
    expect(sameMessage('${prefix}invalid literal/length code', merged), isTrue);
    expect(sameMessage('${prefix}invalid block type', merged), isFalse);
  });
}
