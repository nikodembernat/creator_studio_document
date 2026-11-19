// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python): the doctests of
// core/_wire.py (`Override`, `ObjectModel`), and the construction, assignment,
// union, equality, and copy behavior that core/_wire.py implements.

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:test/test.dart';

Matcher _invalid(String type) => throwsA(
  isA<ModelValidationError>().having(
    (e) => e.issues.map((i) => i.type),
    'issue types',
    contains(type),
  ),
);

void main() {
  group('doctests', () {
    test('Override: a null property decodes as cleared', () {
      expect(CellProperties.fromJson({'fill': null}).fill.isCleared, isTrue);
    });

    test('ObjectModel: toJson writes the envelope', () {
      final dumped = Size(width: 100, height: 50).toJson();
      expect(
        (dumped['type_identifier'], dumped['version']),
        ('com.apple.apps.content-language.size', '1.0'),
      );
    });
  });

  group('Override', () {
    test('has three states', () {
      const notSet = Override<int>.notSet();
      const cleared = Override<int>.cleared();
      const value = Override.value(3);
      expect(
        [notSet.isNotSet, notSet.isCleared, notSet.isValue],
        [true, false, false],
      );
      expect(
        [cleared.isNotSet, cleared.isCleared, cleared.isValue],
        [false, true, false],
      );
      expect(
        [value.isNotSet, value.isCleared, value.isValue],
        [false, false, true],
      );
      expect([notSet.get(), cleared.get(), value.get()], [null, null, 3]);
    });

    test('compares by state and value', () {
      expect(
        const Override<num>.value(1),
        const Override<num>.value(1.5 - 0.5),
      );
      expect(const Override.value([1, 2]), const Override.value([1, 2]));
      expect(
        const Override<int>.cleared(),
        isNot(const Override<int>.notSet()),
      );
      expect(
        const Override<num>.value(1).hashCode,
        const Override<num>.value(1.5 - 0.5).hashCode,
      );
      expect('${const Override.value(2)}', 'Override.value(2)');
      expect('${const Override<int>.notSet()}', 'Override.notSet()');
    });

    test('switches exhaustively', () {
      String describe(Override<double> o) => switch (o) {
        OverrideNotSet() => 'inherit',
        OverrideCleared() => 'none',
        OverrideValue(:final value) => '$value',
      };
      expect(describe(const Override.value(2)), '2.0');
      expect(describe(const Override.cleared()), 'none');
    });

    test('a field defaults to not set and encodes by state', () {
      final cell = CellProperties();
      expect(cell.fill.isNotSet, isTrue);
      expect(cell.toJson().containsKey('fill'), isFalse);
      cell.fill = const Override.cleared();
      expect(cell.toJson()['fill'], isNull);
      expect(cell.toJson().containsKey('fill'), isTrue);
      cell.fill = Override.value(Fill(color: Color(rgba: RGBA(red: 1))));
      expect(
        ((cell.toJson()['fill']! as Map)['color']! as Map)['type_identifier'],
        'com.apple.apps.content-language.color',
      );
    });
  });

  group('construction and assignment', () {
    test('arguments mark fields set; defaults do not', () {
      final shape = Shape(identifier: 's', opacity: 1);
      expect(shape.fieldsSet, {'identifier', 'opacity'});
      expect(shape.aspectRatioLocked, isFalse);
      expect(shape.head, LineEnd.none);
      expect(shape.stroke.line, isNotNull);
      expect(shape.toJson(), {
        'identifier': 's',
        'opacity': 1.0,
        'type_identifier': 'com.apple.apps.content-language.shape',
        'version': '1.0',
      });
      shape.head = LineEnd.filledArrow;
      expect(shape.fieldsSet, contains('head'));
      expect(shape.toJson()['head'], 'filled_arrow');
    });

    test('each instance gets a fresh default', () {
      final a = Shape();
      final b = Shape();
      expect(identical(a.stroke, b.stroke), isFalse);
      expect(a.stroke, b.stroke);
    });

    test('constraints apply on construction', () {
      expect(() => RGBA(red: 5), _invalid('less_than_equal'));
      expect(() => RGBA(green: -1), _invalid('greater_than_equal'));
      expect(() => Group(children: []), _invalid('too_short'));
      expect(
        () => UnequalColumnsDescription(columnWidths: List.filled(11, 1)),
        _invalid('too_long'),
      );
      expect(
        () => Size(width: double.nan, height: 1),
        _invalid('finite_number'),
      );
      expect(
        () => UnequalColumnsDescription(columnWidths: [double.infinity]),
        _invalid('finite_number'),
      );
    });

    test('constraints apply on assignment', () {
      final rgba = RGBA();
      expect(() => rgba.red = 2, _invalid('less_than_equal'));
      expect(rgba.red, 0);
      expect(rgba.fieldsSet, isEmpty);
      rgba.red = 1;
      expect(rgba.red, 1.0);
      expect(rgba.fieldsSet, {'red'});
    });

    test('decoding enforces strict types', () {
      expect(
        () => Size.fromJson({'width': true, 'height': 1}),
        _invalid('float_type'),
      );
      expect(
        () => Table.fromJson({'number_of_columns': 1.0, 'number_of_rows': 1}),
        _invalid('int_type'),
      );
      expect(() => Label.fromJson({'is_visible': 1}), _invalid('bool_type'));
      expect(() => Shape.fromJson({'identifier': 1}), _invalid('string_type'));
      expect(() => Shape.fromJson({'head': 'nope'}), _invalid('enum'));
      expect(Size.fromJson({'width': 1, 'height': 2}).width, isA<double>());
    });

    test('a ModelValidationError lists every issue with its path', () {
      try {
        Group.fromJson({
          'children': [
            {'shape': <String, Object?>{}},
            5,
            {
              'shape': {'identifier': 3},
            },
          ],
        });
        fail('expected a ModelValidationError');
      } on ModelValidationError catch (e) {
        expect(e.title, 'Group');
        expect(e.issues.map((i) => i.path), [
          'children.1',
          'children.2.shape.identifier',
        ]);
        expect('$e', startsWith('2 validation errors for Group\n'));
      }
    });
  });

  group('unknown keys', () {
    test('are kept in order and can be edited', () {
      final size = Size.fromJson({
        'zeta': 1,
        'width': 1,
        'alpha': [1, 2],
        'height': 2,
      });
      expect(size.extras, {
        'zeta': 1,
        'alpha': [1, 2],
      });
      size.extras['zeta'] = 'changed';
      expect(size.toJson().keys, [
        'width',
        'height',
        'type_identifier',
        'version',
        'zeta',
        'alpha',
      ]);
      expect(size.toJson()['zeta'], 'changed');
    });
  });

  group('tagged unions', () {
    test('a union needs a case unless it adopts a preset', () {
      expect(CanvasObject.new, _invalid('value_error'));
      expect(CanvasObject(presetIdentifier: 'p').unionPrimary(), isNull);
    });

    test('a lone valueless case encodes as a bare string', () {
      expect(Stroke(empty: true).toJson(), 'empty');
      expect(Stroke.fromJson('empty').empty, isTrue);
      expect(Stroke(empty: false, line: Line()).empty, isFalse);
    });

    test('the primary is the newest case unless one is designated', () {
      final both = CanvasObject(shape: Shape(), textbox: Textbox());
      expect(both.unionPrimaryName(), 'textbox');
      expect([for (final c in both.unionCases()) c.name], ['textbox', 'shape']);
      final pinned = CanvasObject.unionOf(
        'shape',
        shape: Shape(),
        textbox: Textbox(),
      );
      expect(pinned.unionPrimaryName(), 'shape');
      expect((pinned.toJson() as Map)['primary_case'], 'shape');
      expect(pinned, isNot(both));
    });

    test('unionOf rejects an unknown primary', () {
      expect(
        () => Chart.unionOf('nope', column: ColumnChart()),
        throwsArgumentError,
      );
    });

    test('unionPrimary switches exhaustively', () {
      String describe(Stroke stroke) => switch (stroke.unionPrimary()) {
        StrokeEmptyCase() => 'none',
        StrokeFrameCase(:final payload) => 'frame ${payload.name.wireValue}',
        StrokeLineCase(:final payload) => 'line ${payload.width}',
        null => 'unset',
      };
      expect(describe(Stroke(line: Line(width: 2))), 'line 2.0');
      expect(describe(Stroke.fromJson('empty')), 'none');
      expect(describe(Stroke(presetIdentifier: 'p')), 'unset');
    });

    test('unknown cases are preserved', () {
      final chart = Chart.fromJson({
        'column': <String, Object?>{},
        'super_axis': <String, Object?>{},
        'primary_case': 'super_axis',
      });
      // test_version_drift.py: a known primary stays readable.
      expect(chart.unionPrimaryName(), 'column');
      expect(chart.extras.keys, ['super_axis']);
      expect((chart.toJson() as Map)['primary_case'], 'super_axis');
    });

    test('assigning a case keeps the designation', () {
      final chart = Chart.unionOf('column', column: ColumnChart())
        ..bar = BarChart();
      expect(chart.unionPrimaryName(), 'column');
    });
  });

  group('equality and copies', () {
    test('compares fields and unknown keys, not which fields are set', () {
      expect(
        Size(width: 1, height: 2),
        Size.fromJson({'width': 1.0, 'height': 2}),
      );
      expect(
        Size(width: 1, height: 2).hashCode,
        Size.fromJson({'width': 1.0, 'height': 2}).hashCode,
      );
      expect(
        Size(width: 1, height: 2),
        isNot(Size.fromJson({'width': 1, 'height': 2, 'x': 1})),
      );
      expect(Shape(), Shape(opacity: 1));
    });

    test('a deep copy is equal and independent', () {
      final original = Group(
        children: [CanvasObject(shape: Shape(identifier: 'a'))],
      );
      final copy = original.deepCopy();
      expect(copy, original);
      copy.children.first.shape!.identifier = 'b';
      expect(original.children.first.shape!.identifier, 'a');
      expect(copy, isNot(original));
      expect(copy.children, isA<List<CanvasObject>>());
    });

    test('a deep copy keeps the designated primary and set fields', () {
      final pinned = Chart.unionOf(
        'column',
        column: ColumnChart(),
        bar: BarChart(),
      );
      final copy = pinned.deepCopy();
      expect(copy.unionPrimaryName(), 'column');
      expect(copy.fieldsSet, pinned.fieldsSet);
    });
  });

  group('registry', () {
    test('maps every type identifier to its schema', () {
      expect(modelSchemas, hasLength(193));
      for (final MapEntry(:key, :value) in modelSchemas.entries) {
        expect(value.typeId, key);
        expect(modelFor(key), same(value));
      }
      expect(modelFor('nope'), isNull);
      expect(
        modelFor('com.apple.apps.content-language.size')!
            .fromJson({'width': 1, 'height': 2}),
        Size(width: 1, height: 2),
      );
    });
  });

  group('sameJson', () {
    test('compares numbers by value but never booleans with numbers', () {
      expect(sameJson(1, 1.0), isTrue);
      expect(sameJson(true, 1), isFalse);
      expect(sameJson(0, false), isFalse);
      expect(sameJson(true, true), isTrue);
    });

    test('ignores key order but not array order or absent keys', () {
      expect(sameJson({'a': 1, 'b': 2}, {'b': 2, 'a': 1}), isTrue);
      expect(sameJson([1, 2], [2, 1]), isFalse);
      expect(sameJson({'a': null}, <String, Object?>{}), isFalse);
      expect(sameJson('1', 1), isFalse);
      expect(
        sameJson(
          {
            'a': [
              {'b': 1.0},
            ],
          },
          {
            'a': [
              {'b': 1},
            ],
          },
        ),
        isTrue,
      );
    });
  });
}
