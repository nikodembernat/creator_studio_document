// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/test_indirect_resources.py.

@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:creator_studio_document/creator_studio_document.dart'
    hide Pattern;
import 'package:creator_studio_document/src/core/package.dart';
import 'package:creator_studio_document/validation.dart';
import 'package:test/test.dart';

import 'builders.dart';

Matcher _throwsSaveError(Pattern pattern) => throwsA(
  isA<StateError>().having(
    (e) => e.message,
    'message',
    pattern is String ? contains(pattern) : matches(pattern),
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
  doc.resources['real.mp4'] = Uint8List.fromList([
    0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, //
  ]);
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('validation_res_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a missing indirect resource is rejected '
      '(test_validate_indirect_resource_missing_raises)', () {
    expect(
      () => validateDocument(docWithIndirectImage('missing.png')),
      throwsLookupError(
        "`IndirectResource.filename` 'missing.png' matches no stored resource "
        '(at slides[0].contents[0].object.image.resource.indirect.filename)',
      ),
    );
  });

  test('a present indirect resource passes '
      '(test_validate_indirect_resource_present_passes)', () {
    final doc = docWithIndirectImage('present.png');
    doc.resources['present.png'] = png;
    validateDocument(doc);
  });

  test('the identifier is looked up over the filename '
      '(test_validate_looks_up_identifier_over_filename)', () {
    final doc = docWithIndirectImage('shown.png', identifier: 'stored.png');
    doc.resources['shown.png'] = png;
    expect(
      () => validateDocument(doc),
      throwsLookupError(RegExp(r'stored\.png')),
    );
    doc.resources['stored.png'] = png;
    validateDocument(doc);
  });

  test('the lookup field of a missing resource is named '
      '(test_validate_names_the_lookup_field_of_a_missing_resource)', () {
    final doc = docWithIndirectImage('Photo.png', identifier: 'a1b2.png');
    expect(
      () => validateDocument(doc),
      throwsLookupError(
        RegExp(r"`IndirectResource\.identifier` 'a1b2\.png' matches no"),
      ),
    );
  });

  for (final (i, filename) in ['', '   '].indexed) {
    test('a blank filename is malformed even with an identifier '
        '(test_validate_blank_filename_is_malformed_even_with_identifier'
        '[filename$i])', () {
      final doc = docWithIndirectImage(filename, identifier: 'a1b2.png');
      doc.resources['a1b2.png'] = png;
      expect(
        () => validateDocument(doc),
        throwsValueError(
          "`IndirectResource.filename` '$filename' is empty or blank (at "
          'slides[0].contents[0].object.image.resource.indirect.filename)',
        ),
      );
    });
  }

  test('a padded filename is allowed when an identifier is set '
      '(test_validate_padded_filename_allowed_when_identifier_set)', () {
    final doc = docWithIndirectImage('photo.png ', identifier: 'a1b2.png');
    doc.resources['a1b2.png'] = png;
    validateDocument(doc);
  });

  test('a padded identifier resolves when stored '
      '(test_validate_padded_identifier_resolves_when_stored)', () {
    final doc = docWithIndirectImage('Photo.png', identifier: ' a1b2.png');
    doc.resources[' a1b2.png'] = png;
    validateDocument(doc);
  });

  test('a blank identifier is a malformed reference, not a missing resource '
      '(test_validate_blank_identifier_diagnoses_reference_not_resource)', () {
    final doc = docWithIndirectImage('Photo.png', identifier: ' ');
    expect(
      () => validateDocument(doc),
      throwsValueError(
        RegExp(r'`IndirectResource\.identifier` .* is empty or blank'),
      ),
    );
  });

  test('an empty filename is a malformed reference, not a missing resource '
      '(test_validate_empty_filename_diagnoses_reference_not_resource)', () {
    expect(
      () => validateDocument(docWithIndirectImage('')),
      throwsValueError(
        RegExp(r'`IndirectResource\.filename` .* is empty or blank'),
      ),
    );
  });

  test('a whitespace filename is a malformed reference, not a missing '
      'resource (test_validate_whitespace_filename_diagnoses_reference_not_'
      'resource)', () {
    expect(
      () => validateDocument(docWithIndirectImage('   ')),
      throwsValueError(
        RegExp(r'`IndirectResource\.filename` .* is empty or blank'),
      ),
    );
  });

  test('a padded filename resolves by its exact name '
      '(test_validate_padded_filename_resolves_by_exact_name)', () {
    final doc = docWithIndirectImage('  img.png  ');
    doc.resources['img.png'] = png;
    expect(() => validateDocument(doc), throwsLookupError("'  img.png  '"));
    doc.resources['  img.png  '] = png;
    validateDocument(doc);
  });

  test('a unique ASCII skeleton match is accepted '
      '(test_validate_accepts_a_unique_ascii_skeleton_match)', () {
    final doc = docWithIndirectImage('ÕåÖþ£ƒ');
    doc.resources['写真'] = png;
    validateDocument(doc);
    doc.resources['画像'] = png;
    expect(() => validateDocument(doc), throwsLookupError('ÕåÖþ£ƒ'));
  });

  test('a dangling resource that only a preset reaches is caught '
      '(test_validate_catches_dangling_resource_reached_only_via_preset)', () {
    final doc = _docWithPresetSuppliedPoster('ghost.png');
    final serialized = {
      for (final (_, name) in iterIndirectIdentifiers(
        doc.toMainJson(),
        PresetRegistry(doc.presets),
      ))
        name,
    };
    expect(serialized, {'real.mp4'});
    expect(serialized.every(doc.resources.canResolve), isTrue);
    expect(
      () => validateDocument(doc),
      throwsLookupError(
        "`IndirectResource.filename` 'ghost.png' matches no stored resource "
        '(at slides[0].contents[0].object.movie.poster_image.indirect'
        '.filename)',
      ),
    );
  });

  test('a resource that a preset supplies passes when present '
      '(test_validate_passes_when_preset_supplied_resource_is_present)', () {
    final doc = _docWithPresetSuppliedPoster('poster.png');
    doc.resources['poster.png'] = png;
    validateDocument(doc);
  });

  test('save resolves by identifier, not filename '
      '(test_save_resolves_by_identifier_not_filename)', () {
    final doc = docWithIndirectImage('Photo.png', identifier: 'a1b2.png');
    doc.resources['Photo.png'] = png;
    expect(
      () => doc.save('${tmp.path}/bad.keyx'),
      _throwsSaveError("'a1b2.png' (looked up by identifier)"),
    );
    doc.resources['a1b2.png'] = png;
    doc.save('${tmp.path}/ok.keyx');
  });

  test('save resolves an identifier that a preset supplies '
      '(test_save_resolves_preset_omitted_identifier)', () {
    _docWithIdentifierFromPreset('a1b2.png').save('${tmp.path}/ok.keyx');
    expect(
      () =>
          _docWithIdentifierFromPreset('Photo.png')
              .save('${tmp.path}/bad.keyx'),
      _throwsSaveError('a1b2.png'),
    );
  });

  test('save resolves against the presets as the hooks leave them '
      '(test_save_resolves_against_presets_as_hooks_leave_them)', () {
    final doc = _docWithIdentifierFromPreset('a1b2.png');
    void repoint(Package<Presentation> d, Map<String, Object?> _) {
      d.presets = [
        Preset('img', {'identifier': 'other.png'}),
      ];
    }

    expect(
      () => doc.save('${tmp.path}/bad.keyx', preSaveHooks: [repoint]),
      _throwsSaveError('other.png'),
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
      () => validateDocument(doc),
      throwsValueError(
        'An inherited preset value is invalid. Fix the preset properties. '
        'Validation errors:\n'
        '  at slides.0.contents.0.object.image.resource.indirect.identifier: '
        'Input should be a valid string',
      ),
    );
    expect(
      () => doc.save('${tmp.path}/bad.keyx'),
      _throwsSaveError("'missing.png' (looked up by filename)"),
    );
  });

  test('save reports a missing name once '
      '(test_save_reports_a_missing_name_once)', () {
    final doc = docWithIndirectImage('Photo.png', identifier: 'x.png');
    doc.payload.slides.add(docWithIndirectImage('x.png').payload.slides[0]);
    expect(
      () => doc.save('${tmp.path}/bad.keyx'),
      _throwsSaveError(
        RegExp(r"Data/: 'x\.png' \(looked up by filename and identifier\)$"),
      ),
    );
  });
}
