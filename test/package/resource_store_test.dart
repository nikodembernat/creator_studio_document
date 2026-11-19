// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python): the doctests of
// `ResourceStore` in core/package.py, and the behavior its docstrings and
// comments describe, with the outcomes checked against upstream.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:test/test.dart';

import 'builders.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

Matcher _invalidName(String repr) => throwsA(
  isA<ArgumentError>().having(
    (e) => e.message,
    'message',
    'invalid resource filename $repr: expected a flat filename (nonempty, '
        r"no '/', '\', or '..')",
  ),
);

// A lazily opened package with the resources [names], saved to [dir].
KeyxDocument _lazyWith(Directory dir, List<String> names) {
  final doc = emptyDoc();
  for (final n in names) {
    doc.resources[n] = _b(n);
  }
  final path = '${dir.path}/lazy.keyx';
  doc.save(path);
  return KeyxDocument.openLazy(path);
}

void main() {
  group('doctests', () {
    test('uniqueFilename picks a free name', () {
      final store = ResourceStore({'logo.png': _b('old')});
      final name = store.uniqueFilename('logo.png');
      store[name] = _b('new');
      expect(store.keys.toList()..sort(), ['logo 2.png', 'logo.png']);
    });

    test('bytesFor finds a decomposed spelling that indexing misses', () {
      // The key is the NFD spelling of café.png.
      final store = ResourceStore({'cafe\u0301.png': _b('png bytes')});
      expect(store.containsKey('café.png'), isFalse);
      expect(store['café.png'], isNull);
      expect(store.bytesFor('café.png'), _b('png bytes'));
    });
  });

  group('filenames', () {
    test('a key must be a flat filename', () {
      final store = ResourceStore();
      expect(() => store[''] = png, _invalidName("''"));
      expect(() => store['.'] = png, _invalidName("'.'"));
      expect(() => store['..'] = png, _invalidName("'..'"));
      expect(() => store['a/b'] = png, _invalidName("'a/b'"));
      expect(() => store[r'a\b'] = png, _invalidName(r"'a\\b'"));
      expect(() => ResourceStore({'Data/x.png': png}), throwsArgumentError);
      expect(
        () => store.addAll({'ok.png': png, '../x': png}),
        throwsArgumentError,
      );
      expect(store.keys, ['ok.png']);
      expect(
        () =>
            Package(Presentation(slides: [Slide()]), resources: {'/abs': png}),
        throwsArgumentError,
      );
    });

    test('names with dots and spaces are flat', () {
      final store = ResourceStore()
        ..['...'] = png
        ..['.hidden'] = png
        ..[' padded '] = png
        ..['a..b'] = png;
      expect(store, hasLength(4));
    });

    test('uniqueFilename numbers the name before its last dot', () {
      final store = ResourceStore({
        for (final n in [
          'a.tar.gz',
          '.hidden',
          'noext',
          'a.',
          'x.png',
          'x 2.png',
        ])
          n: png,
      });
      expect(
        [
          for (final n in [
            'a.tar.gz',
            '.hidden',
            'noext',
            'a.',
            'x.png',
            'free.png',
          ])
            store.uniqueFilename(n),
        ],
        ['a.tar 2.gz', ' 2.hidden', 'noext 2', 'a 2.', 'x 3.png', 'free.png'],
      );
    });
  });

  group('resolving', () {
    test('an exact key wins over a canonically equivalent one', () {
      final store = ResourceStore({
        'e\u0301.png': _b('nfd'),
        'é.png': _b('nfc'),
      });
      expect(store.bytesFor('é.png'), _b('nfc'));
      expect(store.bytesFor('e\u0301.png'), _b('nfd'));
    });

    test('of equivalent keys, the first in code point order matches', () {
      final store = ResourceStore({
        '\u1e61\u0323.png': _b('b'),
        's\u0323\u0307.png': _b('a'),
      });
      expect(store.resolveKey('\u1e69.png'), 's\u0323\u0307.png');
      expect(store.resolveKey('\u1e63\u0307.png'), 's\u0323\u0307.png');
      expect(store.bytesFor('\u1e69.png'), _b('a'));
    });

    test('the only key with the same ASCII characters matches', () {
      final store = ResourceStore({'写真': png});
      expect(store.canResolve('ÕåÖþ£ƒ'), isTrue);
      expect(store.bytesFor('ÕåÖþ£ƒ'), png);
      store['画像'] = png;
      expect(store.canResolve('ÕåÖþ£ƒ'), isFalse);
      expect(
        () => store.bytesFor('ÕåÖþ£ƒ'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            "no Data/ bytes for indirect resource 'ÕåÖþ£ƒ'",
          ),
        ),
      );
    });

    test('the ASCII match can pick a different file', () {
      final store = ResourceStore({'è.png': png});
      expect(store.resolveKey('é.png'), 'è.png');
    });

    test('the index follows changes to the keys', () {
      final store = ResourceStore({'e\u0301.png': _b('1')});
      expect(store.resolveKey('é.png'), 'e\u0301.png');
      store.remove('e\u0301.png');
      expect(store.canResolve('é.png'), isFalse);
      store['e\u0301.png'] = _b('2');
      expect(store.bytesFor('é.png'), _b('2'));
    });

    test('a padded name resolves only by its exact spelling', () {
      final store = ResourceStore({'img.png': png});
      expect(store.canResolve('  img.png  '), isFalse);
      store['  img.png  '] = png;
      expect(store.canResolve('  img.png  '), isTrue);
    });
  });

  group('lazy', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('store_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('reads each resource on first access and caches it', () {
      final doc = _lazyWith(tmp, ['a.png', 'b.png']);
      addTearDown(doc.close);
      final store = doc.resources;
      expect(store.isLazy, isTrue);
      expect(store, hasLength(2));
      expect(store.keys.toList()..sort(), ['a.png', 'b.png']);
      expect(store['a.png'], _b('a.png'));
      expect(identical(store['a.png'], store['a.png']), isTrue);
      expect(store['missing.png'], isNull);
      expect(store[Object()], isNull);
    });

    test('removing a resource that is also cached removes both', () {
      final doc = _lazyWith(tmp, ['a.png', 'b.png']);
      addTearDown(doc.close);
      final store = doc.resources;
      expect(store['a.png'], _b('a.png'));
      expect(store.remove('a.png'), _b('a.png'));
      expect(store.containsKey('a.png'), isFalse);
      expect(store['a.png'], isNull);
      expect(store.remove('a.png'), isNull);
      // A removal reads the bytes it returns.
      expect(store.remove('b.png'), _b('b.png'));
      expect(store, isEmpty);
      store['a.png'] = _b('new');
      expect(store['a.png'], _b('new'));
      expect(store, hasLength(1));
    });

    test('delete drops a resource without reading it', () {
      final doc = _lazyWith(tmp, ['a.png', 'b.png']);
      addTearDown(doc.close);
      final store = doc.resources;
      expect(store['a.png'], _b('a.png'));
      expect(store.delete('a.png'), isTrue);
      expect(store.delete('b.png'), isTrue);
      expect(store.delete('b.png'), isFalse);
      expect(store.delete('missing.png'), isFalse);
      expect(store, isEmpty);
      store['b.png'] = _b('new');
      expect(store['b.png'], _b('new'));
      expect(ResourceStore({'x.png': png}).delete('x.png'), isTrue);
    });

    test('delete drops a corrupt member that remove must read', () {
      // Upstream's `del` reads nothing, so a lazily opened package can drop
      // a corrupt resource and save; `remove` reads it, as `pop` does.
      const path = 'test/fixtures/package/bad_crc_data.keyx';
      final doc = KeyxDocument.openLazy(path);
      addTearDown(doc.close);
      final corrupt = throwsA(
        isA<DocumentPackageError>()
            .having(
              (e) => e.kind,
              'kind',
              DocumentPackageErrorKind.malformedArchive,
            )
            .having(
              (e) => e.message,
              'message',
              contains("Bad CRC-32 for file 'Data/hero.png'"),
            ),
      );
      expect(() => doc.resources.remove('hero.png'), corrupt);
      expect(doc.resources.keys, ['hero.png']);
      expect(doc.resources.delete('hero.png'), isTrue);
      expect(doc.resources, isEmpty);
      final saved = '${tmp.path}/repaired.keyx';
      doc.save(saved, validateResources: false);
      expect(KeyxDocument.open(saved).resources, isEmpty);
    });

    test('clear reads nothing and converges', () {
      final doc = _lazyWith(tmp, ['a.png', 'b.png']);
      addTearDown(doc.close);
      final store = doc.resources..['c.png'] = png;
      expect(store, hasLength(3));
      store.clear();
      expect(store, isEmpty);
      expect(store.keys, isEmpty);
      final saved = '${tmp.path}/cleared.keyx';
      doc.save(saved);
      expect(KeyxDocument.open(saved).resources, isEmpty);
    });

    test('overwriting a resource replaces the archived bytes', () {
      final doc = _lazyWith(tmp, ['a.png']);
      addTearDown(doc.close);
      doc.resources['a.png'] = _b('replaced');
      expect(doc.resources, hasLength(1));
      final saved = '${tmp.path}/over.keyx';
      doc.save(saved);
      expect(KeyxDocument.open(saved).resources['a.png'], _b('replaced'));
    });

    test('close keeps only what was read, and is idempotent', () {
      final doc = _lazyWith(tmp, ['a.png', 'b.png']);
      expect(doc.resources['a.png'], _b('a.png'));
      doc.close();
      expect(doc.resources.isLazy, isFalse);
      expect(doc.resources.keys, ['a.png']);
      doc.close();
      expect(doc.resources.keys, ['a.png']);
    });

    test('a new store takes over the archive of a lazy one', () {
      final doc = _lazyWith(tmp, ['a.png', 'b.png']);
      final old = doc.resources;
      expect(old['a.png'], _b('a.png'));
      old.remove('b.png');
      final moved = ResourceStore(old);
      addTearDown(moved.close);
      expect(moved.isLazy, isTrue);
      expect(old.isLazy, isFalse);
      expect(old.keys, ['a.png']);
      expect(moved.keys, ['a.png']);
      moved['b.png'] = _b('again');
      expect(moved.keys, ['a.png', 'b.png']);
      // Closing the old store no longer closes the archive.
      old.close();
      expect(moved.isLazy, isTrue);
    });

    test('an eager store copies another store', () {
      final a = ResourceStore({'a.png': png});
      final b = ResourceStore(a)..['b.png'] = png;
      expect(a.keys, ['a.png']);
      expect(b.keys, ['a.png', 'b.png']);
    });

    test('a lazy read of a corrupt member is a malformed archive', () {
      final doc = emptyDoc();
      doc.resources['a.png'] = Uint8List(64);
      final path = '${tmp.path}/corrupt.keyx';
      doc.save(path);
      final bytes = File(path).readAsBytesSync();
      // Overwrite the start of the deflated data of Data/a.png.
      final name = utf8.encode('Data/a.png');
      var at = -1;
      for (var i = 0; i + 30 + name.length <= bytes.length; i++) {
        if (bytes[i] == 0x50 &&
            bytes[i + 1] == 0x4b &&
            bytes[i + 2] == 3 &&
            bytes[i + 3] == 4 &&
            utf8.decode(
                  bytes.sublist(i + 30, i + 30 + name.length),
                  allowMalformed: true,
                ) ==
                'Data/a.png') {
          at = i + 30 + name.length;
          break;
        }
      }
      expect(at, greaterThan(0));
      bytes.fillRange(at, at + 4, 0xff);
      File(path).writeAsBytesSync(bytes);
      final lazy = KeyxDocument.openLazy(path);
      addTearDown(lazy.close);
      expect(lazy.resources.containsKey('a.png'), isTrue);
      expect(
        () => lazy.resources['a.png'],
        throwsA(
          isA<DocumentPackageError>().having(
            (e) => e.kind,
            'kind',
            DocumentPackageErrorKind.malformedArchive,
          ),
        ),
      );
      expect(
        () => lazy.save('${tmp.path}/out.keyx'),
        throwsA(isA<DocumentPackageError>()),
      );
      expect(File('${tmp.path}/out.keyx').existsSync(), isFalse);
    });
  });

  test('toString lists the names without reading', () {
    expect(
      '${ResourceStore({'a.png': png, "it's.png": png})}',
      '''ResourceStore('a.png', "it's.png")''',
    );
  });
}
