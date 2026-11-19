// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Not ported: upstream tests `_slide_layout_refs.py` only through the
// authoring functions. The expected keys come from upstream's
// `layout_name_key`, run on the Python that `tool/extract_schema.py` ran
// on.

import 'package:creator_studio_document/authoring.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:test/test.dart';

void main() {
  group('layoutNameKey', () {
    for (final (name, key) in const [
      ('Title & Bullets', 'title & bullets'),
      ('TITLE & BULLETS', 'title & bullets'),
      ('  Title  ', '  title  '),
      ('\u0130stanbul', 'istanbul'),
      ('ISTANBUL', 'istanbul'),
      ('\u0131stanbul', 'istanbul'),
      ('i\u0307', 'i'),
      ('I\u0307\u0301', '\u00ed'),
      ('\u1eca\u0307', '\u1ecb'),
      ('Stra\u00dfe', 'strasse'),
      ('STRASSE', 'strasse'),
      ('\u1e9e', 'ss'),
      ('\ufb01le', 'file'),
      ('\ufb00', 'ff'),
      ('\u00c5', 'aa'),
      ('\u00c5', 'aa'),
      ('\u00c5ngstr\u00f6m', 'aangstr\u00f6m'),
      ('aa', 'aa'),
      ('AA', 'aa'),
      ('A\u00e5', 'aaa'),
      ('\u216b', 'xii'),
      ('\u01c5', 'd\u017e'),
      ('\u03a3\u0391\u03a3', '\u03c3\u03b1\u03c3'),
      ('\u03c2', '\u03c3'),
      ('\u00e9', '\u00e9'),
      ('e\u0301', '\u00e9'),
      ('\uac00\uac01', '\uac00\uac01'),
      ('\u1100\u1161\u11a8', '\uac01'),
      ('\u3131', '\u1100'),
      ('\uff46\uff55\uff4c\uff4c\uff57\uff49\uff44\uff54\uff48', 'fullwidth'),
      ('\u2460', '1'),
      (
        '\ufdfa',
        '\u0635\u0644\u0649 \u0627\u0644\u0644\u0647 \u0639\u0644\u064a\u0647 \u0648\u0633\u0644\u0645',
      ),
      ('\u01c4', 'd\u017e'),
      ('\u0149', '\u02bcn'),
      ('\u01f0', '\u01f0'),
      ('\u0390', '\u0390'),
      ('q\u0323\u0307', 'q\u0323\u0307'),
      ('q\u0307\u0323', 'q\u0323\u0307'),
      ('\u0105\u0301', '\u0105\u0301'),
      ('x\ud800y', 'x\ud800y'),
      ('\udc00', '\udc00'),
      ('\u{1f600} Photo', '\u{1f600} photo'),
      ('\u{1d400}\u{1d401}', 'ab'),
      ('Photo - Horizontal', 'photo - horizontal'),
      ('', ''),
    ]) {
      test('keys ${name.runes.map((c) => c.toRadixString(16))}', () {
        expect(layoutNameKey(name), key);
      });
    }
  });

  group('resolveSlideLayout', () {
    final first = SlideLayout(name: 'Title');
    final second = SlideLayout(name: 'title');
    final byId = SlideLayout(name: 'Other', identifier: 'Plain');
    final byName = SlideLayout(name: 'Plain');
    final layouts = [first, second, byId, byName];

    test('prefers an identifier over a name', () {
      expect(resolveSlideLayout(layouts, 'Plain'), same(byId));
    });

    test('takes the first layout whose name key matches', () {
      expect(resolveSlideLayout(layouts, 'title'), same(first));
      expect(resolveSlideLayout(layouts, 'TİTLE'), same(first));
    });

    test('returns null when nothing matches', () {
      expect(resolveSlideLayout(layouts, 'Nope'), isNull);
      expect(resolveSlideLayout(const [], 'Title'), isNull);
    });
  });
}
