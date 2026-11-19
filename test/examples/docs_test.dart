// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

/// Checks the prose of the example scripts and of `example/README.md`: that
/// it says where each script comes from, and that it wraps at 80 columns.
@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

const _upstreamExamples = 'src/creator_studio_doc_format/examples/';

// The scripts in `example/`, by name without `.dart`.
List<String> _scripts() => [
  for (final f in Directory(
    p.join(packageRoot, 'example'),
  ).listSync().whereType<File>())
    if (f.path.endsWith('.dart')) p.basenameWithoutExtension(f.path),
]..sort();

// The lines of [text] that are prose: outside code blocks, and not a table
// row or a line that holds a link or a long code span.
Iterable<(int, String)> _proseLines(List<String> lines) sync* {
  var inCode = false;
  for (final (i, line) in lines.indexed) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('/// ```')) {
      inCode = !inCode;
      continue;
    }
    if (inCode || trimmed.startsWith('|') || line.contains('](')) {
      continue;
    }
    yield (i + 1, line);
  }
}

void main() {
  test('each script names its upstream source, as the README says', () {
    final scripts = _scripts();
    expect(scripts, contains('main'));
    for (final name in scripts) {
      final header = File(p.join(packageRoot, 'example', '$name.dart'))
          .readAsLinesSync()
          .take(7)
          .join('\n');
      expect(
        header,
        name == 'main'
            ? contains('the quick start of\n// README.md.')
            : contains('$_upstreamExamples$name.py.'),
        reason: name,
      );
    }
    final readme = File(p.join(packageRoot, 'example', 'README.md'))
        .readAsStringSync()
        .replaceAll('\n', ' ');
    expect(
      readme,
      allOf(
        contains(
          'Each script other than `main.dart` is a port of the upstream '
          'script of the same name',
        ),
        contains('`main.dart` is a port of the quick start in upstream'),
      ),
    );
  });

  test('the prose of the examples wraps at 80 columns', () {
    final files = [
      p.join(packageRoot, 'example', 'README.md'),
      for (final name in _scripts())
        p.join(packageRoot, 'example', '$name.dart'),
    ];
    for (final path in files) {
      final lines = File(path).readAsLinesSync();
      final dart = path.endsWith('.dart');
      for (final (number, line) in _proseLines(lines)) {
        // In a script, only comments are prose; `dart format` wraps code.
        if (dart && !line.trimLeft().startsWith('//')) {
          continue;
        }
        expect(
          line.length,
          lessThanOrEqualTo(80),
          reason: '${p.relative(path, from: packageRoot)}:$number: $line',
        );
      }
    }
  });
}
