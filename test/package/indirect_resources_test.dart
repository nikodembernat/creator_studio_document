// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/test_indirect_resources.py, the cases about
// `Package.save` and `_iter_indirect_identifiers`. The cases that exercise
// `validate_document` belong to the validation tests.

@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/src/core/package.dart';
import 'package:test/test.dart';

import 'builders.dart';

Matcher _missing(Object message) => throwsA(
  isA<StateError>().having(
    (e) => e.message,
    'message',
    message is RegExp ? matches(message) : message,
  ),
);

KeyxDocument _docWithPresetSuppliedPoster(String filename) {
  final movie = Movie(
    resource: Resource(indirect: IndirectResource(filename: 'real.mp4')),
    playbackOptions: PlaybackOptions(),
    presetIdentifier: 'poster',
  );
  final doc = KeyxDocument(
    Presentation(
      slideSize: slideSize(),
      slides: [
        Slide(
          contents: [SlideObject(object: CanvasObject(movie: movie))],
        ),
      ],
    ),
    presets: [
      Preset('poster', {
        'poster_image': {
          'indirect': {
            'type_identifier': 'indirect-resource',
            'version': '1.0',
            'filename': filename,
          },
        },
      }),
    ],
  );
  doc.resources['real.mp4'] = Uint8List.fromList([0, 0, 0, 0x18]);
  return doc;
}

KeyxDocument _docWithIdentifierFromPreset(String stored) {
  final doc = docWithIndirectImage(
    'Photo.png',
    identifier: 'a1b2.png',
    presetIdentifier: 'img',
    presets: [
      Preset('img', {'identifier': 'a1b2.png'}),
    ],
  );
  doc.resources[stored] = png;
  return doc;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('indirect_'));
  tearDown(() => tmp.deleteSync(recursive: true));
  String at(String name) => '${tmp.path}/$name';

  test('the save check misses a dangling resource reached only via a preset '
      '(test_validate_catches_dangling_resource_reached_only_via_preset)', () {
    final doc = _docWithPresetSuppliedPoster('ghost.png');
    final references = {
      for (final (_, name) in iterIndirectIdentifiers(
        doc.toMainJson(),
        PresetRegistry(doc.presets),
      ))
        name,
    };
    expect(references, {'real.mp4'});
    expect(references.every(doc.resources.canResolve), isTrue);
  });

  test('save resolves by identifier, not filename '
      '(test_save_resolves_by_identifier_not_filename)', () {
    final doc = docWithIndirectImage('Photo.png', identifier: 'a1b2.png');
    doc.resources['Photo.png'] = png;
    expect(
      () => doc.save(at('bad.keyx')),
      _missing(RegExp(r"'a1b2\.png' \(looked up by identifier\)")),
    );
    doc.resources['a1b2.png'] = png;
    doc.save(at('ok.keyx'));
    expect(File(at('ok.keyx')).existsSync(), isTrue);
  });

  test('save resolves an identifier that the preset supplies '
      '(test_save_resolves_preset_omitted_identifier)', () {
    _docWithIdentifierFromPreset('a1b2.png').save(at('ok.keyx'));
    expect(
      () => _docWithIdentifierFromPreset('Photo.png').save(at('bad.keyx')),
      _missing(RegExp(r'a1b2\.png')),
    );
  });

  test('save resolves against the presets as the hooks leave them '
      '(test_save_resolves_against_presets_as_hooks_leave_them)', () {
    final doc = _docWithIdentifierFromPreset('a1b2.png');
    void repoint(Package<Presentation> d, Map<String, Object?> main) {
      d.presets = [
        Preset('img', {'identifier': 'other.png'}),
      ];
    }

    expect(
      () => doc.save(at('bad.keyx'), preSaveHooks: [repoint]),
      _missing(RegExp(r'other\.png')),
    );
  });

  test('save skips a preset identifier of the wrong type '
      '(test_save_skips_wrong_typed_preset_identifier)', () {
    final doc = docWithIndirectImage(
      'missing.png',
      presetIdentifier: 'img',
      presets: [
        Preset('img', {'identifier': 123}),
      ],
    );
    expect(
      () => doc.save(at('bad.keyx')),
      _missing(RegExp(r"'missing\.png' \(looked up by filename\)")),
    );
  });

  test('save reports a missing name once '
      '(test_save_reports_a_missing_name_once)', () {
    final doc = docWithIndirectImage('Photo.png', identifier: 'x.png');
    doc.payload.slides.add(docWithIndirectImage('x.png').payload.slides[0]);
    expect(
      () => doc.save(at('bad.keyx')),
      _missing(
        RegExp(r"Data/: 'x\.png' \(looked up by filename and identifier\)$"),
      ),
    );
  });

  group('beyond upstream', () {
    test('missing names are listed in code point order', () {
      final doc = docWithIndirectImage('b.png', identifier: 'é.png');
      doc.payload.slides.add(docWithIndirectImage('a.png').payload.slides[0]);
      doc.payload.slides.add(
        docWithIndirectImage('\u{1F600}.png').payload.slides[0],
      );
      doc.payload.slides.add(docWithIndirectImage('�.png').payload.slides[0]);
      expect(
        doc.toBytes,
        _missing(
          "indirect resources missing from Data/: 'a.png' (looked up by "
          "filename), 'é.png' (looked up by identifier), '�.png' "
          "(looked up by filename), '\u{1F600}.png' (looked up by filename)",
        ),
      );
    });

    test('validateResources: false saves a dangling reference', () {
      docWithIndirectImage('missing.png')
          .save(at('d.keyx'), validateResources: false);
      expect(KeyxDocument.open(at('d.keyx')).resources, isEmpty);
    });

    test('the save check accepts the matches bytesFor accepts', () {
      final doc = docWithIndirectImage('café.png');
      doc.resources['café.png'] = png;
      doc.toBytes();
      final mojibake = docWithIndirectImage('ÕåÖþ£ƒ');
      mojibake.resources['写真'] = png;
      mojibake.toBytes();
      mojibake.resources['画像'] = png;
      expect(mojibake.toBytes, _missing(RegExp('ÕåÖþ£ƒ')));
    });

    test('a preset that adopts itself is searched once', () {
      final registry = PresetRegistry([
        Preset('loop', {
          'child': {
            'preset_identifier': 'loop',
            'type_identifier':
                'com.apple.apps.content-language.resource.indirect-resource',
            'filename': 'inner.png',
          },
          'identifier': 'from-preset.png',
        }),
      ]);
      final found = iterIndirectIdentifiers({
        'preset_identifier': 'loop',
        'type_identifier':
            'com.apple.apps.content-language.resource.indirect-resource',
        'filename': 'outer.png',
      }, registry).toList();
      expect(found, [
        ('identifier', 'from-preset.png'),
        ('identifier', 'from-preset.png'),
      ]);
    });

    test('an explicit null identifier falls back to the filename', () {
      final registry = PresetRegistry([
        Preset('p', {'identifier': 'preset.png'}),
      ]);
      expect(
        iterIndirectIdentifiers([
          {
            'preset_identifier': 'p',
            'type_identifier':
                'com.apple.apps.content-language.resource.indirect-resource',
            'identifier': null,
            'filename': 'own.png',
          },
        ], registry).toList(),
        [('filename', 'own.png')],
      );
    });
  });
}
