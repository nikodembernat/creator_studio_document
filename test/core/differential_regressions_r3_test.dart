// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

// Regression tests for a third round of differential runs against the
// upstream Python package. Every expectation was checked against upstream.

import 'dart:convert';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

const _sizeId = 'com.apple.apps.content-language.size';
const _cellId = 'com.apple.apps.content-language.table.cell';
const _textId = 'com.apple.apps.content-language.text';
const _runId = 'com.apple.apps.content-language.text-run';
const _paragraphId = 'com.apple.apps.content-language.paragraph';

const _unicodeMessage =
    'Input should be a valid string, unable to parse raw data as a unicode '
    'string';

Matcher _issue(List<Object> location, String type) => isA<ValidationIssue>()
    .having((i) => i.location, 'location', location)
    .having((i) => i.type, 'type', type);

Matcher _invalid(List<Matcher> issues) => throwsA(
  isA<ModelValidationError>().having((e) => e.issues, 'issues', issues),
);

Matcher _stateError(String message) =>
    throwsA(isA<StateError>().having((e) => e.message, 'message', message));

Matcher _argumentError(String message) =>
    throwsA(isA<ArgumentError>().having((e) => e.message, 'message', message));

// Decodes JSON text, so lone surrogates arrive as `jsonDecode` gives them.
Object? _json(String text) => jsonDecode(text);

