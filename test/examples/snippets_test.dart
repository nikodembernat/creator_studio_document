// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python): docs/snippets/*.py,
// with the output that docs/guide/*.rst shows for them.

/// Runs each file of `doc/snippets/` in a directory that holds the files it
/// reads, checks what it prints and writes, and checks that every Dart code
/// block of `README.md` is one of their regions, so the guide's code runs,
/// and that a block with imports analyzes cleanly on its own.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// The regions of the snippet files: the lines between `// [name]` and
/// `// [/name]`, without the indentation they share.
Map<String, String> _regions() {
  final regions = <String, String>{};
  final start = RegExp(r'^(\s*)// \[([a-z-]+)\]$');
  for (final file in Directory(
    p.join(packageRoot, 'doc', 'snippets'),
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final match = start.firstMatch(lines[i]);
      if (match == null) {
        continue;
      }
      final [indent!, name!] = [match[1], match[2]];
      final end = lines.indexOf('$indent// [/$name]', i);
      expect(end, greaterThan(i), reason: '${file.path}: [$name] is open');
      final body = [
        for (final line in lines.sublist(i + 1, end))
          if (line.startsWith(indent)) line.substring(indent.length) else line,
      ];
      final key = '${p.basenameWithoutExtension(file.path)}/$name';
      regions[key] = body.join('\n');
    }
  }
  return regions;
}

/// Writes a ZIP archive of [entries] to [path].
void _writeZip(String path, Map<String, String> entries) {
  final archive = Archive();
  for (final MapEntry(key: name, value: text) in entries.entries) {
    archive.add(ArchiveFile.bytes(name, Uint8List.fromList(utf8.encode(text))));
  }
  File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
}

/// The Dart code blocks of `README.md`.
List<String> _readmeBlocks() {
  final readme = File(p.join(packageRoot, 'README.md')).readAsStringSync();
  return RegExp(
    r'^```dart\n(.*?)^```$',
    multiLine: true,
    dotAll: true,
  ).allMatches(readme).map((m) => m[1]!).toList();
}

