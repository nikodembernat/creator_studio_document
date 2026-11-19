// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/test_lazy_guard.py. Upstream checks that
// `validate_document` reads no resource bytes from a lazily opened package;
// here the check covers the package operations it relies on: encoding the
// payload, and resolving, counting, and listing the resources.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/src/core/package.dart';
import 'package:test/test.dart';

import 'builders.dart';

// Flips a bit of the CRC that the central directory records for [name].
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
  test('a lazily opened package reads no resource bytes until asked '
      '(test_validate_document_reads_no_resource_bytes_when_lazy)', () {
    final tmp = Directory.systemTemp.createTempSync('lazy_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final doc = docWithIndirectImage('present.png');
    doc.resources['present.png'] = png;
    final path = '${tmp.path}/d.keyx';
    doc.save(path);
    // Break the resource's CRC, so reading its bytes throws.
    File(path).writeAsBytesSync(
      _withBadCrc(File(path).readAsBytesSync(), 'Data/present.png'),
    );

    final lazy = KeyxDocument.openLazy(path);
    try {
      final main = lazy.toMainJson();
      for (final (_, name) in iterIndirectIdentifiers(
        main,
        PresetRegistry(lazy.presets),
      )) {
        expect(lazy.resources.canResolve(name), isTrue);
      }
      expect(lazy.resources.length, 1);
      expect(lazy.resources.keys, ['present.png']);
      expect(lazy.resources.containsKey('present.png'), isTrue);
      expect(lazy.resources.uniqueFilename('present.png'), 'present 2.png');
      expect(lazy.resources.isLazy, isTrue);
      expect('${lazy.resources}', "ResourceStore('present.png')");
      // Only now are the bytes read.
      expect(
        () => lazy.resources['present.png'],
        throwsA(
          isA<DocumentPackageError>().having(
            (e) => e.kind,
            'kind',
            DocumentPackageErrorKind.malformedArchive,
          ),
        ),
      );
    } finally {
      lazy.close();
    }
  });
}
