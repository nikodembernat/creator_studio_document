// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

// Decodes every stream of test/fixtures/package/decompress_cases.json with
// the port of the decompressor that `zipfile` reads its method with, and
// compares the result with what tool/make_package_cases.py recorded from
// Python's: the CRC-32 and length of the output cut at a size and whether the
// stream ended, or the error message. The streams are deflate, bzip2, and
// `zipfile`'s LZMA data, intact, cut short, damaged, or followed by more
// bytes.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:creator_studio_document/src/core/py_decompress.dart';
import 'package:test/test.dart';

import 'messages.dart';

String _crc(List<int> data) =>
    '${getCrc32(data).toRadixString(16).padLeft(8, '0')}:${data.length}';

Decompressed _decode(int method, Uint8List data, int keep) => switch (method) {
  8 => inflateRaw(data, keep),
  12 => decodeBzip2(data, keep),
  14 => decodeZipLzma(data, keep),
  _ => throw ArgumentError.value(method, 'method'),
};

void main() {
  final cases = jsonDecode(
    File('test/fixtures/package/decompress_cases.json').readAsStringSync(),
  ) as List<Object?>;

  test('every case is present', () {
    expect(cases, hasLength(600));
  });

  for (final (index, value) in cases.indexed) {
    final want = value! as Map<String, Object?>;
    final method = want['method']! as int;
    final keep = want['keep']! as int;
    test('case $index (method $method, keeping $keep)', () {
      final data = base64Decode(want['data']! as String);
      final Decompressed out;
      try {
        out = _decode(method, data, keep);
      } on DecompressError catch (e) {
        final error = want['error'] as String?;
        expect(error, isNotNull, reason: 'upstream decodes it; got $e');
        expect(
          sameMessage(e.message, error!),
          isTrue,
          reason: 'upstream: $error\nport:     ${e.message}',
        );
        return;
      }
      expect(want['error'], isNull, reason: 'upstream: ${want['error']}');
      expect(_crc(out.data), want['output']);
      expect(out.ended, want['ended']);
    });
  }

  group('zipfile.LZMADecompressor', () {
    test('gives nothing until it has the header and the properties', () {
      for (final data in [
        <int>[],
        [9, 4, 5, 0],
        [9, 4, 5, 0, 0x5d, 0, 0, 16, 0],
        [9, 4, 0xff, 0, 1, 2, 3],
      ]) {
        final out = decodeZipLzma(Uint8List.fromList(data), 100);
        expect(out.data, isEmpty, reason: '$data');
        expect(out.ended, isFalse, reason: '$data');
      }
    });

    test('rejects properties that liblzma rejects', () {
      for (final props in [
        [0x5d, 0, 0, 16], // four bytes
        [225, 0, 0, 16, 0], // pb of 5
        [5, 0, 0, 16, 0], // lc + lp of 5
      ]) {
        expect(
          () => decodeZipLzma(
            Uint8List.fromList([9, 4, props.length, 0, ...props, 0, 0]),
            0,
          ),
          throwsA(
            isA<DecompressError>().having(
              (e) => e.message,
              'message',
              'Invalid or unsupported options',
            ),
          ),
          reason: '$props',
        );
      }
    });
  });

  test('a decompressor keeps only the size it is asked for', () {
    final content = Uint8List.fromList(List.generate(5000, (i) => i % 7));
    final zlib = const ZLibEncoder().encodeBytes(content);
    // The raw deflate stream, without zlib's header and checksum.
    final deflated = Uint8List.sublistView(zlib, 2, zlib.length - 4);
    for (final keep in [0, 1, 4999, 5000, 9000]) {
      final out = inflateRaw(deflated, keep);
      expect(out.data, content.take(keep), reason: '$keep');
      expect(out.ended, isTrue);
    }
  });
}
