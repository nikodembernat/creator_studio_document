// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

// Decodes every fixture's main.json with its presets, iterates the models, and
// compares each visit's path, class name, index path, and number of ancestors
// with what upstream's `iterate_models` yields
// (test/fixtures/expected/*.navigation.json, written by
// tool/make_navigation_expected.py).

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/navigation.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Decodes `main.json` of the `.keyx` [file] into a [Presentation], resolving
/// presets from its `presets.json`, as opening the document does.
Presentation _readPresentation(File file) {
  final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
  Object? read(String entry) {
    final f = archive.findFile(entry);
    return f == null ? null : jsonDecode(utf8.decode(f.content));
  }

  final presets = [
    for (final e in (read('presets.json') as List<Object?>? ?? const []))
      Preset.fromJson((e! as Map).cast<String, Object?>()),
  ];
  return Presentation.fromJson(
    read('main.json'),
    WireContext(presets: PresetRegistry(presets)),
  );
}

void main() {
  final fixtures =
      Directory('test/fixtures')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.keyx'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('fixtures are present', () {
    expect(fixtures, isNotEmpty);
  });

  for (final file in fixtures) {
    final name = p.basenameWithoutExtension(file.path);
    test('$name iterates like upstream', () {
      final expected = jsonDecode(
        File('test/fixtures/expected/$name.navigation.json').readAsStringSync(),
      ) as List<Object?>;
      final actual = [
        for (final v in iterateModels(_readPresentation(file)))
          [v.path, v.model.wireSchema.name, v.indexPath, v.ancestors.length],
      ];
      expect(actual, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        expect(actual[i], expected[i], reason: 'visit $i');
      }
    });
  }
}
