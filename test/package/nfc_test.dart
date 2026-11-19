// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Spot checks of the NFC normalization that `ResourceStore` matches names
// with, against Python's `unicodedata.normalize("NFC", ...)`. The tables come
// from Python (see tool/extract_schema.py); a run over every code point and
// 200,000 random sequences matched upstream when they were generated.

import 'package:creator_studio_document/src/core/resources_nfc.dart';
import 'package:test/test.dart';

void main() {
  test('composes, reorders, and leaves exclusions decomposed', () {
    for (final (input, output) in [
      ('plain ascii', 'plain ascii'),
      ('e\u0301', '\u00e9'),
      ('cafe\u0301.png', 'caf\u00e9.png'),
      // Dot below (220) sorts before dot above (230), then both compose.
      ('s\u0307\u0323', '\u1e69'),
      ('\u1e61\u0323', '\u1e69'),
      // Hangul syllables compose algorithmically.
      ('\u1100\u1161\u11a8', '\uac01'),
      ('\uac00\u11a8', '\uac01'),
      // A singleton decomposition never recomposes: the ohm sign.
      ('\u2126', '\u03a9'),
      // A composition exclusion stays decomposed.
      ('\u0958', '\u0915\u093c'),
      // A blocked mark doesn't compose across a mark of the same class.
      ('a\u0301\u0301', '\u00e1\u0301'),
      ('a\u0323\u0302', '\u1ead'),
      // Astral code points: musical symbols decompose and stay so.
      ('\u{1d15e}', '\u{1d157}\u{1d165}'),
      ('\ud800 lone', '\ud800 lone'),
    ]) {
      expect(nfc(input), output, reason: input.runes.toString());
    }
  });

  test('combining classes', () {
    expect(combiningClass(0x41), 0);
    expect(combiningClass(0x301), 230);
    expect(combiningClass(0x323), 220);
    expect(combiningClass(0x334), 1);
  });
}
