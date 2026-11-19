// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

// Regression tests for a fourth round of differential runs against the
// upstream Python package. Every expectation was checked against upstream.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:test/test.dart';

import 'json_matchers.dart';

const _p = 'com.apple.apps.content-language.';

Matcher _issue(List<Object> location, String type) => isA<ValidationIssue>()
    .having((i) => i.location, 'location', location)
    .having((i) => i.type, 'type', type);

Matcher _invalid(List<Matcher> issues) => throwsA(
  isA<ModelValidationError>().having((e) => e.issues, 'issues', issues),
);

// The issue types of a validation error, whatever their locations.
Matcher _invalidTypes(List<String> types) => throwsA(
  isA<ModelValidationError>().having(
    (e) => [for (final i in e.issues) i.type],
    'issue types',
    types,
  ),
);

WireContext _ctx(List<Preset> presets, {bool strict = false}) =>
    WireContext(presets: PresetRegistry(presets), strictPresets: strict);

final _groupSelf = Preset('g', {
  'children': [
    {
      'group': {'preset_identifier': 'g'},
    },
  ],
});

void main() {
  group('a preset that adopts itself stops at the recursion guard', () {
    test('a model that relies on it reports the missing field', () {
      expect(
        () => Group.fromJson({'preset_identifier': 'g'}, _ctx([_groupSelf])),
        _invalid([
          _issue(const ['children'], 'missing'),
        ]),
      );
      expect(
        () => Group.fromJson({
          'children': [
            {
              'group': {'preset_identifier': 'g'},
            },
          ],
        }, _ctx([_groupSelf])),
        _invalid([
          _issue(const ['children', 0, 'group', 'children'], 'missing'),
        ]),
      );
    });

    test('a model with its own value decodes and encodes', () {
      final context = _ctx([_groupSelf]);
      final group = Group.fromJson({
        'preset_identifier': 'g',
        'children': [
          {'shape': <String, Object?>{}},
        ],
      }, context);
      expect(group.fieldsSet, {'children', 'preset_identifier'});
      expect(
        group.toJson(context),
        sameJsonInOrder({
          'children': [
            {
              'shape': {'type_identifier': '${_p}shape', 'version': '1.0'},
              'type_identifier': '${_p}canvas-object',
              'version': '1.0',
            },
          ],
          'type_identifier': '${_p}group',
          'version': '1.0',
          'preset_identifier': 'g',
        }),
      );
    });

    test('a union that relies on it has no case', () {
      final context = _ctx([
        Preset('c', {
          'group': {
            'children': [
              {'preset_identifier': 'c'},
            ],
          },
        }),
      ]);
      expect(
        () => CanvasObject.fromJson({'preset_identifier': 'c'}, context),
        _invalid([_issue(const [], 'value_error')]),
      );
    });

    test('a cycle through two presets reports the missing field', () {
      final context = _ctx([
        Preset('a', {
          'children': [
            {
              'group': {'preset_identifier': 'b'},
            },
          ],
        }),
        Preset('b', {
          'children': [
            {
              'group': {'preset_identifier': 'a'},
            },
          ],
        }),
      ]);
      expect(
        () => Group.fromJson({'preset_identifier': 'a'}, context),
        _invalid([
          _issue(const ['children'], 'missing'),
        ]),
      );
    });

    test('strict presets report the loop as recursion_loop', () {
      expect(
        () => Group.fromJson({
          'preset_identifier': 'g',
        }, _ctx([_groupSelf], strict: true)),
        _invalidTypes(['recursion_loop']),
      );
      final shape = Preset('s', {
        'text': {
          'paragraphs': [
            {
              'contents': [
                {
                  'inline_object': {
                    'shape': {'preset_identifier': 's'},
                  },
                },
              ],
            },
          ],
        },
      });
      // The gate validates the text, so the fill loops at the top level,
      // with or without strict presets.
      for (final strict in [false, true]) {
        expect(
          () => Shape.fromJson({
            'preset_identifier': 's',
          }, _ctx([shape], strict: strict)),
          _invalidTypes(['recursion_loop']),
        );
      }
    });
  });

  test('unionOf takes presetIdentifier', () {
    final registry = PresetRegistry([
      Preset.fromJson({
        'identifier': 'p',
        'properties': {'dropShadow': <String, Object?>{}},
      }),
    ]);
    final shadow = Shadow.unionOf('none', none: true, presetIdentifier: 'p');
    expect(shadow.fieldsSet, {'none', 'preset_identifier'});
    expect(
      shadow.toJson(WireContext(presets: registry)),
      sameJsonInOrder({
        'none': null,
        'primary_case': 'none',
        'type_identifier': '${_p}shadow',
        'version': '1.1',
        'preset_identifier': 'p',
      }),
    );
  });

  group('wireSet validates as setattr does', () {
    test('it rejects a value of the wrong type', () {
      expect(
        () => RGBA().wireSet('red', 'x'),
        _invalid([
          _issue(const ['red'], 'float_type'),
        ]),
      );
      expect(
        () => RGBA().wireSet('red', true),
        _invalid([
          _issue(const ['red'], 'float_type'),
        ]),
      );
      expect(
        () => RGBA().wireSet('red', null),
        _invalid([
          _issue(const ['red'], 'float_type'),
        ]),
      );
      expect(
        () => EqualColumnsDescription(count: 1).wireSet('count', 2.0),
        _invalid([
          _issue(const ['count'], 'int_type'),
        ]),
      );
      expect(
        () => SlideTarget(last: true).wireSet('first', false),
        _invalid([
          _issue(const ['first'], 'literal_error'),
        ]),
      );
      expect(
        () => Presentation(slides: [Slide()]).wireSet('slide_size', RGBA()),
        _invalid([
          _issue(const ['slide_size'], 'model_type'),
        ]),
      );
      expect(
        () => RGBA().wireSet('color_space', 'display_p3'),
        _invalid([
          _issue(const ['color_space'], 'enum'),
        ]),
      );
      expect(
        () =>
            UnequalColumnsDescription(columnWidths: [1])
                .wireSet('column_widths', [true]),
        _invalid([
          _issue(const ['column_widths', 0], 'float_type'),
        ]),
      );
    });

    test('it converts a value as validation does', () {
      final rgba = RGBA()..wireSet('red', 1);
      expect(rgba.red, isA<double>());
      expect(jsonEncode(rgba.toJson()), contains('"red":1.0'));
      expect(
        (UnequalColumnsDescription(
          columnWidths: [100],
        )..wireSet('column_widths', [50, 50])).columnWidths,
        everyElement(isA<double>()),
      );
      expect(
        jsonEncode(
          (UnformattedValue(text: 'a')..wireSet('number', 1)).toJson(),
        ),
        contains('"number":1.0'),
      );
      expect((RGBA()..wireSet('color_space', 'p3')).colorSpace, ColorSpace.p3);
      expect(
        (CellProperties()..wireSet('fill', null)).fill,
        const Override<Fill>.cleared(),
      );
      expect(
        (CharacterProperties()..wireSet('font_size', 12.0)).fontSize,
        const Override<double>.value(12),
      );
      final slides = Presentation(slides: [Slide()])
        ..wireSet('slide_size', {'width': 1, 'height': 2});
      expect(slides.slideSize, Size(width: 1, height: 2));
      expect((SlideTarget(last: true)..wireSet('first', 1)).first, isTrue);
    });
  });

  test('a union with no case reports a value_error', () {
    final noCase = _invalid([_issue(const [], 'value_error')]);
    expect(SlideTarget.new, noCase);
    expect(() => UnformattedValue.unionOf('number'), noCase);
    expect(() => SlideTarget(presetIdentifier: ''), noCase);
    expect(
      SlideTarget.new,
      throwsA(
        isA<ModelValidationError>().having(
          (e) => e.issues.single.message,
          'message',
          'Value error, SlideTarget: no case present',
        ),
      ),
    );
  });

  test('the schema keeps the member docs of every enum', () {
    final schema = jsonDecode(
      File('tool/schema.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final enums = [
      for (final e in schema['enums']! as List<Object?>)
        e! as Map<String, Object?>,
    ];
    final memberLine = RegExp(r'^\s*\S+ — ', multiLine: true);
    for (final e in enums) {
      expect(
        memberLine.hasMatch(e['doc']! as String),
        isFalse,
        reason: '${e['name']} keeps a member line in its own doc',
      );
    }
    Map<String, Object?> members(String name) => {
      for (final m
          in enums.firstWhere((e) => e['name'] == name)['members']!
              as List<Object?>)
        (m! as Map<String, Object?>)['value']! as String:
            (m as Map<String, Object?>)['doc'],
    };
    expect(
      members('Format')['circled'],
      'The number enclosed in a circle. Valid only with the `numeric` kind.',
    );
    expect(members('CombineMode').values, everyElement(isNotEmpty));
    expect(members('PredicateType').values, everyElement(isNotEmpty));
    expect(
      members('Name')['photo_portfolio1'],
      'The picture frame shown in Keynote as “Photo portfolio.”',
    );
  });
}
