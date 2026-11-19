// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

// Regression tests for mismatches that differential runs against the upstream
// Python package found. Every expectation was checked against upstream.

import 'dart:convert';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:test/test.dart';

const _shapeId = 'com.apple.apps.content-language.shape';
const _strokeId = 'com.apple.apps.content-language.stroke';
const _lineId = 'com.apple.apps.content-language.stroke.line';

Map<String, Object?> _shapeWithWidth(Object width) => {
  'stroke': {
    'line': {'width': width, 'type_identifier': _lineId, 'version': '1.0'},
    'type_identifier': _strokeId,
    'version': '1.0',
  },
  'type_identifier': _shapeId,
  'version': '1.0',
};

Matcher _issue(List<Object> location, String type) => isA<ValidationIssue>()
    .having((i) => i.location, 'location', location)
    .having((i) => i.type, 'type', type);

Matcher _invalid(List<Matcher> issues) => throwsA(
  isA<ModelValidationError>().having((e) => e.issues, 'issues', issues),
);

void main() {
  group('the preset gate keeps the constraints of nested models', () {
    test('a nested value that breaks `ge` fills nothing', () {
      final context = WireContext(
        presets: PresetRegistry([
          Preset('p', {
            'text_wrap': true,
            'padding': {'top': -5},
          }),
        ]),
      );
      final cell = CellProperties.fromJson({'preset_identifier': 'p'}, context);
      expect(cell.textWrap, isTrue);
      expect(cell.padding, isNull);
      expect(cell.toJson(context), {
        'type_identifier':
            'com.apple.apps.content-language.table.cell-properties',
        'version': '1.0',
        'preset_identifier': 'p',
      });
    });

    test('a union case that breaks `le` fills nothing', () {
      final context = WireContext(
        presets: PresetRegistry([
          Preset('p', {
            'dropShadow': {'angle': 1000},
          }),
        ]),
      );
      expect(
        () => Shadow.fromJson({'preset_identifier': 'p'}, context),
        _invalid([_issue(const [], 'value_error')]),
      );
    });

    test('a chain that reaches the gate depth still decodes', () {
      final presets = [
        Preset('z', {
          'properties': {'preset_identifier': 'a'},
        }),
        Preset('a', {
          'fill': {'preset_identifier': 'b'},
        }),
        Preset('b', {
          'color': {'preset_identifier': 'c'},
        }),
        Preset('c', {
          'rgba': {'preset_identifier': 'd'},
        }),
        Preset('d', {'red': 2}),
      ];
      final style = CellStyle.fromJson({
        'preset_identifier': 'z',
      }, WireContext(presets: PresetRegistry(presets)));
      expect(style.properties.presetIdentifier, 'a');
      expect(style.properties.fill.isNotSet, isTrue);
      expect(style.toJson(WireContext(presets: PresetRegistry(presets))), {
        'type_identifier': 'com.apple.apps.content-language.stylesheet.table-style-collection.cell-style',
        'version': '1.0',
        'preset_identifier': 'z',
      });
    });

    test('encoding sees no fill from an invalid nested value', () {
      final context = WireContext(
        presets: PresetRegistry([
          Preset('p', {
            'padding': {'top': -5},
          }),
          Preset('s', {
            'dropShadow': {'angle': 1000},
          }),
        ]),
      );
      final cell = CellProperties(presetIdentifier: 'p')..padding = null;
      expect(cell.toJson(context), isNot(contains('padding')));
      expect(
        () => Shadow(presetIdentifier: 's').toJson(context),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            "Shadow: can't encode with no case set, and preset 's' supplies "
                'none',
          ),
        ),
      );
    });
  });

  group('Preset.fromJson keeps optional values that are not strings', () {
    test('a map display_name round-trips', () {
      final preset = Preset.fromJson({
        'identifier': 'a',
        'display_name': {'en': 'X'},
        'properties': <String, Object?>{},
      });
      expect(preset.displayName, isNull);
      expect(preset.toJson(), {
        'identifier': 'a',
        'display_name': {'en': 'X'},
        'properties': <String, Object?>{},
      });
    });

    test('a number parent_identifier round-trips and is missing', () {
      final preset = Preset.fromJson({
        'identifier': 'a',
        'display_name': 5,
        'parent_identifier': 7,
        'properties': {'text_wrap': true},
      });
      expect(preset.toJson(), {
        'identifier': 'a',
        'display_name': 5,
        'parent_identifier': 7,
        'properties': {'text_wrap': true},
      });
      final registry = PresetRegistry([preset]);
      expect(registry.resolvedProperties('a'), {'text_wrap': true});
      expect(registry.warnings, ['missing preset 7']);
    });

    test('assigning a string replaces the raw value', () {
      final preset = Preset.fromJson({
        'identifier': 'a',
        'parent_identifier': 7,
        'properties': <String, Object?>{},
      })..parentIdentifier = 'b';
      expect(preset.toJson()['parent_identifier'], 'b');
    });
  });

  test('a list type_identifier in a preset value fails like upstream', () {
    // Upstream raises `TypeError: unhashable type: 'list'`.
    final context = WireContext(
      presets: PresetRegistry([
        Preset('p', {
          'padding': {
            'type_identifier': [1],
            'top': 5,
          },
        }),
      ]),
    );
    expect(
      () => CellProperties.fromJson({'preset_identifier': 'p'}, context),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          "unhashable type: 'list'",
        ),
      ),
    );
  });

  group('a valueless case accepts what equals True', () {
    for (final input in <Object>[1, 1.0, true]) {
      test('$input (${input.runtimeType})', () {
        expect(Shadow.fromJson({'none': input}).toJson(), 'none');
        expect(Magnet.fromJson({'center': input}).center, isTrue);
      });
    }

    test('nested', () {
      expect(
        Anchor.fromJson({
          'object_id': 'x',
          'magnet': {'center': 1.0},
        }).toJson()['magnet'],
        'center',
      );
    });

    for (final input in <Object>[0, 2, 1.5, 'true', false]) {
      test('rejects $input', () {
        expect(
          () => Shadow.fromJson({'none': input}),
          _invalid([
            _issue(const ['none'], 'literal_error'),
          ]),
        );
      });
    }

    test('reports only the other issues', () {
      expect(
        () => Stroke.fromJson({'empty': 1, 'frame': <String, Object?>{}}),
        _invalid([
          _issue(const ['frame', 'name'], 'missing'),
        ]),
      );
    });
  });

  group('versions beyond 64 bits', () {
    test('parse exactly', () {
      expect(
        '${Version.parse('99999999999999999999')}',
        '99999999999999999999.0',
      );
      expect(
        '${Version.parse('1.99999999999999999999')}',
        '1.99999999999999999999',
      );
      expect(
        '${Version.parse({'major': BigInt.parse('100000000000000000000')})}',
        '100000000000000000000.0',
      );
      expect(Version.parse({'major': 1e20, 'minor': -1.0}), isNull);
      expect(
        Version.parse('1.99999999999999999999')! > const Version(1, 99),
        isTrue,
      );
      expect(
        Version.parse('1.99999999999999999999'),
        Version.parse('01.099999999999999999999'),
      );
    });

    for (final version in <Object>[
      '99999999999999999999',
      '9223372036854775808.0',
      {'major': BigInt.parse('100000000000000000000')},
    ]) {
      test('a huge major is a newer major ($version)', () {
        expect(
          () => Size.fromJson({'width': 1, 'height': 2, 'version': version}),
          throwsA(
            isA<DocumentVersionError>().having(
              (e) => e.message,
              'message',
              startsWith(
                'Size: input declares version ${Version.parse(version)} but',
              ),
            ),
          ),
        );
      });
    }

    test('a huge minor decodes, and the floor keeps it', () {
      final size = Size.fromJson({
        'width': 1,
        'height': 2,
        'version': '1.99999999999999999999',
        'zz': 1,
      });
      expect(size.toJson(), {
        'width': 1.0,
        'height': 2.0,
        'type_identifier': 'com.apple.apps.content-language.size',
        'version': '1.99999999999999999999',
        'zz': 1,
      });
      expect(
        Size.fromJson({
          'width': 1,
          'height': 2,
          'version': '1.9223372036854775808',
        }).toJson()['version'],
        '1.0',
      );
    });
  });

  group('union float cases reject NaN and infinities', () {
    Matcher finite(String key) => _invalid([
      _issue([key], 'finite_number'),
    ]);

    test('on construction', () {
      expect(() => ChartDataValue(number: double.nan), finite('number'));
      expect(() => Duration(seconds: double.infinity), finite('seconds'));
      expect(
        () => Value(duration: double.negativeInfinity),
        finite('duration'),
      );
      expect(() => AxisLabelOrientation(custom: double.nan), finite('custom'));
      expect(() => UnformattedValue(number: double.nan), finite('number'));
    });

    test('on assignment, keeping the old value', () {
      final value = ChartDataValue(number: 1);
      expect(() => value.number = double.nan, finite('number'));
      expect(value.number, 1.0);
      final unformatted = UnformattedValue(number: 1);
      expect(() => unformatted.number = double.infinity, finite('number'));
      expect(unformatted.toJson(), {
        'number': 1.0,
        'type_identifier': unformatted.wireSchema.typeId,
        'version': '1.0',
      });
    });
  });

  group('a model never shares a list with the caller', () {
    test('on construction', () {
      final widths = <double>[1];
      final description = UnequalColumnsDescription(columnWidths: widths);
      widths.add(2);
      expect(description.columnWidths, [1.0]);
      expect(identical(description.columnWidths, widths), isFalse);
    });

    test('on assignment, so constraints keep holding', () {
      final description = UnequalColumnsDescription(columnWidths: [1]);
      final widths = List<double>.filled(10, 1, growable: true);
      description.columnWidths = widths;
      widths.add(3);
      expect(description.toJson()['column_widths'], hasLength(10));
    });

    test('keeps the element type', () {
      final description = UnequalColumnsDescription(columnWidths: [1.0]);
      expect(description.columnWidths, isA<List<double>>());
    });
  });

  test('a NaN put in place into a float list encodes as null', () {
    final description = UnequalColumnsDescription(columnWidths: [1.0]);
    description.columnWidths.add(double.nan);
    final json = description.deepCopy().toJson();
    expect(json['column_widths'], [1.0, null]);
    expect(() => jsonEncode(json), returnsNormally);
  });

  test('fieldsSet holds the unknown keys that decoding kept', () {
    final stop = Stop.fromJson({
      'fraction': 0.5,
      'color': {'rgba': <String, Object?>{}},
      'zz': 1,
      'aa': {'b': null},
    });
    expect([...stop.fieldsSet]..sort(), ['aa', 'color', 'fraction', 'zz']);
    expect([...stop.deepCopy().fieldsSet]..sort(), [
      'aa',
      'color',
      'fraction',
      'zz',
    ]);
    expect(
      [
        ...Magnet.fromJson({'center': null, 'zz': 1}).fieldsSet,
      ]..sort(),
      ['center', 'zz'],
    );
  });

  group('an int default tells an untouched field from one set in place', () {
    test('a default stroke edited to the default width is written', () {
      final shape = Shape();
      shape.stroke.line!.width = 1.0;
      expect(shape.toJson(), _shapeWithWidth(1.0));
      final textbox = Textbox();
      textbox.stroke.line!.width = 1.0;
      expect(textbox.toJson()['stroke'], _shapeWithWidth(1.0)['stroke']);
    });

    test('also after decoding, a second edit, or a copy', () {
      final decoded = Shape.fromJson(<String, Object?>{});
      decoded.stroke.line!.width = 1.0;
      expect(decoded.toJson(), _shapeWithWidth(1.0));

      final twice = Shape();
      twice.stroke.line!
        ..width = 2.0
        ..width = 1.0;
      expect(twice.toJson(), _shapeWithWidth(1.0));

      final original = Shape();
      final copy = original.deepCopy();
      copy.stroke.line!.width = 1.0;
      expect(copy.toJson(), _shapeWithWidth(1.0));
      expect(original.toJson(), {
        'type_identifier': _shapeId,
        'version': '1.0',
      });
    });

    test('an untouched default stays out, and == ignores the difference', () {
      expect(Shape().toJson(), {'type_identifier': _shapeId, 'version': '1.0'});
      expect(Line(width: 1), Line());
      expect(Line().toJson(), {'type_identifier': _lineId, 'version': '1.0'});
    });
  });
}
