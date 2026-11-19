// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/test_pre_save_hook.py, the cases about how `Package.save`
// runs its hooks. Upstream passes `validate_document` as the hook; here a
// stand-in hook checks what the package side guarantees, and the validation
// tests cover `validate_document` itself.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:test/test.dart';

import 'builders.dart';

KeyxDocument _validDoc() {
  final doc = docWithIndirectImage('present.png');
  doc.resources['present.png'] = png;
  return doc;
}

// Throws for an indirect resource that `resources` can't resolve, as
// `validate_document` raises `LookupError`.
void _requireResources(Package<Presentation> doc, Map<String, Object?> main) {
  void walk(Object? value) {
    switch (value) {
      case {'filename': final String name} when !doc.resources.canResolve(name):
        throw StateError('${jsonEncode(name)} matches no stored resource');
      case final Map<Object?, Object?> map:
        map.values.forEach(walk);
      case final List<Object?> list:
        list.forEach(walk);
    }
  }

  walk(main);
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('hooks_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a hook that throws aborts the save '
      '(test_hook_violation_aborts_the_save)', () {
    final out = File('${tmp.path}/d.keyx');
    final doc = docWithIndirectImage('missing.png');
    expect(
      () => doc.save(out.path, preSaveHooks: [_requireResources]),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('missing.png'),
        ),
      ),
    );
    expect(out.existsSync(), isFalse);
    expect(tmp.listSync(), isEmpty, reason: 'no temporary file is left');
  });

  test('a clean document writes (test_hook_clean_doc_writes)', () {
    final out = File('${tmp.path}/d.keyx');
    _validDoc().save(out.path, preSaveHooks: [_requireResources]);
    expect(out.statSync().type, FileSystemEntityType.file);
  });

  test('the payload is serialized once for every hook and the write '
      '(test_hook_serializes_the_payload_once)', () {
    final seen = <Map<String, Object?>>[];
    void record(Package<Presentation> _, Map<String, Object?> main) =>
        seen.add(main);
    final out = '${tmp.path}/d.keyx';
    _validDoc().save(out, preSaveHooks: [record, _requireResources, record]);
    expect(seen, hasLength(2));
    expect(identical(seen[0], seen[1]), isTrue);
    final archive = KeyxDocument.open(out);
    expect(
      sameJson(archive.toMainJson(), seen[0]),
      isTrue,
      reason: 'main.json is the value the hooks saw',
    );
  });

  test('a preset cycle that an object adopts stops the save before the hooks '
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
    var called = false;
    expect(
      () => doc.save(
        out.path,
        preSaveHooks: [(_, _) => called = true, _requireResources],
      ),
      throwsA(
        isA<PresetCycleError>().having(
          (e) => '$e',
          'message',
          contains('circular preset'),
        ),
      ),
    );
    expect(called, isFalse);
    expect(out.existsSync(), isFalse);
  });

  group('beyond upstream', () {
    test('hooks run in order, with the package', () {
      final doc = _validDoc();
      final calls = <String>[];
      doc.toBytes(
        preSaveHooks: [
          (d, _) => calls.add('first ${identical(d, doc)}'),
          (d, _) => calls.add('second ${identical(d, doc)}'),
        ],
      );
      expect(calls, ['first true', 'second true']);
    });

    test('the destination check runs before any hook', () {
      final dir = Directory('${tmp.path}/dir.keyx')..createSync();
      var called = false;
      expect(
        () =>
            _validDoc().save(dir.path, preSaveHooks: [(_, _) => called = true]),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            "can't save a package over a directory",
          ),
        ),
      );
      expect(called, isFalse);
      expect(dir.existsSync(), isTrue);
    });
  });
}