void main() {
  test('getting_started.dart creates and edits hello.keyx', () async {
    final dir = tempDir();
    final result = await runScript(
      'doc/snippets/getting_started.dart',
      const [],
      workingDirectory: dir,
    );
    expect(result, succeeded, reason: '${result.stderr}');

    final hello = expectValidRoundTrip(p.join(dir, 'hello.keyx'));
    final title = hello.presentation.slides.single.contents!.single.object;
    expect(title.textbox?.text?.string, 'Hello, Keynote');

    final edited = expectValidRoundTrip(p.join(dir, 'edited.keyx'));
    final [first, added] = edited.presentation.slides;
    expect(first.note?.string, 'Welcome everyone, then move on.');
    expect(first.contents, isEmpty);
    expect(added.contents, isNull);
  });

  test('adding_objects.dart builds every kind of content', () async {
    final dir = tempDir();
    copyFixture('sample.keyx', dir, as: 'presentation.keyx');
    copyFixture('photo_placeholder.png', dir, as: 'cover.png');
    final result = await runScript(
      'doc/snippets/adding_objects.dart',
      const [],
      workingDirectory: dir,
    );
    expect(result, succeeded, reason: '${result.stderr}');
    expect(outputLines(result), [
      startsWith('solid Color(rgba: RGBA(red: 0.8'),
    ]);

    final doc = expectValidRoundTrip(p.join(dir, 'objects.keyx'));
    final slides = doc.presentation.slides;
    final [..., texts, objects] = slides;
    expect(
      [for (final o in texts.contents!) o.object.textbox?.text?.unionPrimary()],
      [
        isA<TextStringCase>(),
        isA<TextTextRunsCase>(),
        isA<TextParagraphsCase>(),
      ],
    );
    expect(
      [for (final o in objects.contents!) o.object.unionPrimaryName()],
      ['shape', 'image', 'table', 'chart', 'connectionLine'],
    );
    final image = objects.contents![1].object.image!;
    final name = image.resource.indirect!.identifier!;
    expect(
      doc.resources[name],
      File(p.join(dir, 'cover.png')).readAsBytesSync(),
    );
    final table = objects.contents![2].object.table!;
    expect(table.content![0].cells![1].unformattedValue?.number, 41);

    final styled = expectValidRoundTrip(p.join(dir, 'styled.keyx'));
    final registry = PresetRegistry(styled.presets);
    expect(registry.resolvedProperties('title'), {
      'font_name': 'Helvetica Neue',
      'font_size': 48,
      'bold': true,
    });
  });

  test('authoring.dart prints the layouts and builds slides', () async {
    final dir = tempDir();
    copyFixture('Tidal_en.keyx', dir, as: 'themed.keyx');
    copyFixture('photo_placeholder.png', dir, as: 'cover.png');
    final result = await runScript(
      'doc/snippets/authoring.dart',
      const [],
      workingDirectory: dir,
    );
    expect(result, succeeded, reason: '${result.stderr}');
    // Part of the output that the guide shows.
    expect(
      outputLines(result),
      containsAllInOrder([
        'Title [TITLE, Subtitle]',
        'Title & Bullets [TITLE, BODY, Presentation Name, SLIDE_NUMBER]',
        'Title, Bullets & Photo [TITLE, BODY, Media]',
        'Quote [Text, Text-1]',
        'Blank []',
        'Helvetica Neue 46',
      ]),
    );

    final slides = expectValidRoundTrip(p.join(dir, 'slides.keyx'));
    final [..., bullets, photo] = slides.presentation.slides;
    expect(bullets.layout, 'Title & Bullets');
    expect(photo.layout, 'Title, Bullets & Photo');
    expect(slides.resources.keys, contains('cover.png'));

    final built = expectValidRoundTrip(p.join(dir, 'presentation.keyx'));
    expect(built.presentation.slides, hasLength(2));
    expect(
      [for (final s in built.presentation.slides) s.layout],
      ['Title & Bullets', 'Title & Bullets'],
    );
  });

  test('navigation.dart prints the text and reads lazily', () async {
    final dir = tempDir();
    copyFixture('Tidal_en.keyx', dir, as: 'presentation.keyx');
    copyFixture('Tidal_en.keyx', dir, as: 'big-presentation.keyx');
    final result = await runScript(
      'doc/snippets/navigation.dart',
      const [],
      workingDirectory: dir,
    );
    expect(result, succeeded, reason: '${result.stderr}');
    final lines = outputLines(result);
    // The output that the guide shows for the first region.
    expect(lines.take(8), [
      '1 "A theme built for testing, not for sale"',
      '2 "Example Company"',
      '2 " · Confidential"',
      '3 "#"',
      '7 "Photo caption sample"',
      '8 "Testing is the ultimate confidence."',
      '8 "A. Synthetic Author"',
      '11 "Second line"',
    ]);
    final size = KeyxDocument.open(p.join(dir, 'big-presentation.keyx'))
        .resources['sample_photo.jpg']!
        .length;
    // The captions, then the lazily opened document.
    expect(lines.skip(lines.length - 3), [
      '7 "Photo caption sample"',
      '16',
      '$size bytes',
    ]);
  });

  test('validation.dart reports each error and validates', () async {
    final dir = tempDir();
    copyFixture('sample.keyx', dir, as: 'presentation.keyx');
    File(p.join(dir, 'not-a-presentation.keyx')).writeAsStringSync('hello');
    _writeZip(p.join(dir, 'bad-models.keyx'), {'main.json': '{}'});
    _writeZip(p.join(dir, 'too-new.keyx'), {
      'main.json': '{"slides": [{}]}',
      'manifest.json': '{"package_version": "99.0"}',
    });
    _writeZip(p.join(dir, 'no-main.keyx'), {
      'manifest.json': '{"package_version": "1.0"}',
    });

    final result = await runScript('doc/snippets/validation.dart', const [
      'not-a-presentation.keyx',
      'missing.keyx',
      'bad-models.keyx',
      'too-new.keyx',
      'no-main.keyx',
    ], workingDirectory: dir);
    expect(result, succeeded, reason: '${result.stderr}');
    expect(outputLines(result), [
      "not-a-presentation.keyx isn't a document.",
      startsWith("Can't read missing.keyx: "),
      "bad-models.keyx doesn't match this library's models.",
      'too-new.keyx needs a newer version of the library.',
      'no-main.keyx is corrupt (missing_main_file).',
    ]);

    final out = expectValidRoundTrip(p.join(dir, 'out.keyx'));
    expect(
      out.presentation.slides.first.note?.string,
      'Checked before saving.',
    );
  });

  test('prefix.dart uses the models through a prefix', () async {
    final result = await runScript(
      'doc/snippets/prefix.dart',
      const [],
      workingDirectory: tempDir(),
    );
    expect(result, succeeded, reason: '${result.stderr}');
    expect(outputLines(result), ['Hello 0:00:05.000000']);
  });

  test('every Dart code block of README.md is a snippet region', () {
    final regions = _regions();
    expect(regions, hasLength(23));
    final blocks = _readmeBlocks();
    expect(blocks, isNotEmpty);
    final function = RegExp(r'^void \w+\(.*\) \{$');
    for (final block in blocks) {
      // A block may start with the imports that its region's file has, and
      // hold its region in a function, as a complete program does.
      var lines = block
          .trimRight()
          .split('\n')
          .skipWhile((l) => l.startsWith('import ') || l.isEmpty)
          .toList();
      if (function.hasMatch(lines.first) && lines.last == '}') {
        lines = [
          for (final l in lines.sublist(1, lines.length - 1))
            if (l.startsWith('  ')) l.substring(2) else l,
        ];
      }
      final code = lines.join('\n');
      expect(
        regions.values,
        contains(code),
        reason: 'README.md block is no snippet region:\n$code',
      );
    }
  });

  test('every README.md block with imports analyzes without issues', () async {
    // A block with imports is a whole file, such as a program a reader
    // copies, so it must hold up on its own, not only as a snippet region.
    final files = [
      for (final block in _readmeBlocks())
        if (block.startsWith('import ')) block,
    ];
    expect(files, hasLength(6));
    // Inside the package, so that the files resolve its imports and get its
    // analysis options.
    final dir = Directory(p.join(packageRoot, '.dart_tool'))
        .createTempSync('readme_blocks_');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final (i, block) in files.indexed) {
      File(p.join(dir.path, 'block_$i.dart')).writeAsStringSync(block);
    }
    final result = await Process.run(Platform.resolvedExecutable, [
      'analyze',
      dir.path,
    ], workingDirectory: packageRoot);
    expect(result, succeeded, reason: '${result.stdout}${result.stderr}');
    expect('${result.stdout}', contains('No issues found!'));
  });

  test('README.md states the SDK minimum that pubspec.yaml requires', () {
    final pubspec = File(p.join(packageRoot, 'pubspec.yaml'))
        .readAsStringSync();
    final sdk = RegExp(
      r'^  sdk: \^(\S+)$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(sdk, isNotNull);
    final readme = File(p.join(packageRoot, 'README.md')).readAsStringSync();
    expect(readme, contains('The library needs Dart ${sdk![1]} or later.'));
  });

  test("README.md maps upstream's exceptions for the authoring API", () {
    final readme = File(p.join(packageRoot, 'README.md')).readAsStringSync();
    for (final mapping in [
      '`KeyError` is `ArgumentError`',
      '`TypeError` is `UnsupportedError`',
      '`ValueError` is `ArgumentError`',
    ]) {
      expect(readme, contains(mapping));
    }
  });
}
