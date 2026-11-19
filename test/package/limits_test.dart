// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python): the outcomes of
// `Package.open` and `Package.save` in core/package.py at the edges of what
// Python, Pydantic, and `zipfile` accept, each checked against upstream
// 0.1.0 on Python 3.13: entry names that UTF-8 can't encode, integers too
// large for 64 bits, a preset cycle, and deeply nested JSON.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _plain = 'test/fixtures/package/ok_plain.keyx';

// The entries of ok_plain.keyx, with [replace] replacing or adding some.
Uint8List _plainWith(Map<String, String> replace) {
  final archive = ZipDecoder().decodeBytes(File(_plain).readAsBytesSync());
  final out = Archive();
  final names = {for (final f in archive.files) f.name: f.content};
  for (final MapEntry(:key, :value) in replace.entries) {
    names[key] = utf8.encode(value);
  }
  for (final MapEntry(:key, :value) in names.entries) {
    out.add(ArchiveFile.bytes(key, value));
  }
  return ZipEncoder().encodeBytes(out);
}

String _entry(Uint8List archive, String name) =>
    utf8.decode(ZipDecoder().decodeBytes(archive).findFile(name)!.content);

String _plainMain() => _entry(File(_plain).readAsBytesSync(), 'main.json');

// ok_plain's main.json with an unknown key `zzz` holding [json], on the
// object at [path].
String _mainWithExtra(List<Object> path, String json) {
  final main = jsonDecode(_plainMain()) as Map<String, Object?>;
  Object? node = main;
  for (final key in path) {
    node = switch (key) {
      final String k => (node! as Map<String, Object?>)[k],
      final int i => (node! as List<Object?>)[i],
      _ => throw ArgumentError(key),
    };
  }
  (node! as Map<String, Object?>)['zzz'] = '@@';
  return jsonEncode(main).replaceFirst('"@@"', json);
}

String _nested(int depth, [String leaf = '']) =>
    '${'[' * depth}$leaf${']' * depth}';

