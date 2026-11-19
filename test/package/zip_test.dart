// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python): the root-prefix
// detection and re-zip hint of core/package.py, with the outcomes checked
// against upstream.

import 'package:creator_studio_document/src/core/package_zip.dart';
import 'package:test/test.dart';

void main() {
  test('the root prefix and the re-zip hint follow upstream', () {
    for (final (names, prefix, hint) in [
      (<String>[], '', ''),
      (['main.json'], '', ''),
      (
        ['Deck/main.json', 'Deck/Data/a.png'],
        'Deck/',
        " (archive was re-zipped: entries live under 'Deck/', not at the "
            'archive root)',
      ),
      (['Deck/main.json', 'other.txt'], '', ''),
      (['A/x', 'B/y'], '', ''),
      (
        ['./main.json', './Data/a'],
        './',
        " (archive was re-zipped: entries live under './', not at the "
            'archive root)',
      ),
      (
        ['./Deck/main.json', './Deck/Data/a'],
        './Deck/',
        " (archive was re-zipped: entries live under './Deck/', not at the "
            'archive root)',
      ),
      (['./a', 'b'], '', ''),
      (
        ['Deck/', 'Deck/main.json', '__MACOSX/Deck/._main.json'],
        'Deck/',
        " (archive was re-zipped: entries live under 'Deck/', not at the "
            'archive root and __MACOSX sidecars present)',
      ),
      (
        ['__MACOSX/x'],
        '',
        ' (archive was re-zipped: __MACOSX sidecars present)',
      ),
      (
        ['Deck/main.json', 'Deck/sub/'],
        'Deck/',
        " (archive was re-zipped: entries live under 'Deck/', not at the "
            'archive root)',
      ),
    ]) {
      final found = detectRootPrefix(names);
      expect(found, prefix, reason: '$names');
      expect(rezipHint(names, found), hint, reason: '$names');
    }
  });
}
