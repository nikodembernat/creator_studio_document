// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python): the behavior that
// the docstrings and comments of `Package` and `KeyxDocument` in
// core/package.py and core/keyx.py describe. The outcomes of unusual and
// malformed archives, checked against upstream, are in
// differential_cases_test.dart.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'builders.dart';

Matcher _packageError(DocumentPackageErrorKind kind, [Object? message]) =>
    throwsA(
      isA<DocumentPackageError>()
          .having((e) => e.kind, 'kind', kind)
          .having((e) => e.message, 'message', message ?? anything),
    );

Uint8List _zip(Map<String, String> entries) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in entries.entries) {
    archive.add(ArchiveFile.bytes(key, utf8.encode(value)));
  }
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  final fixtures =
      Directory('test/fixtures')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.keyx'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('package_'));
  tearDown(() => tmp.deleteSync(recursive: true));
  String at(String name) => p.join(tmp.path, name);

  group('fixtures', () {
    for (final file in fixtures) {
      final name = p.basename(file.path);
      test('$name opens eagerly and lazily alike, and survives a save', () {
        final eager = KeyxDocument.open(file.path);
        final lazy = KeyxDocument.openLazy(file.path);
        addTearDown(lazy.close);
        final fromBytes = KeyxDocument.fromBytes(file.readAsBytesSync());
        expect(identical(eager.presentation, eager.payload), isTrue);
        expect(lazy.payload, eager.payload);
        expect(fromBytes.payload, eager.payload);
        expect(lazy.resources.keys, eager.resources.keys);
        for (final key in eager.resources.keys) {
          expect(lazy.resources[key], eager.resources[key]);
        }
        eager.save(at(name));
        final again = KeyxDocument.open(at(name));
        expect(again.payload, eager.payload);
        expect(sameJson(again.toMainJson(), eager.toMainJson()), isTrue);
        expect(
          [for (final p in again.presets) p.toJson()],
          [for (final p in eager.presets) p.toJson()],
        );
        expect(again.resources.keys, eager.resources.keys);
        // The bytes API writes what save writes, apart from timestamps.
        final viaBytes = KeyxDocument.fromBytes(eager.toBytes());
        expect(viaBytes.payload, eager.payload);
      });
    }
  });

  group('constructing', () {
    test('defaults: no presets, a default manifest, no resources', () {
      final doc = emptyDoc();
      expect(doc.presets, isEmpty);
      expect(doc.manifest.packageVersion, isNull);
      expect(doc.resources, isEmpty);
      expect(doc.resources.isLazy, isFalse);
    });

    test('a package of any root model takes its schema', () {
      final pkg = Package(
        Presentation(slides: [Slide()]),
        resources: {'a.png': png},
      );
      final read = Package.fromBytes(
        pkg.toBytes(),
        payloadModel: Presentation.schema,
      );
      expect(read.payload, pkg.payload);
      expect(read.resources['a.png'], png);
    });

    test("the resources read from bytes don't share the caller's buffer", () {
      final buffer = File('test/fixtures/package/stored.keyx')
          .readAsBytesSync();
      final doc = KeyxDocument.fromBytes(buffer);
      final hero = doc.resources['hero.png']!;
      final before = List.of(hero);
      expect(before.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(hero.buffer, isNot(same(buffer.buffer)));
      expect(hero.lengthInBytes, hero.buffer.lengthInBytes);
      buffer.fillRange(0, buffer.length, 0);
      expect(doc.resources['hero.png'], before);
      hero[0] = 0;
      expect(buffer.every((b) => b == 0), isTrue);
    });

    test('the resources are copied', () {
      final resources = {'a.png': png};
      final doc = KeyxDocument(
        Presentation(slides: [Slide()]),
        resources: resources,
      );
      resources['b.png'] = png;
      expect(doc.resources.keys, ['a.png']);
    });
  });

  group('saving', () {
    test('writes the parts as compact UTF-8 JSON, then the resources', () {
      final doc = docWithIndirectImage('héro.png')
        ..resources['héro.png'] = png
        ..manifest = Manifest(packageVersion: '1.7');
      doc.presets.add(Preset('é', {'note': 'ünïcode', 'n': 1.0}));
      final archive = ZipDecoder().decodeBytes(doc.toBytes());
      expect(
        [for (final f in archive.files) f.name],
        ['main.json', 'manifest.json', 'presets.json', 'Data/héro.png'],
      );
      String text(String name) => utf8.decode(archive.findFile(name)!.content);
      expect(text('manifest.json'), '{"package_version":"1.0"}');
      expect(
        text('presets.json'),
        '[{"identifier":"é","properties":{"note":"ünïcode","n":1.0}}]',
      );
      expect(text('main.json'), isNot(contains(' ')));
      expect(text('main.json'), contains('"filename":"héro.png"'));
      expect(archive.findFile('Data/héro.png')!.content, png);
    });

    test(
      'replaces the destination atomically and leaves no temporary file',
      () {
        final out = File(at('d.keyx'))..writeAsStringSync('old');
        emptyDoc().save(out.path);
        expect(KeyxDocument.open(out.path).payload.slides, hasLength(1));
        expect(tmp.listSync().map((e) => p.basename(e.path)), ['d.keyx']);
      },
    );

    test('a failed save leaves the destination untouched', () {
      final out = File(at('d.keyx'))..writeAsStringSync('old');
      expect(
        () => docWithIndirectImage('missing.png').save(out.path),
        throwsStateError,
      );
      expect(out.readAsStringSync(), 'old');
      expect(tmp.listSync(), hasLength(1));
    });

    test('a missing parent directory names the destination', () {
      final out = at('no/such/dir/d.keyx');
      expect(
        () => emptyDoc().save(out),
        // Upstream keeps the type, `FileNotFoundError`, as it names `path`.
        throwsA(
          isA<PathNotFoundException>()
              .having((e) => e.path, 'path', out)
              .having((e) => e.osError?.errorCode, 'errno', isNonZero),
        ),
      );
      expect(tmp.listSync(), isEmpty);
    });

    test(
      'a read-only directory names the destination, as a permission error',
      () {
        final dir = Directory(at('ro'))..createSync();
        Process.runSync('chmod', ['555', dir.path]);
        addTearDown(() => Process.runSync('chmod', ['755', dir.path]));
        final out = p.join(dir.path, 'd.keyx');
        expect(
          () => emptyDoc().save(out),
          // Upstream keeps the type, `PermissionError`, as it names `path`.
          throwsA(
            isA<PathAccessException>().having((e) => e.path, 'path', out),
          ),
        );
        expect(dir.listSync(), isEmpty);
      },
      testOn: 'posix',
      skip: Platform.environment['USER'] == 'root'
          ? 'root writes to a read-only directory'
          : false,
    );

    test('a directory destination is refused and kept', () {
      final dir = Directory(at('dir.keyx'))..createSync();
      expect(
        () => emptyDoc().save(dir.path),
        throwsA(
          isA<FileSystemException>()
              .having(
                (e) => e.message,
                'message',
                "can't save a package over a directory",
              )
              .having((e) => e.path, 'path', dir.path),
        ),
      );
      expect(dir.existsSync(), isTrue);
    });

    test('a lone surrogate in the payload fails to encode', () {
      final doc = emptyDoc();
      doc.payload.slides.single.extras['x'] = 'a\ud800';
      expect(
        doc.toBytes,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(r"can't encode character '\ud800'"),
          ),
        ),
      );
    });

    test('a closed lazy package saves only what it read', () {
      emptyDoc()
        ..resources['a.png'] = png
        ..resources['b.png'] = png
        ..save(at('src.keyx'));
      final lazy = KeyxDocument.openLazy(at('src.keyx'));
      expect(lazy.resources['a.png'], png);
      lazy
        ..close()
        ..save(at('out.keyx'));
      expect(KeyxDocument.open(at('out.keyx')).resources.keys, ['a.png']);
    });

    test('a lazy package can be saved over its own file', () {
      emptyDoc()
        ..resources['a.png'] = png
        ..save(at('d.keyx'));
      final lazy = KeyxDocument.openLazy(at('d.keyx'));
      addTearDown(lazy.close);
      lazy
        ..resources['b.png'] = png
        ..save(at('d.keyx'));
      expect(KeyxDocument.open(at('d.keyx')).resources.keys.toList()..sort(), [
        'a.png',
        'b.png',
      ]);
    });

    test('close is safe on an eager package, and repeatable', () {
      emptyDoc()
        ..close()
        ..close();
    });
  });

  group('opening', () {
    test('a path that does not exist is a file system error', () {
      for (final open in [KeyxDocument.open, KeyxDocument.openLazy]) {
        expect(
          () => open(at('missing.keyx')),
          throwsA(isA<FileSystemException>()),
        );
      }
    });

    test('messages name the path, or the bytes', () {
      final path = at('junk.keyx');
      File(path).writeAsStringSync('not a zip');
      expect(
        () => KeyxDocument.open(path),
        _packageError(
          DocumentPackageErrorKind.notAPackage,
          "'$path' isn't a ZIP package",
        ),
      );
      expect(
        () => KeyxDocument.fromBytes(utf8.encode('not a zip')),
        _packageError(
          DocumentPackageErrorKind.notAPackage,
          "the bytes isn't a ZIP package",
        ),
      );
      expect(
        () => KeyxDocument.fromBytes(
          Uint8List.fromList([0x50, 0x4b, 3, 4, 0, 0]),
        ),
        _packageError(
          DocumentPackageErrorKind.malformedArchive,
          "the bytes has no ZIP central directory, so it's truncated",
        ),
      );
      final noMain = at('nomain.keyx');
      File(noMain).writeAsBytesSync(_zip({'presets.json': '[]'}));
      expect(
        () => KeyxDocument.openLazy(noMain),
        _packageError(
          DocumentPackageErrorKind.missingMainFile,
          "'$noMain': main.json is required",
        ),
      );
      expect(
        () => KeyxDocument.fromBytes(_zip({'presets.json': '[]'})),
        _packageError(
          DocumentPackageErrorKind.missingMainFile,
          'main.json is required',
        ),
      );
    });

    test('a JSON error reads as Python words it', () {
      expect(
        () => KeyxDocument.fromBytes(_zip({'main.json': '{"a" 1}'})),
        _packageError(
          DocumentPackageErrorKind.malformedJson,
          "main.json: Expecting ':' delimiter: line 1 column 6 (char 5)",
        ),
      );
      expect(
        () => KeyxDocument.fromBytes(
          _zip({'main.json': '{}', 'presets.json': '{}'}),
        ),
        _packageError(
          DocumentPackageErrorKind.malformedPresets,
          "presets.json isn't a JSON array",
        ),
      );
      expect(
        () => KeyxDocument.fromBytes(
          _zip({'main.json': '{}', 'presets.json': '[{"identifier": "é"}]'}),
        ),
        _packageError(
          DocumentPackageErrorKind.malformedPresets,
          "presets.json: no `properties` in preset 'é'",
        ),
      );
    });

    test('a version error names the path', () {
      final path = at('v2.keyx');
      File(path).writeAsBytesSync(
        _zip({
          'main.json': '{}',
          'manifest.json': '{"package_version": "2.1"}',
        }),
      );
      expect(
        () => KeyxDocument.open(path),
        throwsA(
          isA<DocumentVersionError>().having(
            (e) => e.message,
            'message',
            "'$path': `package_version` '2.1' (major 2) exceeds supported "
                'major 1. Update this library to a newer version to read it.',
          ),
        ),
      );
    });

    test('a package_version integer beyond 64 bits keeps its digits', () {
      // Outcomes checked against upstream, which reads the exact integer.
      final main = utf8.decode(
        ZipDecoder()
            .decodeBytes(File('test/fixtures/sample.keyx').readAsBytesSync())
            .findFile('main.json')!
            .content,
      );
      final path = at('big.keyx');
      for (final (manifest, spelled, major) in [
        (
          '{"package_version":100000000000000000000}',
          '100000000000000000000',
          '100000000000000000000',
        ),
        (
          '{"package_version":9223372036854775808}',
          '9223372036854775808',
          '9223372036854775808',
        ),
        (
          '{"package_version":{"major":100000000000000000000,"minor":0}}',
          '100000000000000000000.0',
          '100000000000000000000',
        ),
        (
          '{"package_version":"100000000000000000000"}',
          '100000000000000000000',
          '100000000000000000000',
        ),
      ]) {
        final bytes = _zip({'main.json': main, 'manifest.json': manifest});
        File(path).writeAsBytesSync(bytes);
        final message =
            "`package_version` '$spelled' (major $major) exceeds supported "
            'major 1. Update this library to a newer version to read it.';
        Matcher versionError(String text) => throwsA(
          isA<DocumentVersionError>().having((e) => e.message, 'message', text),
        );
        expect(
          () => KeyxDocument.fromBytes(bytes),
          versionError(message),
          reason: manifest,
        );
        expect(
          () => KeyxDocument.open(path),
          versionError("'$path': $message"),
        );
        expect(
          () => KeyxDocument.openLazy(path),
          versionError("'$path': $message"),
        );
      }
      for (final (manifest, version) in [
        (
          '{"package_version":{"major":1,"minor":100000000000000000000}}',
          '1.100000000000000000000',
        ),
        (
          '{"package_version":-100000000000000000000}',
          '-100000000000000000000',
        ),
        ('{"package_version":1e20}', '1e+20'),
      ]) {
        final doc = KeyxDocument.fromBytes(
          _zip({'main.json': main, 'manifest.json': manifest}),
        );
        expect(doc.manifest.packageVersion, version, reason: manifest);
      }
    });

    test('a payload that does not match the model is a validation error', () {
      expect(
        () => KeyxDocument.fromBytes(_zip({'main.json': '{"slides": []}'})),
        throwsA(isA<ModelValidationError>()),
      );
    });

    test('a corrupt member names the re-zip evidence', () {
      final good = _zip({
        'Deck/main.json': '{}',
        '__MACOSX/Deck/._main.json': 'x',
      });
      // Flip the stored CRC of the first entry in the central directory.
      final bytes = Uint8List.fromList(good);
      final view = ByteData.sublistView(bytes);
      for (var i = 0; i < bytes.length - 4; i++) {
        if (view.getUint32(i, Endian.little) == 0x02014b50) {
          bytes[i + 16] ^= 1;
          break;
        }
      }
      expect(
        () => KeyxDocument.fromBytes(bytes),
        _packageError(
          DocumentPackageErrorKind.malformedArchive,
          "Bad CRC-32 for file 'Deck/main.json' (archive was re-zipped: "
          "entries live under 'Deck/', not at the archive root and __MACOSX "
          'sidecars present)',
        ),
      );
    });

    test('resources come only from flat names under Data/', () {
      final doc = KeyxDocument.fromBytes(
        _zip({
          'main.json': '{"slides": [{}]}',
          'Data/a.png': 'a',
          'Data/sub/b.png': 'b',
          'Data/..': 'c',
          'Other/c.png': 'c',
          'd.png': 'd',
        }),
      );
      expect(doc.resources.keys, ['a.png']);
    });
  });
}
