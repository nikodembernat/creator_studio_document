// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/test_pre_save_hook.py.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/src/validation/resolve.dart';
import 'package:creator_studio_document/src/validation/validate_document.dart'
    show resolvePhase;
import 'package:creator_studio_document/validation.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'builders.dart';

KeyxDocument _validDoc() {
  final doc = docWithIndirectImage('present.png');
  doc.resources['present.png'] = png;
  return doc;
}

(String, String, String, String) _snapshot(KeyxDocument doc) => (
  jsonEncode(doc.toMainJson()),
  jsonEncode([for (final p in doc.presets) p.toJson()]),
  jsonEncode(doc.manifest.toJson()),
  jsonEncode(doc.resources.keys.toList()..sort()),
);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('validation_hook_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a violation aborts the save (test_hook_violation_aborts_the_save)', () {
    final out = File('${tmp.path}/d.keyx');
    final doc = docWithIndirectImage('missing.png');
    expect(
      () => doc.save(out.path, preSaveHooks: [validateDocument]),
      throwsLookupError(RegExp(r'missing\.png')),
    );
    expect(out.existsSync(), isFalse);
  });

  test('a clean document writes (test_hook_clean_doc_writes)', () {
    final out = File('${tmp.path}/d.keyx');
    _validDoc().save(out.path, preSaveHooks: [validateDocument]);
    expect(out.statSync().type, FileSystemEntityType.file);
  });

  // Upstream counts the calls of a patched `Presentation.model_dump`. Dart
  // can't patch a method, so this counts what each encoding of an edited
  // model decoded at a newer version logs once.
  test('the hook serializes the payload once '
      '(test_hook_serializes_the_payload_once)', () {
    final doc = _validDoc();
    final slide = Slide.fromJson({'version': '1.5', 'future_key': 1})
      ..identifier = 'edited';
    doc.payload.slides.add(slide);
    var encodings = 0;
    final subscription = Logger.root.onRecord.listen((r) {
      if (r.message.contains('edited after decoding')) {
        encodings++;
      }
    });
    addTearDown(subscription.cancel);
    doc.save('${tmp.path}/d.keyx', preSaveHooks: [validateDocument]);
    expect(encodings, 1);
    validateDocument(doc);
    expect(encodings, 2, reason: 'without the JSON, it encodes the payload');
  });

  test("the hook doesn't mutate the document "
      '(test_the_hook_does_not_mutate_the_document)', () {
    final doc = _validDoc();
    final before = _snapshot(doc);
    validateDocument(doc);
    expect(_snapshot(doc), before);
  });

  test("the hook doesn't mutate the JSON passed in "
      '(test_the_hook_does_not_mutate_the_main_json_passed_in)', () {
    final doc = _validDoc();
    final main = doc.toMainJson();
    final frozen = jsonDecode(jsonEncode(main));
    validateDocument(doc, main);
    expect(main, frozen);
  });

  test('a phase that mutates the JSON is caught '
      '(test_a_phase_that_mutates_main_json_is_caught)', () {
    resolvePhase = <T extends ObjectModel>(doc, main) {
      main['injected'] = 1;
      return resolveProperties(doc, main);
    };
    addTearDown(() => resolvePhase = resolveProperties);
    final doc = _validDoc();
    expect(
      () => validateDocument(doc, doc.toMainJson()),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          '`main_json` changed during `validateDocument`. This is a defect '
              'in `validateDocument`.',
        ),
      ),
    );
  });

  test("the self-check is skipped when the JSON isn't passed in "
      '(test_the_self_check_is_skipped_when_main_json_is_not_passed_in)', () {
    resolvePhase = <T extends ObjectModel>(doc, main) {
      main['injected'] = 1;
      return resolveProperties(doc, main);
    };
    addTearDown(() => resolvePhase = resolveProperties);
    validateDocument(_validDoc());
  });

  test('the save reports a preset cycle that an object adopts '
      '(test_hook_reports_a_preset_cycle_an_object_adopts)', () {
    final out = File('${tmp.path}/d.keyx');
    final slide = Slide(
      contents: [
        SlideObject(
          object: CanvasObject(shape: Shape(presetIdentifier: 'a')),
        ),
      ],
    );
    final doc = KeyxDocument(
      Presentation(slideSize: slideSize(), slides: [slide]),
      presets: [
        Preset('a', {}, parentIdentifier: 'b'),
        Preset('b', {}, parentIdentifier: 'a'),
      ],
    );
    expect(
      () => doc.save(out.path, preSaveHooks: [validateDocument]),
      throwsA(
        isA<PresetCycleError>().having(
          (e) => '$e',
          'toString()',
          contains('circular preset'),
        ),
      ),
    );
    expect(out.existsSync(), isFalse);
  });

  // Upstream appends a string to `slides`, which Pydantic's serializer
  // rejects before the hook runs, so only a direct call names the path. A
  // Dart list of slides can't hold a string, and the encoder writes an
  // in-place change that a typed list can hold, so the hook reports it, with
  // its path, as a direct call does.
  test('an in-place change has a path, directly and through the hook '
      '(test_an_in_place_append_has_a_path_only_when_validated_directly)', () {
    final doc = emptyDoc();
    expect(
      () => (doc.payload.slides as List<Object?>).add('x'),
      throwsA(isA<TypeError>()),
    );
    doc.payload.slides.clear();
    expect(() => validateDocument(doc), throwsValueError('at slides'));
    expect(
      () => doc.save('${tmp.path}/d.keyx', preSaveHooks: [validateDocument]),
      throwsValueError('at slides'),
    );
  });

  // Upstream's dump raises `PydanticSerializationError`, a `ValueError`, for
  // a union whose every case was cleared in place, which field-type
  // validation lets through. A save encodes before the hooks run, so it
  // throws the encoder's `StateError`, as upstream raises the same error.
  test('a union with no case set is a value error, unless the save encodes '
      'it first', () {
    for (final (stroke, clear) in <(Stroke, void Function(Stroke))>[
      (Stroke(empty: true), (s) => s.empty = false),
      (Stroke(line: Line(width: 1)), (s) => s.line = null),
    ]) {
      final doc = KeyxDocument(
        Presentation(
          slideSize: slideSize(),
          slides: [
            Slide(
              contents: [
                SlideObject(
                  object: CanvasObject(shape: Shape(stroke: stroke)),
                ),
              ],
            ),
          ],
        ),
      );
      clear(stroke);
      const message =
          "Error calling function `_wire_encode`: ValueError: Stroke: can't "
          'encode with no case set';
      expect(
        () => validateDocument(doc),
        throwsA(
          isA<DocumentValueError>()
              .having((e) => e.message, 'message', message)
              .having((e) => e.cause, 'cause', isStateError),
        ),
      );
      expect(
        () => doc.toBytes(preSaveHooks: [validateDocument]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            "Stroke: can't encode with no case set",
          ),
        ),
      );
    }
  });

  test('the hook runs on toBytes too', () {
    expect(
      () =>
          docWithIndirectImage('missing.png')
              .toBytes(preSaveHooks: [validateDocument]),
      throwsLookupError('missing.png'),
    );
    expect(_validDoc().toBytes(preSaveHooks: [validateDocument]), isNotEmpty);
  });

  test('the hook fits a package of any payload type', () {
    final doc = Package<Presentation>(emptyDoc().payload);
    final List<PreSaveHook<Presentation>> hooks = [validateDocument];
    expect(doc.toBytes(preSaveHooks: hooks), isNotEmpty);
  });
}
