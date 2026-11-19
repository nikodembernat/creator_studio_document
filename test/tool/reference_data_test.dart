// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

// Checks the scripts in tool/ that write the reference data of the tests:
// that their documentation names files that exist, and that what they write
// comes out the same on every run.

@TestOn('vm')
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// The paths in backquotes that start at the package root, such as
// `test/fixtures/package/expected.json` or `test/examples/expected/<name>.zip`.
final _path = RegExp(r'`((?:example|lib|test|tool)/[^`\s]*)`');

// The docstring of a Python script: the text of its first triple quotes.
String _docstring(String source) {
  final start = source.indexOf('"""');
  return start < 0
      ? ''
      : source.substring(start, source.indexOf('"""', start + 3));
}

// Whether [pattern], a path that may hold `*` and `<placeholder>`, names a
// file or folder that exists.
bool _exists(String pattern) {
  if (!pattern.contains('*') && !pattern.contains('<')) {
    return FileSystemEntity.typeSync(pattern) != FileSystemEntityType.notFound;
  }
  final dir = Directory(p.dirname(pattern));
  final name = RegExp(
    '^${RegExp.escape(p.basename(pattern)).replaceAll(r'\*', '.*').replaceAll(RegExp('<[^>]*>'), '.+')}\$',
  );
  return dir.existsSync() &&
      dir.listSync().any((e) => name.hasMatch(p.basename(e.path)));
}

void main() {
  test('the generators and their README name files that exist', () {
    final documents = {
      'tool/README.md': File('tool/README.md').readAsStringSync(),
      for (final script in Directory(
        'tool',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.py')))
        script.path: _docstring(script.readAsStringSync()),
    };
    final named = <String>{};
    for (final MapEntry(key: document, value: text) in documents.entries) {
      for (final match in _path.allMatches(text)) {
        final path = match[1]!;
        named.add(path);
        expect(_exists(path), isTrue, reason: '$document names $path');
      }
    }
    expect(named, contains('test/fixtures/expected/wire_cases.json'));
    expect(named, contains('tool/wire_cases.py'));
  });

  test('the expected example documents have a fixed timestamp', () {
    // 2026-01-01 00:00:00, in the date and time fields of a ZIP entry.
    const fixed = ((2026 - 1980) << 9 | 1 << 5 | 1) << 16;
    final zips = Directory('test/examples/expected')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.zip'));
    expect(zips, isNotEmpty);
    for (final zip in zips) {
      final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
      for (final entry in archive.files) {
        expect(
          entry.lastModDosTime,
          fixed,
          reason: '${zip.path}: ${entry.name}',
        );
      }
    }
  });
}