Matcher _stateError(String message) =>
    throwsA(isA<StateError>().having((e) => e.message, 'message', message));

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('limits_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('a resource filename that UTF-8 cannot encode', () {
    const message =
        r"'utf-8' codec can't encode character '\ud800' in position 6: "
        'surrogates not allowed';

    test('fails toBytes, as zipfile fails to write it', () {
      final doc = KeyxDocument.open(_plain);
      doc.resources['a\uD800.png'] = Uint8List.fromList([1]);
      expect(doc.toBytes, _stateError(message));
    });

    test('never merges two names that differ only in it', () {
      final doc = KeyxDocument.open(_plain);
      doc.resources['a\uD800.png'] = Uint8List.fromList([1]);
      doc.resources['a\uDC00.png'] = Uint8List.fromList([2]);
      expect(doc.toBytes, _stateError(message));
    });

    test('fails save and leaves the destination untouched', () {
      final out = p.join(tmp.path, 'x.keyx');
      File(out).writeAsStringSync('before');
      final doc = KeyxDocument.open(_plain);
      doc.resources['b\uDC00\uDC01.png'] = Uint8List.fromList([1]);
      expect(
        () => doc.save(out),
        _stateError(
          "'utf-8' codec can't encode characters in position 6-7: "
          'surrogates not allowed',
        ),
      );
      expect(File(out).readAsStringSync(), 'before');
      expect(tmp.listSync(), hasLength(1));
    });
  });

  group('an integer too large for 64 bits', () {
    const big = '123456789012345678901234567890';

    test('round-trips exactly in unknown keys and preset properties', () {
      final main = _mainWithExtra([], big).replaceFirst(
        '"slides":[{',
        '"slides": [{"zzz": [9223372036854775808, '
            '-9223372036854775809, 1${'0' * 400}], ',
      );
      final bytes = _plainWith({
        'main.json': main,
        'presets.json':
            '[{"identifier":"big","properties":{"a":$big,'
            '"b":[18446744073709551616]}}]',
      });
      final doc = KeyxDocument.fromBytes(bytes);
      expect(doc.payload.extras['zzz'], BigInt.parse(big));
      expect(doc.presets.single.properties!['a'], BigInt.parse(big));
      final saved = doc.toBytes();
      expect(_entry(saved, 'main.json'), contains('"zzz":$big'));
      expect(
        _entry(saved, 'main.json'),
        contains(
          '"zzz":[9223372036854775808,-9223372036854775809,1${'0' * 400}]',
        ),
      );
      expect(
        _entry(saved, 'presets.json'),
        '[{"identifier":"big","properties":{"a":$big,'
        '"b":[18446744073709551616]}}]',
      );
      final back = KeyxDocument.fromBytes(saved);
      expect(back.payload, doc.payload);
      expect(back.payload.extras['zzz'], BigInt.parse(big));
    });

    test(
      'in a float field reads as the nearest double, as Python reads it',
      () {
        final main = _plainMain().replaceFirst(
          '"width":1920.0',
          '"width": $big',
        );
        final doc = KeyxDocument.fromBytes(_plainWith({'main.json': main}));
        expect(doc.payload.slideSize!.width, 1.2345678901234568e+29);
      },
    );

    test('in a float field fails as float_type when no double holds it', () {
      final main = _plainMain().replaceFirst(
        '"width":1920.0',
        '"width": 1${'0' * 400}',
      );
      expect(
        () => KeyxDocument.fromBytes(_plainWith({'main.json': main})),
        throwsA(
          isA<ModelValidationError>().having(
            (e) => [for (final i in e.issues) (i.path, i.type)],
            'issues',
            [('slide_size.width', 'float_type')],
          ),
        ),
      );
    });

    test('in a version map part parses, as Python reads it', () {
      final main = _plainMain().replaceFirst(
        '"version":"1.0"',
        '"version": {"major": 18446744073709551616}',
      );
      expect(
        () => KeyxDocument.fromBytes(_plainWith({'main.json': main})),
        throwsA(
          isA<DocumentVersionError>().having(
            (e) => e.message,
            'message',
            'KeynoteTheme: input declares version 18446744073709551616.0 but '
                'this library implements 1.x. Update this library to a newer '
                'version to read it.',
          ),
        ),
      );
    });

    test('compares exactly in sameJson', () {
      final twoTo63 = BigInt.parse('9223372036854775808');
      expect(sameJson(twoTo63, 9223372036854775808.0), isTrue);
      expect(sameJson(twoTo63 + BigInt.one, 9223372036854775808.0), isFalse);
      expect(sameJson(BigInt.from(3), 3), isTrue);
      expect(
        sameJson([twoTo63], [BigInt.parse('9223372036854775808')]),
        isTrue,
      );
      expect(sameJson(BigInt.one, true), isFalse);
    });
  });

  test('a preset cycle that save reaches throws PresetCycleError', () {
    final out = p.join(tmp.path, 'x.keyx');
    for (final validateResources in [true, false]) {
      final doc = KeyxDocument.open(_plain);
      doc.presets[0].parentIdentifier = 'title_text';
      expect(
        () => doc.save(out, validateResources: validateResources),
        throwsA(
          isA<PresetCycleError>().having(
            (e) => '$e',
            'message',
            "circular preset `parent_identifier` chain at 'title_text'",
          ),
        ),
      );
    }
    expect(tmp.listSync(), isEmpty);
  });

  group('deeply nested JSON', () {
    test('opens as deep as Python reads it, in any part', () {
      for (final (name, json) in [
        ('manifest.json', '{"package_version":"1.0","x":${_nested(9997)}}'),
        (
          'presets.json',
          '[{"identifier":"base_text","properties":{"zzz":'
              '${_nested(9995)}}}]',
        ),
        ('main.json', _mainWithExtra([], _nested(9997))),
      ]) {
        final bytes = _plainWith({name: json});
        final path = p.join(tmp.path, 'deep.keyx');
        File(path).writeAsBytesSync(bytes);
        KeyxDocument.fromBytes(bytes);
        KeyxDocument.open(path);
        KeyxDocument.openLazy(path).close();
      }
    });

    test('one level deeper fails as a malformed part', () {
      for (final (name, json, kind, what) in [
        (
          'manifest.json',
          '{"package_version":"1.0","x":${_nested(9998)}}',
          DocumentPackageErrorKind.malformedJson,
          'array',
        ),
        (
          'presets.json',
          '[{"identifier":"base_text","properties":{"zzz":'
              '${'{"a":' * 9996}1${'}' * 9996}}}]',
          DocumentPackageErrorKind.malformedPresets,
          'object',
        ),
        (
          'main.json',
          _mainWithExtra([], _nested(9998)),
          DocumentPackageErrorKind.malformedJson,
          'array',
        ),
      ]) {
        expect(
          () => KeyxDocument.fromBytes(_plainWith({name: json})),
          throwsA(
            isA<DocumentPackageError>()
                .having((e) => e.kind, 'kind', kind)
                .having(
                  (e) => e.message,
                  'message',
                  '$name: maximum recursion depth exceeded while decoding a '
                      'JSON $what from a unicode string',
                ),
          ),
          reason: name,
        );
      }
    });

    test('presets save back as deep as they were read', () {
      final presets =
          '[{"identifier":"base_text","properties":{"font_name":'
          '"Helvetica Neue","tracking":0.0,"zzz":${_nested(9994)}}}]';
      final doc = KeyxDocument.fromBytes(_plainWith({'presets.json': presets}));
      final out = p.join(tmp.path, 'out.keyx');
      doc.save(out);
      expect(_entry(File(out).readAsBytesSync(), 'presets.json'), presets);
    });

    test("in the payload saves only within Pydantic's depth of 256", () {
      // Each object, list, and value counts one level, from the payload at 1.
      for (final (path, fits) in <(List<Object>, int)>[
        ([], 255),
        (['theme'], 254),
        (['slides', 0], 253),
        (
          [
            'slides',
            0,
            'contents',
            0,
            'object',
            'group',
            'title',
            'paragraph_properties',
            'character_properties',
            'character_fill',
            'color',
            'rgba',
          ],
          243,
        ),
      ]) {
        KeyxDocument.fromBytes(
          _plainWith({'main.json': _mainWithExtra(path, _nested(fits))}),
        ).toBytes();
        KeyxDocument.fromBytes(
          _plainWith({
            'main.json': _mainWithExtra(path, _nested(fits - 1, '1')),
          }),
        ).toBytes();
        final deeper = KeyxDocument.fromBytes(
          _plainWith({'main.json': _mainWithExtra(path, _nested(fits + 1))}),
        );
        expect(
          () => deeper.save(p.join(tmp.path, 'x.keyx')),
          _stateError('Maximum serialization depth exceeded'),
          reason: '$path',
        );
        expect(
          () => deeper.payload.toJson(
            WireContext(presets: PresetRegistry(deeper.presets)),
          ),
          _stateError('Maximum serialization depth exceeded'),
        );
        expect(
          () => validateDocument(deeper),
          throwsA(
            isA<DocumentValueError>().having(
              (e) => e.message,
              'message',
              'Maximum serialization depth exceeded',
            ),
          ),
        );
        final scalar = KeyxDocument.fromBytes(
          _plainWith({'main.json': _mainWithExtra(path, _nested(fits, '1'))}),
        );
        expect(
          scalar.toBytes,
          _stateError('Maximum serialization depth exceeded'),
        );
      }
      expect(tmp.listSync(), isEmpty);
    });

    test('of groups counts toward the same depth', () {
      final main = jsonDecode(_plainMain()) as Map<String, Object?>;
      final contents =
          ((main['slides']! as List<Object?>)[0]!
                  as Map<String, Object?>)['contents']!
              as List<Object?>;
      final slideObject = contents[0]! as Map<String, Object?>;
      final group = slideObject['object']! as Map<String, Object?>;
      Map<String, Object?> wrap(Object? object, int times) {
        var out = object! as Map<String, Object?>;
        for (var i = 0; i < times; i++) {
          out = {
            'group': {
              'children': [out],
              'type_identifier': 'com.apple.apps.content-language.group',
              'version': '1.0',
            },
            'type_identifier': group['type_identifier'],
            'version': group['version'],
          };
        }
        return out;
      }

      String withGroups(int times) {
        slideObject['object'] = wrap(group, times);
        return jsonEncode(main);
      }

      // Upstream saves 79 levels of groups around the fixture's and fails at
      // 80.
      KeyxDocument.fromBytes(_plainWith({'main.json': withGroups(79)}))
          .toBytes();
      expect(
        KeyxDocument.fromBytes(_plainWith({'main.json': withGroups(80)}))
            .toBytes,
        _stateError('Maximum serialization depth exceeded'),
      );
    });
  });
}
