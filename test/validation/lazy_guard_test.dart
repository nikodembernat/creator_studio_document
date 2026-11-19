// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/test_lazy_guard.py.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';
import 'package:test/test.dart';

import 'builders.dart';

// Flips a bit of the CRC that the central directory records for [name], so
// reading the member's bytes throws.
Uint8List _withBadCrc(Uint8List zip, String name) {
  final bytes = Uint8List.fromList(zip);
  final data = ByteData.sublistView(bytes);
  final want = utf8.encode(name);
  for (var i = 0; i + 46 <= bytes.length; i++) {
    if (data.getUint32(i, Endian.little) != 0x02014b50) {
      continue;
    }
    final length = data.getUint16(i + 28, Endian.little);
    final got = bytes.sublist(i + 46, i + 46 + length);
    if (const ListEquality<int>().equals(got, want)) {
      bytes[i + 16] ^= 1;
      return bytes;
    }
  }
  throw StateError('no central directory entry for $name');
}

void main() {
  // Upstream counts the calls of a patched `_ZipBackend.read`. Here the
  // resource's CRC is broken, so reading its bytes would throw.
  test('validateDocument reads no resource bytes when lazy '
      '(test_validate_document_reads_no_resource_bytes_when_lazy)', () {
    final tmp = Directory.systemTemp.createTempSync('validation_lazy_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final doc = docWithIndirectImage('present.png');
    doc.resources['present.png'] = png;
    final path = '${tmp.path}/d.keyx';
    doc.save(path);
    File(path).writeAsBytesSync(
      _withBadCrc(File(path).readAsBytesSync(), 'Data/present.png'),
    );

    final lazy = KeyxDocument.openLazy(path);
    try {
      validateDocument(lazy);
      expect(
        () => lazy.resources['present.png'],
        throwsA(isA<DocumentPackageError>()),
        reason: 'the bytes are unreadable, so validation never read them',
      );
    } finally {
      lazy.close();
    }
  });
}
