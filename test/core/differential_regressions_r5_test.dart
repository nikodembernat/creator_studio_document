// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

// Regression tests for a fifth round of differential runs against the
// upstream Python package. Every expectation was checked against upstream,
// except where a test pins a documented difference (see README).

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:test/test.dart';

import 'json_matchers.dart';

const _p = 'com.apple.apps.content-language.';

const _filledKey = '\u0000wire_filled';

Matcher _invalid(List<List<Object>> issues) => throwsA(
  isA<ModelValidationError>().having(
    (e) => [
      for (final i in e.issues) [i.location, i.type, i.message],
    ],
    'issues',
    issues,
  ),
);

WireContext _ctx(List<Preset> presets) =>
    WireContext(presets: PresetRegistry(presets));

void main() {
  group('the fields set of an object a preset filled', () {
    final context = _ctx([
      Preset('p', {'text_wrap': true}),
    ]);

    test("holds upstream's hand-over key, as model_fields_set does", () {
      final cell = CellProperties.fromJson({'preset_identifier': 'p'}, context);
      expect(cell.textWrap, isTrue);
      expect(cell.fieldsSet, {'preset_identifier', _filledKey});
      expect(cell.extras, isEmpty);
      expect(cell.deepCopy().fieldsSet, {'preset_identifier', _filledKey});
      cell.textWrap = false;
      expect(cell.fieldsSet, {'preset_identifier', _filledKey, 'text_wrap'});
    });

    test('lacks it when nothing was filled', () {
      expect(
        CellProperties.fromJson({
          'preset_identifier': 'p',
          'text_wrap': false,
        }, context).fieldsSet,
        {'preset_identifier', 'text_wrap'},
      );
      expect(CellProperties.fromJson({'preset_identifier': 'p'}).fieldsSet, {
        'preset_identifier',
      });
    });

    test('the key never reaches the JSON', () {
      final cell = CellProperties.fromJson({'preset_identifier': 'p'}, context);
      expect(
        cell.toJson(context),
        sameJsonInOrder({
          'type_identifier': '${_p}table.cell-properties',
          'version': '1.0',
          'preset_identifier': 'p',
        }),
      );
    });
  });

  group('a list longer than max_length reports only too_long', () {
    const cwTooLong = [
      ['column_widths'],
      'too_long',
      'List should have at most 10 items after validation, not 11',
    ];
    const gwTooLong = [
      ['gutter_widths'],
      'too_long',
      'List should have at most 9 items after validation, not 10',
    ];

    test('on decode, whatever its items hold', () {
      expect(
        () => UnequalColumnsDescription.fromJson({
          'column_widths': List.filled(11, 'x'),
        }),
        _invalid([cwTooLong]),
      );
      expect(
        () => UnequalColumnsDescription.fromJson({
          'column_widths': [1.0],
          'gutter_widths': List.filled(10, true),
        }),
        _invalid([gwTooLong]),
      );
      expect(
        () => UnequalColumnsDescription.fromJson({
          'column_widths': List.filled(11, 'x'),
          'gutter_widths': 'nope',
        }),
        _invalid([
          cwTooLong,
          [
            ['gutter_widths'],
            'list_type',
            'Input should be a valid list',
          ],
        ]),
      );
    });

    test('on construction and assignment', () {
      expect(
        () => UnequalColumnsDescription(
          columnWidths: List.filled(11, double.nan),
        ),
        _invalid([cwTooLong]),
      );
      expect(
        () => UnequalColumnsDescription(columnWidths: [1.0]).columnWidths =
            List.filled(11, double.infinity),
        _invalid([cwTooLong]),
      );
    });

    test('a list within the limit still reports its items', () {
      expect(
        () => UnequalColumnsDescription(
          columnWidths: [...List<double>.filled(9, 1), double.nan],
        ),
        _invalid([
          [
            ['column_widths', 9],
            'finite_number',
            'Input should be a finite number',
          ],
        ]),
      );
      expect(
        () => UnequalColumnsDescription.fromJson({
          'column_widths': [...List.filled(9, 1), 'x'],
        }),
        _invalid([
          [
            ['column_widths', 9],
            'float_type',
            'Input should be a valid number',
          ],
        ]),
      );
    });
  });

  // Upstream's results here come from Pydantic running a nested model's wrap
  // validator or serializer twice. The port keeps to what upstream does for
  // the same model at the top level; see "Differences from upstream" in the
  // README.
  group('documented differences: a nested model is coded once', () {
    test('a nested CanvasObject keeps to its declared version', () {
      final context = _ctx([
        Preset('p', {
          'textbox': {'description': 'from preset'},
        }),
      ]);
      final object = <String, Object?>{
        'genericCanvasObject': <String, Object?>{},
        'version': '1.0',
        'preset_identifier': 'p',
      };
      final nested = SlideObject.fromJson({'object': object}, context).object;
      final top = CanvasObject.fromJson(object, context);
      for (final o in [nested, top]) {
        expect(
          [for (final (name, _) in o.unionCaseEntries()) name],
          ['genericCanvasObject'],
        );
        expect(
          o.toJson(context),
          sameJsonInOrder({
            'genericCanvasObject': {
              'type_identifier': '${_p}canvas-object-generic',
              'version': '1.0',
            },
            'type_identifier': '${_p}canvas-object',
            'version': '1.0',
            'preset_identifier': 'p',
          }),
        );
      }
    });

    test('a nested Label leaves a factored-out field out', () {
      final context = _ctx([
        Preset('L', {'is_visible': false}),
      ]);
      final shape = Shape.fromJson({
        'title': {'is_visible': false, 'preset_identifier': 'L'},
      }, context);
      final json = shape.toJson(context);
      expect(
        json['title'],
        sameJsonInOrder({
          'type_identifier': '${_p}label',
          'version': '1.0',
          'preset_identifier': 'L',
        }),
      );
      expect(Shape.fromJson(json, context), shape);
    });

    test('TransformationInfo.base_table leaves a required field out', () {
      final context = _ctx([
        Preset('T', {'number_of_columns': 1, 'number_of_rows': 1}),
      ]);
      final info = TransformationInfo.fromJson({
        'base_table': {
          'number_of_columns': 1,
          'number_of_rows': 1,
          'preset_identifier': 'T',
        },
      }, context);
      final json = info.toJson(context);
      expect(
        json['base_table'],
        sameJsonInOrder({
          'type_identifier': '${_p}table',
          'version': '1.0',
          'preset_identifier': 'T',
        }),
      );
      expect(TransformationInfo.fromJson(json, context), info);
    });
  });
}
