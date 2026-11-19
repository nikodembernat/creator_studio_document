// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

// Regenerates the models in memory and checks that the committed output
// matches, so tool/schema.json, tool/src/generator.dart, and the generated
// files can't drift apart.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/src/generator.dart';

void main() {
  test('generated files match tool/schema.json and the generator', () async {
    final schema = jsonDecode(
      File('tool/schema.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final files = generate(schema);
    final scratch = Directory('.dart_tool/creator_studio_document_generated');
    if (scratch.existsSync()) {
      scratch.deleteSync(recursive: true);
    }
    scratch.createSync(recursive: true);
    final written = <String, File>{};
    for (final MapEntry(:key, :value) in files.entries) {
      final file = File(p.join(scratch.path, p.basename(key)))
        ..writeAsStringSync(value);
      written[key] = file;
    }
    final format = await Process.run('dart', [
      'format',
      ...written.values.map((f) => f.path),
    ]);
    expect(format.exitCode, 0, reason: '${format.stdout}${format.stderr}');
    for (final MapEntry(:key, :value) in written.entries) {
      expect(
        File(key).readAsStringSync() == value.readAsStringSync(),
        isTrue,
        reason: '$key is stale; run `dart run tool/generate.dart`',
      );
    }
    scratch.deleteSync(recursive: true);
  });

  test('tool/README.md lists every reference data script', () {
    // Each `make_*.py` script writes data the tests compare against, so the
    // update procedure must run all of them.
    final readme = File('tool/README.md').readAsStringSync();
    final scripts = [
      for (final f in Directory('tool').listSync().whereType<File>())
        if (p.basename(f.path) case final name
            when name.startsWith('make_') && name.endsWith('.py'))
          name,
    ];
    expect(scripts, hasLength(4));
    for (final name in scripts) {
      expect(readme, contains('python -I tool/$name'), reason: name);
    }
  });
}
