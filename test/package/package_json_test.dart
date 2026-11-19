// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Checks that a package's parts are read as Python's `json.loads` reads
// them and written as upstream's `_dumps` writes them. Every expectation is
// what upstream's Python produces for the same input.

import 'dart:convert';
import 'dart:typed_data';

import 'package:creator_studio_document/src/core/package_json.dart';
import 'package:test/test.dart';

Uint8List _b(List<int> bytes) => Uint8List.fromList(bytes);

Uint8List _s(String text) => Uint8List.fromList(utf8.encode(text));

Matcher _error(String message) =>
    throwsA(isA<PyJsonError>().having((e) => e.message, 'message', message));

void main() {
  group('loads', () {
    test('a repeated key keeps the last value, and special numbers read', () {
      final value =
          pyJsonLoads(_s('{"a": 1, "a": 2, "b": [1.5, -0.0, 1e400, NaN]}'))!
              as Map<String, Object?>;
      expect(value.keys, ['a', 'b']);
      expect(value['a'], 2);
      final b = value['b']! as List<Object?>;
      expect(b[0], 1.5);
      expect((b[1]! as double).isNegative, isTrue);
      expect(b[2], double.infinity);
      expect((b[3]! as double).isNaN, isTrue);
      expect(pyJsonLoads(_s('-Infinity')), double.negativeInfinity);
      expect(pyJsonLoads(_s('Infinity')), double.infinity);
    });

    test('escapes pair surrogates, and keep a lone one', () {
      expect(pyJsonLoads(_s(r'"𐀀\ud800x"')), '\u{10000}\ud800x');
      expect(pyJsonLoads(_b([0x22, 0xed, 0xa0, 0x80, 0x22])), '\ud800');
    });

    test('the encoding is detected as Python detects it', () {
      expect(
        pyJsonLoads(_b([0xef, 0xbb, 0xbf, ...utf8.encode('{"k": "v"}')])),
        {'k': 'v'},
      );
      // UTF-16 with a byte order mark, as `str.encode("utf-16")` writes it.
      final utf16 = <int>[0xff, 0xfe];
      for (final unit in '{"k": "é"}'.codeUnits) {
        utf16.addAll([unit & 0xff, unit >> 8]);
      }
      expect(pyJsonLoads(_b(utf16)), {'k': 'é'});
      expect(pyJsonLoads(_b([0, 0x5b, 0, 0x31, 0, 0x5d])), [1]);
      expect(pyJsonLoads(_b([0x5b, 0, 0, 0, 0x31, 0, 0, 0, 0x5d, 0, 0, 0])), [
        1,
      ]);
    });

    test('an integer too large for an int reads exactly, as a BigInt', () {
      expect(pyJsonLoads(_s('[12345678901234567890, -9223372036854775809]')), [
        BigInt.parse('12345678901234567890'),
        BigInt.parse('-9223372036854775809'),
      ]);
      expect(pyJsonLoads(_s('9223372036854775807')), isA<int>());
      expect(
        () => pyJsonLoads(_s('1' * 4301)),
        _error(
          'Exceeds the limit (4300 digits) for integer string conversion: '
          'value has 4301 digits; use sys.set_int_max_str_digits() to '
          'increase the limit',
        ),
      );
      expect(pyJsonLoads(_s('-${'1' * 4300}')), BigInt.parse('-${'1' * 4300}'));
    });

    test('reads as deep as Python, and fails one level deeper', () {
      String nested(int depth, String open, String leaf, String close) =>
          '${open * depth}$leaf${close * depth}';
      expect(maxJsonDepth, 9998);
      var value = pyJsonLoads(_s(nested(maxJsonDepth, '[', '', ']')));
      for (var depth = 1; depth < maxJsonDepth; depth++) {
        value = (value! as List<Object?>).single;
      }
      expect(value, isEmpty);
      pyJsonLoads(_s(nested(maxJsonDepth, '{"a":', '1', '}')));
      for (final (open, leaf, close, what) in [
        ('[', '', ']', 'array'),
        ('{"a":', '1', '}', 'object'),
      ]) {
        expect(
          () => pyJsonLoads(_s(nested(maxJsonDepth + 1, open, leaf, close))),
          throwsA(
            isA<PyJsonDepthError>().having(
              (e) => e.message,
              'message',
              'maximum recursion depth exceeded while decoding a JSON $what '
                  'from a unicode string',
            ),
          ),
        );
      }
      // The depth error comes first, as Python's recursion stops it before
      // the reader reaches the bad end.
      expect(
        () => pyJsonLoads(_s('${'[' * (maxJsonDepth + 1)}x')),
        throwsA(isA<PyJsonDepthError>()),
      );
      expect(
        () => pyJsonLoads(_s('${'[' * (maxJsonDepth - 1)}x')),
        _error('Expecting value: line 1 column 9998 (char 9997)'),
      );
    });

    test('errors read as Python words them', () {
      for (final (input, message) in [
        ('  [1, 2]  x', 'Extra data: line 1 column 11 (char 10)'),
        ('{"a" 1}', "Expecting ':' delimiter: line 1 column 6 (char 5)"),
        (
          '[1,]',
          'Illegal trailing comma before end of array: line 1 column 3 '
              '(char 2)',
        ),
        (
          '{"a":1,}',
          'Illegal trailing comma before end of object: line 1 column 7 '
              '(char 6)',
        ),
        ('"a\tb"', 'Invalid control character at: line 1 column 3 (char 2)'),
        (r'"\x"', r'Invalid \escape: line 1 column 2 (char 1)'),
        (r'"\u12g4"', r'Invalid \uXXXX escape: line 1 column 3 (char 2)'),
        ('-', 'Expecting value: line 1 column 1 (char 0)'),
        ('01', 'Extra data: line 1 column 2 (char 1)'),
        ('1.', 'Extra data: line 1 column 2 (char 1)'),
        ('1e', 'Extra data: line 1 column 2 (char 1)'),
        (
          '"unterminated',
          'Unterminated string starting at: line 1 column 1 '
              '(char 0)',
        ),
        ('{"a":\n  [1, @]}', 'Expecting value: line 2 column 7 (char 12)'),
        ('', 'Expecting value: line 1 column 1 (char 0)'),
        ('[\u{1F600}, x]', 'Expecting value: line 1 column 2 (char 1)'),
        (
          '["\u{1F600}" x]',
          "Expecting ',' delimiter: line 1 column 6 "
              '(char 5)',
        ),
      ]) {
        expect(() => pyJsonLoads(_s(input)), _error(message), reason: input);
      }
      expect(
        () => pyJsonLoads(_b([0xff])),
        _error(
          "'utf-8' codec can't decode byte 0xff in position 0: invalid start "
          'byte',
        ),
      );
    });
  });

  group('dumps', () {
    test('writes compact JSON with Python number spellings', () {
      final text = utf8.decode(
        pyJsonDumps({
          'a': [1, 1.0, 1e16, 1e-7, 0.1, double.nan, double.infinity],
          'é\n"\\\u0001\u007f ': true,
          'b': null,
          'c': false,
        }),
      );
      expect(
        text,
        '{"a":[1,1.0,1e+16,1e-07,0.1,NaN,Infinity],'
        '"é\\n\\"\\\\\\u0001\u007f ":true,"b":null,"c":false}',
      );
    });

    test('converts keys that are not strings as Python does', () {
      expect(
        utf8.decode(pyJsonDumps({1: 2, 2.5: false, null: 1, true: 0})),
        '{"1":2,"2.5":false,"null":1,"true":0}',
      );
    });

    test('a lone surrogate fails as UTF-8 encoding does', () {
      expect(
        () => pyJsonDumps('\ud800'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            r"'utf-8' codec can't encode character '\ud800' in position 1: "
                'surrogates not allowed',
          ),
        ),
      );
    });

    test('a run of lone surrogates is named as Python names it', () {
      expect(
        () => pyJsonDumps({'k': 'x\udc00\udc01y\ud800'}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            "'utf-8' codec can't encode characters in position 7-8: "
                'surrogates not allowed',
          ),
        ),
      );
    });

    test('writes a BigInt as its exact digits', () {
      expect(
        utf8.decode(
          pyJsonDumps({
            'a': BigInt.parse('123456789012345678901234567890'),
            'b': [BigInt.parse('-9223372036854775809')],
          }),
        ),
        '{"a":123456789012345678901234567890,"b":[-9223372036854775809]}',
      );
    });

    test('writes a value as deep as it reads', () {
      final text = '${'[' * maxJsonDepth}1${']' * maxJsonDepth}';
      expect(utf8.decode(pyJsonDumps(pyJsonLoads(_s(text)))), text);
    });

    test('a value that is not JSON, or contains itself, fails', () {
      expect(() => pyJsonDumps(Object()), throwsArgumentError);
      final list = <Object?>[];
      list.add(list);
      expect(() => pyJsonDumps(list), throwsArgumentError);
    });

    test('what it writes reads back', () {
      final value = {
        'nested': [
          {'x': 'tab\there', 'y': -0.5, 'z': '\u{1F600}'},
        ],
      };
      expect(pyJsonLoads(pyJsonDumps(value)), value);
    });
  });
}
