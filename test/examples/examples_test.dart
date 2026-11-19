// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python): the doctest of
// src/creator_studio_doc_format/examples/authoring.py, and the behavior of
// every script in src/creator_studio_doc_format/examples/.

/// Runs every script in `example/` as `dart example/<name>.dart` does, and
/// checks that each document it writes passes `validateDocument`, round-trips,
/// and matches what the upstream script writes.
///
/// `expected/<name>.zip` holds the JSON entries of the document that the
/// upstream script of the same name writes, from creator-studio-doc-format
/// 0.1.0, run as
///
/// ```sh
/// python -m creator_studio_doc_format.examples.<name> [input] <output>
/// ```
///
/// with the fixtures as input for `authoring` and `inspection`.
/// `expected/hello.zip` is the document of upstream's README quick start.
/// `tool/make_example_expected.py` writes them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:creator_studio_document/authoring.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../example/inspection.dart' as inspection;
import 'support.dart';

/// The examples that build a document from scratch, with the resources each
/// one stores.
const _builders = {
  'basics': {'hero.png': 'photo_placeholder.png'},
  'charts': <String, String>{},
  'hyperlinks': <String, String>{},
  'image_decoration': {'photo.png': 'photo_placeholder.png'},
  'lists': {'bullet.png': 'bullet.png'},
  'shapes_and_lines': <String, String>{},
  'spreadsheets': <String, String>{},
  'tables': <String, String>{},
};

final _uuid = RegExp(
  '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}',
);

/// Replaces each random identifier of [entries] by its order of first
/// appearance, across the entries in name order.
Map<String, String> _normalizeUuids(Map<String, String> entries) {
  final seen = <String, String>{};
  return {
    for (final name in entries.keys.toList()..sort())
      name: entries[name]!.replaceAllMapped(
        _uuid,
        (m) => seen.putIfAbsent(m[0]!, () => 'UUID-${seen.length}'),
      ),
  };
}

/// Checks that the JSON entries of the document at [path] are the ones the
/// upstream script [name] writes.
///
/// [adjust] changes the decoded upstream JSON of an entry where the port
/// deliberately differs; the entries are then compared as JSON rather than
/// as text.
void _expectMatchesUpstream(
  String path,
  String name, {
  bool randomIdentifiers = false,
  Map<String, void Function(Object? json)> adjust = const {},
}) {
  final expectedFile = File(
    p.join(packageRoot, 'test', 'examples', 'expected', '$name.zip'),
  );
  Map<String, String> jsonEntries(List<int> bytes) => {
    for (final MapEntry(:key, :value) in zipEntries(bytes).entries)
      if (key.endsWith('.json')) key: utf8.decode(value),
  };
  var expected = jsonEntries(expectedFile.readAsBytesSync());
  var actual = jsonEntries(File(path).readAsBytesSync());
  if (randomIdentifiers) {
    expected = _normalizeUuids(expected);
    actual = _normalizeUuids(actual);
  }
  expect(actual.keys.toSet(), expected.keys.toSet());
  for (final MapEntry(key: entry, value: text) in expected.entries) {
    if (adjust[entry] case final change?) {
      final json = jsonDecode(text);
      change(json);
      expect(jsonDecode(actual[entry]!), json, reason: entry);
    } else {
      expect(actual[entry], text, reason: entry);
    }
  }
}

