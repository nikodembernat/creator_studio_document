// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

// Decodes every fixture's main.json with its presets, encodes it again, and
// compares the result with what the upstream Python package produces
// (test/fixtures/expected/*.json, written by tool/make_expected.py).

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'json_matchers.dart';

void main() {
  final fixtures =
      Directory('test/fixtures')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.keyx'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('fixtures are present', () {
    expect(fixtures, hasLength(5));
  });

  for (final file in fixtures) {
    final name = p.basenameWithoutExtension(file.path);
    group(name, () {
      late Object? main;
      late List<Preset> presets;

      setUpAll(() {
        final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
        Object? read(String entry) {
          final f = archive.findFile(entry);
          return f == null ? null : jsonDecode(utf8.decode(f.content));
        }

        main = read('main.json');
        presets = [
          for (final e in (read('presets.json') as List<Object?>? ?? const []))
            Preset.fromJson((e! as Map).cast<String, Object?>()),
        ];
      });

      Object? expected(String suffix) => jsonDecode(
        File('test/fixtures/expected/$name.$suffix.json').readAsStringSync(),
      );

      for (final (suffix, strict) in const [
        ('roundtrip', false),
        ('roundtrip_strict', true),
      ]) {
        test('decodes and re-encodes like upstream ($suffix)', () {
          final model = Presentation.fromJson(
            main,
            WireContext(
              presets: PresetRegistry(presets),
              strictPresets: strict,
            ),
          );
          final encoded = model.toJson(
            WireContext(presets: PresetRegistry(presets)),
          );
          expect(encoded, sameJsonInOrder(expected(suffix)));
        });
      }

      test('a deep copy encodes the same and compares equal', () {
        final context = WireContext(presets: PresetRegistry(presets));
        final model = Presentation.fromJson(main, context);
        final copy = model.deepCopy();
        expect(copy, model);
        expect(copy.hashCode, model.hashCode);
        expect(identical(copy.slides, model.slides), isFalse);
        expect(
          copy.toJson(WireContext(presets: PresetRegistry(presets))),
          sameJsonInOrder(expected('roundtrip')),
        );
      });

      test('re-decoding the encoded JSON gives an equal model', () {
        final model = Presentation.fromJson(
          main,
          WireContext(presets: PresetRegistry(presets)),
        );
        final encoded = model.toJson(
          WireContext(presets: PresetRegistry(presets)),
        );
        final again = Presentation.fromJson(
          encoded,
          WireContext(presets: PresetRegistry(presets)),
        );
        expect(
          again.toJson(WireContext(presets: PresetRegistry(presets))),
          sameJsonInOrder(encoded),
        );
      });
    });
  }
}
