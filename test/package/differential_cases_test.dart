// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

// Opens every archive in test/fixtures/package/ eagerly and lazily, saves
// what opens, and compares the outcome with upstream's, which
// tool/make_package_cases.py recorded in test/fixtures/package/expected.json:
// the error kind, or the manifest, presets, resources, and saved entries.

@TestOn('vm')
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/src/core/package_json.dart';
import 'package:test/test.dart';

// Where upstream lets an exception that isn't a `DocumentPackageError`
// escape, and what the port throws instead.
const _deviations = {
  // `zipfile` raises `BadZipFile` from `is_zipfile`, outside upstream's
  // `_catching_zip_errors`.
  'BadZipFile': 'malformed_archive',
  // Python's UTF-8 encoder rejects a lone surrogate.
  'UnicodeEncodeError': 'StateError',
};

// The cases where the port throws something else than upstream for a reason
// of its own, by case.
const _caseDeviations = {
  // A local header before the start of the file: Python's seek fails with
  // `OSError` (`EINVAL`), which upstream lets escape as an error of the file
  // system. The port reports the damaged central directory.
  'negative_header_offset.keyx': {'OSError': 'malformed_archive'},
};

String _outcomeOf(Object error) => switch (error) {
  DocumentPackageError(:final kind) => kind.value,
  DocumentVersionError() => 'DocumentVersionError',
  ModelValidationError() => 'ValidationError',
  _ => '${error.runtimeType}',
};

String _crc(List<int> data) =>
    '${getCrc32(data).toRadixString(16).padLeft(8, '0')}:${data.length}';

void main() {
  final expected =
      pyJsonLoads(
            File('test/fixtures/package/expected.json').readAsBytesSync(),
          )!
          as Map<String, Object?>;
  final cases = expected['cases']! as Map<String, Object?>;
  final parts = expected['parts']! as Map<String, Object?>;
  late Directory scratch;

  setUpAll(() {
    scratch = Directory.systemTemp.createTempSync('package_cases_');
  });
  tearDownAll(() => scratch.deleteSync(recursive: true));

  test('every case is present', () {
    expect(cases, hasLength(63));
  });

  for (final MapEntry(key: name, :value) in cases.entries) {
    final byMode = value! as Map<String, Object?>;
    for (final mode in const ['open', 'lazy']) {
      final want = byMode[mode]! as Map<String, Object?>;
      test('$name ($mode)', () {
        final path = 'test/fixtures/package/$name';
        final KeyxDocument doc;
        try {
          doc = mode == 'open'
              ? KeyxDocument.open(path)
              : KeyxDocument.openLazy(path);
        } on Object catch (e) {
          final error = want['error'] as String?;
          expect(error, isNotNull, reason: 'upstream opens it; got $e');
          expect(
            _outcomeOf(e),
            _caseDeviations[name]?[error] ?? _deviations[error] ?? error,
            reason: '$e',
          );
          return;
        }
        try {
          expect(want['error'], isNull, reason: 'upstream fails to open it');
          expect(doc.manifest.packageVersion, want['manifest']);
          expect([for (final p in doc.presets) p.identifier], want['presets']);
          expect(doc.resources.keys.toList()..sort(), want['resources']);
          final saved = '${scratch.path}/$name.$mode';
          try {
            doc.save(saved, validateResources: false);
          } on Object catch (e) {
            final error = want['save_error'] as String?;
            expect(error, isNotNull, reason: 'upstream saves it; got $e');
            expect(_outcomeOf(e), _deviations[error] ?? error);
            return;
          }
          expect(want['save_error'], isNull, reason: 'upstream fails to save');
          final archive = ZipDecoder().decodeBytes(
            File(saved).readAsBytesSync(),
          );
          final entries = want['saved']! as Map<String, Object?>;
          expect(
            [for (final f in archive.files) f.name]..sort(),
            entries.keys.toList()..sort(),
          );
          for (final file in archive.files) {
            final bytes = file.content;
            final crc = entries[file.name]! as String;
            if (file.name.endsWith('.json') && !file.name.contains('/')) {
              expect(
                sameJson(pyJsonLoads(bytes), parts[crc]),
                isTrue,
                reason: '${file.name} differs from upstream',
              );
              // The port writes the same text as upstream's `_dumps`.
              expect(_crc(bytes), crc, reason: '${file.name} text differs');
            } else {
              expect(_crc(bytes), crc, reason: '${file.name} bytes differ');
            }
          }
        } finally {
          doc.close();
        }
      });
    }
  }

  test('a directory is not a package, eagerly or lazily', () {
    final dir = Directory('${scratch.path}/folder.keyx')..createSync();
    for (final open in [KeyxDocument.open, KeyxDocument.openLazy]) {
      expect(
        () => open(dir.path),
        throwsA(
          isA<DocumentPackageError>()
              .having(
                (e) => e.kind,
                'kind',
                DocumentPackageErrorKind.notAPackage,
              )
              .having(
                (e) => e.message,
                'message',
                "'${dir.path}' is a directory, not a ZIP package",
              ),
        ),
      );
    }
  });
}