void main() {
  late String out;
  final runs = <String, Future<ProcessResult>>{};

  setUpAll(() {
    out = Directory.systemTemp.createTempSync('csd_examples_').path;
    // Starts every script at once, in a directory of its own, so the scripts
    // find their fixtures next to themselves rather than in the current
    // directory.
    for (final name in _builders.keys) {
      runs[name] = runScript('example/$name.dart', [
        p.join(out, '$name.keyx'),
      ], workingDirectory: out);
    }
    runs['main'] = runScript('example/main.dart', [
      p.join(out, 'hello.keyx'),
    ], workingDirectory: out);
    runs['authoring'] = runScript('example/authoring.dart', [
      p.join(packageRoot, 'example', 'fixtures', 'Tidal_en.keyx'),
      p.join(out, 'authoring.keyx'),
    ], workingDirectory: out);
    runs['inspection'] = runScript('example/inspection.dart', [
      p.join(packageRoot, 'example', 'fixtures', 'sample.keyx'),
      p.join(out, 'replaced.keyx'),
    ], workingDirectory: out);
  });

  tearDownAll(() => Directory(out).deleteSync(recursive: true));

  group('builds', () {
    for (final MapEntry(key: name, value: resources) in _builders.entries) {
      test('$name.dart writes a valid document like upstream', () async {
        final result = await runs[name]!;
        expect(result, succeeded, reason: '${result.stderr}');
        final path = p.join(out, '$name.keyx');
        expect(outputLines(result), [
          'wrote $path (${File(path).lengthSync()} bytes)',
        ]);

        final doc = expectValidRoundTrip(path);
        expect(doc.resources.keys.toSet(), resources.keys.toSet());
        for (final MapEntry(key: filename, value: fixture)
            in resources.entries) {
          expect(
            doc.resources[filename],
            File(p.join(packageRoot, 'example', 'fixtures', fixture))
                .readAsBytesSync(),
          );
        }

        _expectMatchesUpstream(
          path,
          name,
          adjust: switch (name) {
            // Upstream gives `ContactShadow` an `angle`, which isn't one of
            // its fields, so upstream keeps it as an unknown key. The port
            // leaves it out.
            'image_decoration' => {
              'main.json': (json) {
                final slides = (json! as Map<String, Object?>)['slides'];
                final slide = (slides! as List<Object?>)[0];
                final contents = (slide! as Map)['contents'] as List<Object?>;
                final image = ((contents[2]! as Map)['object'] as Map)['image'];
                final shadow = (image as Map)['shadow'] as Map;
                (shadow['contactShadow'] as Map).remove('angle');
              },
            },
            // Upstream's `model_dump(exclude={"type_identifier",
            // "version"})` doesn't exclude the envelope, which its wire
            // serializer adds back. The port leaves it out, as the comment
            // in both says.
            'tables' => {
              'presets.json': (json) {
                for (final preset in json! as List<Object?>) {
                  final entry = preset! as Map<String, Object?>;
                  if ((entry['identifier']! as String).startsWith('stroke_')) {
                    (entry['properties']! as Map)
                      ..remove('type_identifier')
                      ..remove('version');
                  }
                }
              },
            },
            _ => const {},
          },
        );
      });
    }
  });

  test('main.dart writes the quick start, as upstream does', () async {
    final result = await runs['main']!;
    expect(result, succeeded, reason: '${result.stderr}');
    final path = p.join(out, 'hello.keyx');
    expect(outputLines(result), ['wrote $path']);
    final doc = expectValidRoundTrip(path);
    final textbox = doc.presentation.slides.single.contents!.single.object;
    expect(textbox.textbox?.text?.string, 'Hello, Keynote');
    _expectMatchesUpstream(path, 'hello');
  });

  group('authoring.dart', () {
    test('builds slides from the theme, as upstream does', () async {
      final result = await runs['authoring']!;
      expect(result, succeeded, reason: '${result.stderr}');
      final path = p.join(out, 'authoring.keyx');
      final lines = outputLines(result);
      expect(lines.take(3), [
        'Title',
        '    TITLE:shape "Title Text"',
        '    Subtitle:shape "A theme built for testing, not for sale"',
      ]);
      expect(
        lines,
        containsAllInOrder([
          'Title & Bullets',
          '    SLIDE_NUMBER:shape null',
          'Body -> text-2-paragraphstyle-Body',
          'resolved heading gap: 24pt',
          'Wrote $path',
        ]),
      );

      final doc = expectValidRoundTrip(path);
      expect(
        [for (final s in doc.presentation.slides) s.layout],
        [
          'Photo - Horizontal',
          'Title, Bullets & Photo',
          'Title & Bullets',
          'Quote',
        ],
      );
      expect(
        doc.resources.keys.toSet(),
        containsAll(['season_plan.png', 'sample_photo.jpg']),
      );
      _expectMatchesUpstream(path, 'authoring', randomIdentifiers: true);
    });

    // The doctest of upstream's authoring.py.
    test("reads the theme's layout and style names", () {
      final doc = KeyxDocument.open(
        p.join(packageRoot, 'example', 'fixtures', 'Tidal_en.keyx'),
      );
      expect(
        summarizeSlideLayouts(doc.presentation.theme!).keys.first,
        'Title',
      );
      final pairs = [
        for (final s in doc.presentation.stylesheet!.paragraphStyles!)
          if (s.properties.presetIdentifier.isNotEmpty)
            (s.name, s.properties.presetIdentifier),
      ];
      // A (style name, preset identifier) pair.
      expect(pairs[0], ('Title Small', 'text-1-paragraphstyle-Title Alt'));
      // The preset identifier can differ from the style name.
      expect(
        {for (final (name, id) in pairs) name: id}['Title Small'],
        'text-1-paragraphstyle-Title Alt',
      );
      final reg = PresetRegistry(doc.presets);
      const body = 'text-2-paragraphstyle-Body'; // Query by identifier.
      expect(reg.resolvedProperties(body)['space_after'], 24);
    });
  });

  group('inspection.dart', () {
    test('prints and replaces the text, as upstream does', () async {
      final result = await runs['inspection']!;
      expect(result, succeeded, reason: '${result.stderr}');
      final path = p.join(out, 'replaced.keyx');
      final lines = outputLines(result);
      expect(lines.first, 'The first slide, two levels deep:');
      expect(lines.sublist(lines.indexOf('Before:')), [
        'Before:',
        '  "Hero"',
        '  "hidden caption; kept for round-trip"',
        '  "Kyoto"',
        '  "Where old temples "',
        '  "meet quiet gardens."',
        '  "EST. 794  ·  THE ANCIENT CAPITAL"',
        'After:',
        '  "Lore"',
        '  "Lorem ipsum dolor sit amet, consect"',
        '  "Lorem"',
        '  "Lorem ipsum dolor "',
        '  "Lorem ipsum dolor s"',
        '  "Lorem ipsum dolor sit amet, cons"',
        'Wrote $path',
      ]);
      expectValidRoundTrip(path);
      _expectMatchesUpstream(path, 'inspection');
    });

    test('loremOfLength cuts the text to the length', () {
      expect(inspection.loremOfLength(0), '');
      expect(inspection.loremOfLength(-3), '');
      expect(inspection.loremOfLength(5), 'Lorem');
      final long = inspection.loremOfLength(inspection.lorem.length * 2 + 7);
      expect(long, hasLength(inspection.lorem.length * 2 + 7));
      expect(long, startsWith(inspection.lorem + inspection.lorem));
    });

    test('outline cuts the JSON short', () {
      final slide = Slide(
        contents: [
          for (var i = 0; i < 3; i++)
            SlideObject(
              object: CanvasObject(
                textbox: Textbox(text: Text(string: 'x' * 9)),
              ),
            ),
        ],
      );
      expect(
        inspection.outline(slide, const [], maxLength: 2, maxString: 4),
        [
          'Slide:',
          '  contents:',
          '    [0]',
          '      object: {…}',
          '    [1]',
          '      object: {…}',
          '    … (1 more)',
        ].join('\n'),
      );
      expect(
        inspection.outline(Text(string: 'x' * 9), const [], maxString: 4),
        'Text:\n  string: "xxxx"…',
      );
    });
  });

  group('arguments', () {
    test('--help prints the usage', () async {
      final result = await runScript('example/authoring.dart', [
        '--help',
      ], workingDirectory: packageRoot);
      expect(result, succeeded);
      expect(
        outputLines(result).first,
        'Usage: dart run example/authoring.dart [input] [output]',
      );
    });

    test('a prefix of --help asks for help, as argparse reads it', () async {
      final dir = tempDir();
      for (final option in ['--h', '--he', '--hel']) {
        final result = await runScript('example/basics.dart', [
          option,
        ], workingDirectory: dir);
        expect(result, succeeded, reason: option);
        expect(
          outputLines(result).first,
          'Usage: dart run example/basics.dart [output]',
          reason: option,
        );
      }
      final longer = await runScript('example/basics.dart', [
        '--helpx',
      ], workingDirectory: dir);
      expect(longer.exitCode, 64);
      expect(longer.stderr, contains('Unrecognized arguments: --helpx'));
      expect(Directory(dir).listSync(), isEmpty);
    });

    test('main.dart parses its arguments like the other scripts', () async {
      final dir = tempDir();
      final help = await runScript('example/main.dart', [
        '--help',
      ], workingDirectory: dir);
      expect(help, succeeded, reason: '${help.stderr}');
      final lines = outputLines(help);
      expect(lines.first, 'Usage: dart run example/main.dart [output]');
      expect(
        lines.last,
        '  output  defaults to '
        '${p.join(Directory.systemTemp.path, 'creator_studio_document_examples', 'hello.keyx')}',
      );
      final extra = await runScript('example/main.dart', [
        'a.keyx',
        'b.keyx',
      ], workingDirectory: dir);
      expect(extra.exitCode, 64);
      expect(Directory(dir).listSync(), isEmpty);
    });

    test('an unknown option fails with the usage and writes nothing', () async {
      final dir = tempDir();
      for (final option in ['--bogus', '-x']) {
        final result = await runScript('example/basics.dart', [
          option,
        ], workingDirectory: dir);
        expect(result.exitCode, 64, reason: option);
        expect(
          result.stderr,
          allOf(
            startsWith('Usage: dart run example/basics.dart [output]'),
            contains('Unrecognized arguments: $option'),
          ),
        );
      }
      expect(Directory(dir).listSync(), isEmpty);
    });

    test('an argument after -- is positional', () async {
      final dir = tempDir();
      final result = await runScript('example/main.dart', [
        '--',
        '-dash.keyx',
      ], workingDirectory: dir);
      expect(result, succeeded, reason: '${result.stderr}');
      expect(outputLines(result), ['wrote -dash.keyx']);
      expectValidRoundTrip(p.join(dir, '-dash.keyx'));
    });

    test('too many arguments fail with the usage', () async {
      final result = await runScript('example/charts.dart', [
        'a.keyx',
        'b.keyx',
      ], workingDirectory: packageRoot);
      expect(result.exitCode, 64);
      expect(
        result.stderr,
        startsWith('Usage: dart run example/charts.dart [output]'),
      );
    });
  });
}