void main() {
  group('a lone surrogate in a key', () {
    test('of a model fails validation at the model, and only there', () {
      expect(
        () => Shape.fromJson(_json(r'{"identifier": "ok", "z\ud800": 1}')),
        _invalid([_issue(const [], 'string_unicode')]),
      );
      // The field errors that would follow are replaced, too.
      expect(
        () => Size.fromJson(_json(r'{"width": "x", "z\ud800": 1}')),
        _invalid([_issue(const [], 'string_unicode')]),
      );
      expect(
        () =>
            Size.fromJson(_json(r'{"width": 1.0, "height": 2.0, "\udfff": 1}')),
        throwsA(
          isA<ModelValidationError>().having(
            (e) => e.issues.single.message,
            'message',
            _unicodeMessage,
          ),
        ),
      );
    });

    test('of a nested model fails at that model', () {
      expect(
        () => Shape.fromJson(_json(r'{"geometry": {"q\ud800": 1}}')),
        _invalid([
          _issue(const ['geometry'], 'string_unicode'),
        ]),
      );
      expect(
        () => Shape.fromJson(
          _json(r'{"geometry": {"position": "bad", "q\ud800": 1}}'),
        ),
        _invalid([
          _issue(const ['geometry'], 'string_unicode'),
        ]),
      );
    });

    test('of a union fails validation at the union', () {
      expect(
        () => Shadow.fromJson(_json(r'{"none": null, "z\ud800": 1}')),
        _invalid([_issue(const [], 'string_unicode')]),
      );
    });

    test('comes after the version check', () {
      expect(
        () => Size.fromJson(
          _json(
            r'{"width": 1.0, "height": 2.0, "version": "9.0", "z\ud800": 1}',
          ),
        ),
        throwsA(isA<DocumentVersionError>()),
      );
    });

    test('inside an unknown value decodes, but fails to encode', () {
      final shape = Shape.fromJson(_json(r'{"zz": {"a\ud800": 1}}'));
      expect(
        shape.toJson,
        _stateError(
          r"'utf-8' codec can't encode character '\ud800' in position 1: "
          'surrogates not allowed',
        ),
      );
      // The position counts code points, as Python does.
      final shadow = Shadow.fromJson(
        _json(r'{"none": null, "zz": [{"\ud83d\ude00a\ud800": 1}]}'),
      );
      expect(
        shadow.toJson,
        _stateError(
          r"'utf-8' codec can't encode character '\ud800' in position 2: "
          'surrogates not allowed',
        ),
      );
    });

    test('added to the unknown keys fails to encode', () {
      final size = Size(width: 1, height: 2);
      size.extras['q\udc00'] = 1;
      expect(
        size.toJson,
        _stateError(
          r"'utf-8' codec can't encode character '\udc00' in position 1: "
          'surrogates not allowed',
        ),
      );
    });

    test('in a value, or a valid pair in a key, round-trips', () {
      expect(
        Shape.fromJson(_json(r'{"zz": "a\ud800", "\ud83d\ude00": 1}')).toJson(),
        {
          'type_identifier': 'com.apple.apps.content-language.shape',
          'version': '1.0',
          'zz': 'a\ud800',
          '\u{1f600}': 1,
        },
      );
    });
  });

  group(r'the key "\u0000wire_filled"', () {
    final registry = PresetRegistry([
      Preset('p', {'width': 5.0}),
      Preset('q', {}),
    ]);
    final context = WireContext(presets: registry);

    test('is dropped from an object that adopts a preset', () {
      for (final value in <Object>[
        ['height'],
        5,
        'x',
      ]) {
        final json = {
          'type_identifier': _sizeId,
          'version': '1.0',
          'width': 5.0,
          'height': 7.0,
          'preset_identifier': 'p',
          '\u0000wire_filled': value,
        };
        for (final decode in [context, null]) {
          final size = Size.fromJson(json, decode);
          expect(size.extras, isEmpty);
          expect(size.fieldsSet, contains('\u0000wire_filled'));
          expect(size.toJson(context), {
            'height': 7.0,
            'type_identifier': _sizeId,
            'version': '1.0',
            'preset_identifier': 'p',
          });
        }
      }
    });

    test('names the filled fields, tested as Python tests membership', () {
      Object encode(Object? value) => Cell.fromJson({
        'preset_identifier': 'q',
        '\u0000wire_filled': value,
      }, context).toJson(context);

      const written = {
        'value': '',
        'type_identifier': _cellId,
        'version': '1.0',
        'preset_identifier': 'q',
      };
      const omitted = {
        'type_identifier': _cellId,
        'version': '1.0',
        'preset_identifier': 'q',
      };
      // A field named as filled, which the preset doesn't supply, is written.
      expect(encode(['value']), written);
      expect(encode('xvaluex'), written);
      expect(encode({'value': 1}), written);
      expect(encode([1, 'value']), written);
      expect(encode('x'), omitted);
      expect(encode(<Object?>[]), omitted);
      expect(encode(null), omitted);
      // Upstream raises `TypeError` when it tests membership in a number.
      expect(
        () => encode(5),
        _argumentError("argument of type 'int' is not iterable"),
      );
      expect(
        () => encode(1.5),
        _argumentError("argument of type 'float' is not iterable"),
      );
      expect(
        () => encode(true),
        _argumentError("argument of type 'bool' is not iterable"),
      );
    });

    test('gives way to the fields a preset really filled', () {
      final reg = PresetRegistry([
        Preset('p', {'value': 'v'}),
      ]);
      final ctx = WireContext(presets: reg);
      final cell = Cell.fromJson({
        'preset_identifier': 'p',
        '\u0000wire_filled': 5,
      }, ctx);
      expect(cell.value, 'v');
      expect(cell.toJson(ctx), {
        'type_identifier': _cellId,
        'version': '1.0',
        'preset_identifier': 'p',
      });
    });

    test('is an unknown key of an object that adopts no preset', () {
      final size = Size.fromJson({
        'width': 1.0,
        'height': 2.0,
        '\u0000wire_filled': ['height'],
      });
      expect(size.toJson(), {
        'width': 1.0,
        'height': 2.0,
        'type_identifier': _sizeId,
        'version': '1.0',
        '\u0000wire_filled': ['height'],
      });
    });
  });

  group('a list case that is set is never factored out', () {
    final run = {'string': 'a', 'type_identifier': _runId, 'version': '1.0'};
    final paragraph = {'type_identifier': _paragraphId, 'version': '1.0'};
    final context = WireContext(
      presets: PresetRegistry([
        Preset('p', {
          'text_runs': [run],
        }),
        Preset('para', {
          'paragraphs': [paragraph],
        }),
      ]),
    );

    test('when decoded', () {
      final text = Text.fromJson({
        'preset_identifier': 'p',
        'text_runs': [run],
      }, context);
      expect(text.toJson(context), {
        'text_runs': [run],
        'type_identifier': _textId,
        'version': '1.0',
        'preset_identifier': 'p',
      });
      final paragraphs = Text.fromJson({
        'preset_identifier': 'para',
        'paragraphs': [paragraph],
      }, context);
      expect(paragraphs.toJson(context), {
        'paragraphs': [paragraph],
        'type_identifier': _textId,
        'version': '1.0',
        'preset_identifier': 'para',
      });
    });

    test('when constructed, beside another case', () {
      expect(
        Text(
          presetIdentifier: 'p',
          textRuns: [TextRun(string: 'a')],
        ).toJson(context),
        {
          'text_runs': [run],
          'type_identifier': _textId,
          'version': '1.0',
          'preset_identifier': 'p',
        },
      );
      expect(
        Text.fromJson({
          'preset_identifier': 'p',
          'string': 's',
          'text_runs': [run],
        }, context).toJson(context),
        {
          'string': 's',
          'text_runs': [run],
          'primary_case': 'string',
          'type_identifier': _textId,
          'version': '1.0',
          'preset_identifier': 'p',
        },
      );
    });

    test('while one the preset filled stays factored out', () {
      expect(
        Text.fromJson({'preset_identifier': 'p'}, context).toJson(context),
        {
          'type_identifier': _textId,
          'version': '1.0',
          'preset_identifier': 'p',
        },
      );
    });
  });

  group('messages quote identifiers with Python repr', () {
    test('missing presets and parents', () {
      for (final (id, quoted) in [
        ("it's", '"it\'s"'),
        ('both \' and "', r"""'both \' and "'"""),
        (r'back\slash', r"'back\\slash'"),
        ('nl\nx', r"'nl\nx'"),
        ('tab\tx', r"'tab\tx'"),
        ('ctl\x01', r"'ctl\x01'"),
        ('\u2028', r"'\u2028'"),
      ]) {
        final registry = PresetRegistry([]);
        CellProperties.fromJson({
          'preset_identifier': id,
        }, WireContext(presets: registry));
        expect(registry.warnings, ['missing preset $quoted']);
        final parents = PresetRegistry([Preset('p', {}, parentIdentifier: id)])
          ..resolvedProperties('p');
        expect(parents.warnings, ['missing preset $quoted']);
      }
    });

    test('a cycle', () {
      final registry = PresetRegistry([
        Preset("it's", {}, parentIdentifier: "it's"),
      ]);
      expect(
        () => registry.resolvedProperties("it's"),
        throwsA(
          isA<PresetCycleError>().having(
            (e) => '$e',
            'message',
            'circular preset `parent_identifier` chain at "it\'s"',
          ),
        ),
      );
    });

    test('an adoption encoded without the presets', () {
      expect(
        Size(width: 1, height: 2, presetIdentifier: 'a\nb').toJson,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            startsWith(r"Size: adopts preset 'a\nb', so encoding needs"),
          ),
        ),
      );
    });

    test('the floor warning sorts by code point and escapes', () {
      final messages = <String>[];
      final level = Logger.root.level;
      Logger.root.level = Level.ALL;
      final subscription = Logger.root.onRecord.listen(
        (r) => messages.add(r.message),
      );
      addTearDown(() {
        subscription.cancel();
        Logger.root.level = level;
      });
      Size.fromJson({
          'width': 1.0,
          'height': 2.0,
          'version': '1.5',
          '\uffff': 1,
          '\u{1f600}': 2,
          "it's": 3,
          'nl\nx': 4,
        })
        ..width = 3
        ..toJson();
      expect(
        messages.single,
        'Size: edited after decoding at 1.5. Its unknown keys '
        '["it\'s", \'nl\\nx\', \'\\uffff\', \'\u{1f600}\'] are kept, but a '
        'newer reader ignores any that are newer than the version written.',
      );
    });

    test('pyRepr matches Python', () {
      expect(pyRepr('\x7f'), r"'\x7f'");
      expect(pyRepr('\x80'), r"'\x80'");
      expect(pyRepr('\xa0'), r"'\xa0'");
      expect(pyRepr('é'), "'é'");
      expect(pyRepr('\u200b'), r"'\u200b'");
      expect(pyRepr('\u{e0001}'), r"'\U000e0001'");
      expect(pyRepr('\u{1f600}'), "'\u{1f600}'");
      expect(pyRepr('\ud800'), r"'\ud800'");
      expect(pyRepr(' '), "' '");
      for (final (value, repr) in [
        (1e16, '1e+16'),
        (1e15, '1000000000000000.0'),
        (1e-5, '1e-05'),
        (1e-4, '0.0001'),
        (1.5, '1.5'),
        (123456789012345680.0, '1.2345678901234568e+17'),
        (1e300, '1e+300'),
        (-0.0, '-0.0'),
        (2.5e-7, '2.5e-07'),
        (1.7976931348623157e308, '1.7976931348623157e+308'),
        (5e-324, '5e-324'),
      ]) {
        expect(pyRepr(value), repr);
      }
      expect(
        pyRepr({'major': 1, 'minor': 1e19}),
        "{'major': 1, 'minor': 1e+19}",
      );
      expect(['\uffff', '\u{1f600}', 'a']..sort(compareCodePoints), [
        'a',
        '\uffff',
        '\u{1f600}',
      ]);
    });
  });

  group('Preset.fromJson checks no types, like Preset.from_dict', () {
    test('properties that are not an object round-trip', () {
      for (final props in <Object?>[
        null,
        [1],
        'x',
      ]) {
        final preset = Preset.fromJson({
          'identifier': 'bad',
          'properties': props,
        });
        expect(preset.properties, isNull);
        expect(preset.toJson(), {'identifier': 'bad', 'properties': props});
      }
    });

    test('a registry with such a preset resolves the others', () {
      final registry = PresetRegistry([
        Preset.fromJson({'identifier': 'bad', 'properties': null}),
        Preset.fromJson({
          'identifier': 'badlist',
          'properties': [1],
        }),
        Preset.fromJson({
          'identifier': 'kid',
          'parent_identifier': 'bad',
          'properties': <String, Object?>{},
        }),
        Preset('p', {'text_wrap': true}),
      ]);
      final context = WireContext(presets: registry);
      final cell = CellProperties.fromJson({'preset_identifier': 'p'}, context);
      expect(cell.textWrap, isTrue);
      expect(cell.toJson(context), {
        'type_identifier':
            'com.apple.apps.content-language.table.cell-properties',
        'version': '1.0',
        'preset_identifier': 'p',
      });
      // Upstream raises `TypeError` once a resolution reaches the preset.
      expect(
        () => registry.resolvedProperties('bad'),
        _argumentError("'NoneType' object is not a mapping"),
      );
      expect(
        () => registry.resolvedProperties('badlist'),
        _argumentError("'list' object is not a mapping"),
      );
      expect(
        () => registry.resolvedProperties('kid'),
        _argumentError("'NoneType' object is not a mapping"),
      );
      expect(
        () => CellProperties.fromJson({'preset_identifier': 'bad'}, context),
        _argumentError("'NoneType' object is not a mapping"),
      );
    });

    test('an identifier that is not a string round-trips and is looked up', () {
      final preset = Preset.fromJson({
        'identifier': 5,
        'properties': {'text_wrap': true},
      });
      expect(preset.identifier, isNull);
      expect(preset.toJson(), {
        'identifier': 5,
        'properties': {'text_wrap': true},
      });
      // Python keys a dict by value: a parent `5.0` names the preset `5`, and
      // `true` names `1`.
      final registry = PresetRegistry([
        preset,
        Preset.fromJson({
          'identifier': 'c',
          'parent_identifier': 5.0,
          'properties': <String, Object?>{},
        }),
        Preset.fromJson({
          'identifier': 1,
          'properties': {'text_wrap': false},
        }),
        Preset.fromJson({
          'identifier': 'x',
          'parent_identifier': true,
          'properties': <String, Object?>{},
        }),
        Preset.fromJson({
          'identifier': 'y',
          'parent_identifier': 2.5,
          'properties': <String, Object?>{},
        }),
      ]);
      expect(registry.resolvedProperties('c'), {'text_wrap': true});
      expect(registry.resolvedProperties('x'), {'text_wrap': false});
      expect(registry.resolvedProperties('y'), isEmpty);
      expect(registry.warnings, ['missing preset 2.5']);
    });

    test('a cycle through identifiers that are not strings', () {
      final registry = PresetRegistry([
        Preset.fromJson({
          'identifier': 'a',
          'parent_identifier': 7,
          'properties': <String, Object?>{},
        }),
        Preset.fromJson({
          'identifier': 7,
          'parent_identifier': 7,
          'properties': <String, Object?>{},
        }),
      ]);
      expect(
        () => registry.resolvedProperties('a'),
        throwsA(
          isA<PresetCycleError>().having(
            (e) => '$e',
            'message',
            'circular preset `parent_identifier` chain at 7',
          ),
        ),
      );
      expect(registry.cycle, 7);
    });

    test('a list identifier is unhashable', () {
      expect(
        () => PresetRegistry([
          Preset.fromJson({
            'identifier': [1],
            'properties': <String, Object?>{},
          }),
        ]),
        _argumentError("unhashable type: 'list'"),
      );
    });

    test('a missing key is still rejected', () {
      expect(() => Preset.fromJson({'properties': {}}), throwsArgumentError);
      expect(() => Preset.fromJson({'identifier': 'x'}), throwsArgumentError);
    });
  });

  group('a version part must be an int, as upstream requires', () {
    test('Version.parse rejects any double part', () {
      expect(Version.parse({'major': 1e19}), isNull);
      expect(Version.parse({'major': 1, 'minor': 1e300}), isNull);
      expect(Version.parse({'major': 9223372036854775808.0}), isNull);
      expect(Version.parse({'major': 1.0}), isNull);
      expect(Version.parse({'major': 1, 'minor': 1e19}), isNull);
      expect(
        '${Version.parse({'major': 1, 'minor': BigInt.parse('10000000000000000000')})}',
        '1.10000000000000000000',
      );
      expect(Version.parse({'major': BigInt.from(-1)}), isNull);
    });

    test('decoding reports an unparsable version', () {
      for (final (text, repr) in [
        ('{"major": 1, "minor": 1e19}', "{'major': 1, 'minor': 1e+19}"),
        ('{"major": 1e19}', "{'major': 1e+19}"),
        ('{"major": 1, "minor": 1e300}', "{'major': 1, 'minor': 1e+300}"),
      ]) {
        expect(
          () => Size.fromJson(
            _json('{"width": 1.0, "height": 2.0, "q": 1, "version": $text}'),
          ),
          throwsA(
            isA<ModelValidationError>().having(
              (e) => e.issues.single.message,
              'message',
              'Value error, Size: unparsable version $repr',
            ),
          ),
        );
      }
      expect(
        () => Shadow.fromJson(
          _json(
            '{"none": null, "q": 1, "version": {"major": 1, "minor": 1e19}}',
          ),
        ),
        _invalid([_issue(const [], 'value_error')]),
      );
    });
  });
}
