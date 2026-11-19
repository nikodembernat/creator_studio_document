// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/test_field_types.py.
//
// Upstream corrupts models past Pydantic's validation: it appends a wrong
// model to a typed list, writes `__dict__` directly, deletes a field, or uses
// `model_construct` and `model_copy(update=...)`. A Dart model's typed
// fields, typed lists, and validating setters rule all of these out, so those
// cases check that Dart rejects the corruption where it happens. The cases
// that Dart can reach, an in-place change to a list or a union, check that
// `validateFieldTypes` catches it.

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/src/validation/field_types.dart';
import 'package:creator_studio_document/src/validation/resolve.dart';
import 'package:creator_studio_document/validation.dart';
import 'package:test/test.dart';

import 'builders.dart';

KeyxDocument _docWithSlide() =>
    KeyxDocument(Presentation(slides: [Slide(identifier: 's1')]));

Color _white() => Color(rgba: RGBA(red: 1, green: 1, blue: 1, alpha: 1));

void main() {
  test('a wrong model appended to a typed list is rejected '
      '(test_wrong_model_appended_to_a_typed_list)', () {
    final doc = _docWithSlide();
    expect(
      () => (doc.payload.slides as List<Object?>).add(Paragraph()),
      throwsA(isA<TypeError>()),
    );
    validateDocument(doc);
  });

  test('a wrong model in a model field is rejected '
      '(test_wrong_model_in_a_scalar_position_field)', () {
    final doc = _docWithSlide();
    expect(
      () => doc.payload.slides[0].wireSet('note', Fill(color: _white())),
      throwsA(isA<ModelValidationError>()),
    );
    validateDocument(doc);
  });

  test('a value that is not a model spliced into a typed list is rejected '
      '(test_non_model_spliced_into_a_typed_list)', () {
    final doc = _docWithSlide();
    expect(
      () => (doc.payload.slides as List<Object?>)[0] = 42,
      throwsA(isA<TypeError>()),
    );
    validateDocument(doc);
  });

  test('a scalar of the wrong type is rejected '
      '(test_scalar_corrupted_past_setattr)', () {
    final doc = _docWithSlide();
    expect(
      () => doc.payload.slides[0].wireSet('identifier', 12345),
      throwsA(isA<ModelValidationError>()),
    );
    expect(doc.payload.slides[0].identifier, 's1');
  });

  test("a required field can't be deleted "
      '(test_deleted_field_is_named_rather_than_emitted_as_null)', () {
    final doc = _docWithSlide();
    expect(
      () => doc.payload.wireSet('slides', null),
      throwsA(isA<ModelValidationError>()),
    );
    expect(doc.payload.slides, hasLength(1));
  });

  test("a required field can't be left unset "
      '(test_required_field_model_construct_never_supplied)', () {
    expect(
      () => Presentation.fromJson(<String, Object?>{}),
      throwsA(
        isA<ModelValidationError>().having(
          (e) => '${e.issues.single}',
          'issue',
          'slides: Field required',
        ),
      ),
    );
  });

  for (final (name, override) in [
    ('not_set', const Override<TextStroke>.notSet()),
    ('cleared', const Override<TextStroke>.cleared()),
    ('value', Override.value(TextStroke(none: true))),
  ]) {
    test('every override state is accepted: $name '
        '(test_every_override_state_is_accepted[$name])', () {
      validateFieldTypes(BorderStyleType(stroke: override));
    });
  }

  test('an override of a wrongly typed value is rejected '
      '(test_override_carrying_a_wrongly_typed_value)', () {
    final model = BorderStyleType();
    expect(
      () => model.wireSet('stroke', const Override.value('not-a-stroke')),
      throwsA(isA<ModelValidationError>()),
    );
    validateFieldTypes(model);
  });

  test('an ill-typed bare value where an override is declared is rejected '
      '(test_bare_value_where_an_override_is_declared[ill_typed])', () {
    expect(
      () => BorderStyleType().wireSet('stroke', 'bare'),
      throwsA(isA<ModelValidationError>()),
    );
  });

  test('a well-typed bare value where an override is declared is wrapped '
      '(test_bare_value_where_an_override_is_declared[well_typed])', () {
    final model = BorderStyleType()..wireSet('stroke', TextStroke(none: true));
    expect(model.stroke, Override.value(TextStroke(none: true)));
    validateFieldTypes(model);
  });

  test('a bare value is wrapped where the serializer would reject it '
      '(test_bare_override_is_caught_where_the_serializer_would_have_caught_'
      'it)', () {
    final model = BorderStyleType()..wireSet('width', 3);
    expect(model.width, const Override<double>.value(3));
    expect(model.toJson()['width'], 3.0);
    validateFieldTypes(model);
  });

  test('an emptied list below its minimum length is rejected '
      '(test_emptied_list_violating_min_length)', () {
    final doc = _docWithSlide();
    doc.payload.slides.clear();
    expect(
      () => validateFieldTypes(doc.payload),
      throwsValueError(
        '`Presentation.slides` holds a value its field declaration rejects '
        '(at slides). $revalidateHint Validation errors:\n'
        '  at slides: List should have at least 1 item after validation, '
        'not 0 (got [])',
      ),
    );
  });

  test('the hint names the Dart way to skip validation, as the README '
      'documents', () {
    // Upstream's hint names in-place mutation, `model_construct`, and
    // `model_copy(update=...)`; only the first exists in Dart.
    final doc = _docWithSlide();
    doc.payload.slides.clear();
    expect(
      () => validateDocument(doc),
      throwsValueError(
        '`Presentation.slides` holds a value its field declaration rejects '
        '(at slides). An in-place change, such as to a list, likely set the '
        'value, and it skips validation. Reassign the field to revalidate it. '
        'Validation errors:\n'
        '  at slides: List should have at least 1 item after validation, '
        'not 0 (got [])',
      ),
    );
  });

  test('forward-compatible unknown keys are not flagged '
      '(test_forward_compatible_extra_keys_are_not_flagged)', () {
    final doc = _docWithSlide();
    doc.payload.slides[0].extras['future_field'] = {'a': 1};
    validateDocument(doc);
  });

  test('a clean document passes (test_a_clean_document_passes)', () {
    validateDocument(_docWithSlide());
  });

  group('in-place changes that Dart can reach', () {
    test('a list grown past its maximum length', () {
      final model = UnequalColumnsDescription(columnWidths: [1]);
      model.columnWidths.addAll(List.filled(10, 2));
      expect(
        () => validateFieldTypes(model),
        throwsValueError(
          '`UnequalColumnsDescription.column_widths` holds a value its field '
          'declaration rejects (at column_widths). $revalidateHint Validation '
          'errors:\n'
          '  at column_widths: List should have at most 10 items after '
          'validation, not 11 (got [1.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, '
          '2.0, 2.0, 2.0])',
        ),
      );
    });

    test('an optional list grown past its maximum length', () {
      final model = UnequalColumnsDescription(
        columnWidths: [1],
        gutterWidths: [1],
      );
      model.gutterWidths!.addAll(List.filled(9, 3));
      expect(
        () => validateFieldTypes(model),
        throwsValueError(
          'at gutter_widths: List should have at most 9 items after '
          'validation, not 10 (got [1.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, '
          '3.0, 3.0])',
        ),
      );
    });

    for (final (bad, shown) in [
      (double.nan, 'nan'),
      (double.infinity, 'inf'),
    ]) {
      test('a list item set to $shown', () {
        final model = UnequalColumnsDescription(columnWidths: [1, 2.5]);
        model.columnWidths[1] = bad;
        expect(
          () => validateFieldTypes(model),
          throwsValueError(
            '`UnequalColumnsDescription.column_widths` holds a value its '
            'field declaration rejects (at column_widths). $revalidateHint '
            'Validation errors:\n'
            '  at column_widths.1: Input should be a finite number '
            '(got $shown)',
          ),
        );
      });
    }

    test('a union with every case unset', () {
      final chart = Chart(column: ColumnChart())..column = null;
      expect(
        () => validateFieldTypes(chart),
        throwsValueError(
          '`Chart` holds values its declaration rejects (at <root>). '
          '$revalidateHint Validation errors:\n'
          '  at <value>: Value error, Chart: no case present (got '
          "{'preset_identifier': '', 'area': None, 'area_3d': None, 'ba… "
          '(529 characters))',
        ),
      );
    });

    test('a union with a valueless case reads as holding it', () {
      final stroke = TextStroke(none: true)..none = false;
      validateFieldTypes(stroke);
    });

    test('a union with every case unset, in a document', () {
      final chart = Chart(column: ColumnChart());
      final doc = docWithChart(chart);
      chart.column = null;
      expect(
        () => validateDocument(doc),
        throwsValueError(
          '`Chart` holds values its declaration rejects (at '
          'slides[0].contents[0].object.chart).',
        ),
      );
    });
  });
}
