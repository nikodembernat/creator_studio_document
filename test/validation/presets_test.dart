// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/test_presets.py.

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/src/validation/resolve.dart';
import 'package:creator_studio_document/validation.dart';
import 'package:test/test.dart';

import 'builders.dart';

KeyxDocument _docWith(List<Slide> slides, List<Preset> presets) => KeyxDocument(
  Presentation(slideSize: slideSize(), slides: slides),
  presets: presets,
);

Slide _slideWithShape(Shape shape) => Slide(
  contents: [SlideObject(object: CanvasObject(shape: shape))],
);

Slide _slideWithRgbaPreset(String preset) => Slide(
  background: Override.value(
    SlideBackground(
      standard: Fill(
        color: Color(rgba: RGBA(presetIdentifier: preset)),
      ),
    ),
  ),
);

void main() {
  test('a minimal document passes (test_validate_minimal_passes)', () {
    validateDocument(emptyDoc());
  });

  test('a preset cycle is rejected (test_validate_detects_preset_cycle)', () {
    final doc = _docWith(
      [Slide()],
      [
        Preset('a', {}, parentIdentifier: 'b'),
        Preset('b', {}, parentIdentifier: 'a'),
      ],
    );
    expect(
      () => validateDocument(doc),
      throwsValueError('Presets form a cycle'),
    );
  });

  test('a preset cycle that an object adopts is rejected before encoding '
      '(test_validate_detects_preset_cycle_an_object_adopts)', () {
    final doc = _docWith(
      [_slideWithShape(Shape(presetIdentifier: 'a'))],
      [
        Preset('a', {}, parentIdentifier: 'b'),
        Preset('b', {}, parentIdentifier: 'a'),
      ],
    );
    expect(
      () => validateDocument(doc),
      throwsValueError('Presets form a cycle'),
    );
  });

  test('duplicate preset identifiers are rejected '
      '(test_validate_detects_preset_duplicate_identifiers)', () {
    final doc = _docWith([Slide()], [Preset('dup', {}), Preset('dup', {})]);
    expect(
      () => validateDocument(doc),
      throwsValueError(
        RegExp(r'`Preset\.identifier` values .* are duplicates'),
      ),
    );
  });

  test('an empty preset identifier is rejected '
      '(test_validate_rejects_empty_preset_identifier)', () {
    final doc = _docWith([Slide()], [Preset('', {})]);
    expect(
      () => validateDocument(doc),
      throwsValueError('`Preset.identifier` is empty'),
    );
  });

  test('an empty parent identifier is allowed '
      '(test_validate_allows_empty_string_parent_identifier)', () {
    validateDocument(
      _docWith([Slide()], [Preset('a', {}, parentIdentifier: '')]),
    );
  });

  test('a cycle through a property reference is rejected '
      '(test_validate_detects_cycle_through_a_property_reference)', () {
    final doc = _docWith(
      [Slide()],
      [
        Preset('a', {}, parentIdentifier: 'b'),
        Preset('b', {
          'fill': {'preset_identifier': 'a'},
        }),
      ],
    );
    expect(
      () => validateDocument(doc),
      throwsValueError('Presets form a cycle'),
    );
  });

  test('a DAG of presets passes (test_validate_accepts_dag_of_presets)', () {
    validateDocument(
      _docWith(
        [Slide()],
        [
          Preset('root', {}),
          Preset('child_a', {}, parentIdentifier: 'root'),
          Preset('child_b', {}, parentIdentifier: 'root'),
        ],
      ),
    );
  });

  test('a missing preset is rejected '
      '(test_validate_strict_resolution_raises_on_missing_preset)', () {
    final doc = _docWith([
      _slideWithShape(Shape(presetIdentifier: 'not-there')),
    ], []);
    expect(
      () => validateDocument(doc),
      throwsLookupError("`preset_identifier` matches no preset: 'not-there'"),
    );
  });

  test('a registered preset resolves '
      '(test_validate_strict_resolution_passes_with_registered_preset)', () {
    final doc = _docWith(
      [_slideWithRgbaPreset('mid-red')],
      [
        Preset('mid-red', {'red': 0.5}),
      ],
    );
    validateDocument(doc);

    final resolved = resolveProperties(doc, doc.toMainJson());
    final background = resolved.slides[0].background.get();
    expect(background, isNotNull);
    final fill = background!.standard;
    expect(fill?.color?.rgba, isNotNull);
    expect(fill!.color!.rgba!.red, 0.5);
  });

  test('an unknown preset property key passes '
      '(test_validate_accepts_unknown_preset_property_key)', () {
    validateDocument(
      _docWith(
        [_slideWithShape(Shape(presetIdentifier: 'unknown-key'))],
        [
          Preset('unknown-key', {'not_a_shape_field': 1}),
        ],
      ),
    );
  });

  test('a projected preset property key is ignored '
      '(test_validate_ignores_projected_preset_property_key)', () {
    final end = End(endPoint: Position(x: 0, y: 0), lineEnd: LineEnd.none);
    final line = ConnectionLine(tail: end, head: end, presetIdentifier: 'proj');
    validateDocument(
      _docWith(
        [
          Slide(
            contents: [SlideObject(object: CanvasObject(connectionLine: line))],
          ),
        ],
        [
          Preset('proj', {
            'paragraph_properties': {
              'type_identifier': 'paragraph-properties',
              'version': '1.0',
            },
          }),
        ],
      ),
    );
  });

  test('an inherited null on a known field is skipped '
      '(test_validate_skips_none_inherited_value_on_known_field)', () {
    final doc = _docWith(
      [_slideWithShape(Shape(presetIdentifier: 'null-head'))],
      [
        Preset('null-head', {'head': null}),
      ],
    );
    validateDocument(doc);
    final resolved = resolveProperties(doc, doc.toMainJson());
    final contents = resolved.slides[0].contents;
    expect(contents, isNotNull);
    final shape = contents![0].object.shape;
    expect(shape, isNotNull);
    expect(shape!.head, LineEnd.none);
  });

  test('an inherited null on an unknown field is skipped '
      '(test_validate_skips_none_inherited_value_on_unknown_field)', () {
    validateDocument(
      _docWith(
        [_slideWithShape(Shape(presetIdentifier: 'null-unknown'))],
        [
          Preset('null-unknown', {'not_a_shape_field': null}),
        ],
      ),
    );
  });

  test('an inherited value of the wrong type is rejected '
      '(test_validate_raises_on_type_incompatible_inherited_value)', () {
    final doc = _docWith(
      [_slideWithRgbaPreset('bad-rgba')],
      [
        Preset('bad-rgba', {'red': 'not-a-number'}),
      ],
    );
    expect(
      () => validateDocument(doc),
      throwsA(
        isA<DocumentValueError>()
            .having(
              (e) => e.message,
              'message',
              'An inherited preset value is invalid. Fix the preset '
                  'properties. Validation errors:\n'
                  '  at slides.0.background.standard.color.rgba.red: Input '
                  'should be a valid number',
            )
            .having((e) => e.cause, 'cause', isA<ModelValidationError>()),
      ),
    );
  });

  test('an inherited value that breaks a constraint names the preset '
      '(test_validate_names_the_preset_cause_on_constraint_violating_'
      'inherited_value)', () {
    final doc = _docWith(
      [_slideWithRgbaPreset('bad-rgba')],
      [
        Preset('bad-rgba', {'red': 5.0}),
      ],
    );
    expect(
      () => validateDocument(doc),
      throwsValueError(
        "The document doesn't validate against its own JSON. Fix any invalid "
        'preset property. Otherwise, an edit bypassed validation. '
        '$revalidateHint Validation errors:\n'
        '  at slides.0.background.standard.color.rgba.red: Input should be '
        'less than or equal to 1',
      ),
    );
  });

  test('a type mismatch names the deepest key '
      '(test_validate_type_mismatch_attributes_deepest_subkey)', () {
    final doc = _docWith(
      [Slide(presetIdentifier: 'bad-slide')],
      [
        Preset('bad-slide', {
          'background': {
            'standard': {
              'color': {
                'rgba': {'red': 'not-a-number'},
              },
            },
          },
        }),
      ],
    );
    expect(
      () => validateDocument(doc),
      throwsValueError(
        RegExp(r'at slides\.0\.background\.standard\.color\.rgba\.red'),
      ),
    );
  });

  test('a missing parent names the child preset '
      '(test_validate_missing_parent_names_the_child_preset)', () {
    final doc = _docWith(
      [_slideWithShape(Shape(presetIdentifier: 'child'))],
      [Preset('child', {}, parentIdentifier: 'missing-parent')],
    );
    expect(
      () => validateDocument(doc),
      throwsLookupError(RegExp(r"matches no preset \(at preset 'child'\)")),
    );
  });

  test('an unresolved preset wins over an inherited value error further on '
      '(test_validate_unresolved_preset_wins_over_downstream_inherited_'
      'value_error)', () {
    final slide = Slide(
      background: Override.value(
        SlideBackground(
          standard: Fill(
            color: Color(rgba: RGBA(presetIdentifier: 'bad-rgba')),
          ),
        ),
      ),
      contents: [
        SlideObject(
          object: CanvasObject(shape: Shape(presetIdentifier: 'gone')),
        ),
      ],
    );
    final doc = _docWith(
      [slide],
      [
        Preset('bad-rgba', {'red': 'not-a-number'}),
      ],
    );
    expect(() => validateDocument(doc), throwsLookupError('gone'));
  });

  test("a top-level preset_identifier in properties isn't a graph edge "
      '(test_validate_top_level_preset_identifier_in_properties_is_not_a_'
      'graph_edge)', () {
    validateDocument(
      _docWith(
        [Slide()],
        [
          Preset('a', {}, parentIdentifier: 'b'),
          Preset('b', {'preset_identifier': 'a'}),
        ],
      ),
    );
  });

  test('without presets, a defect is blamed on an edit', () {
    final doc = KeyxDocument(
      Presentation(
        slideSize: slideSize(),
        slides: [Slide(identifier: 's')],
      ),
    );
    // An unknown key that shadows a field is written in its place.
    doc.payload.slides[0].extras['identifier'] = 5;
    expect(
      () => validateDocument(doc),
      throwsValueError(
        "An edit bypassed validation, so the document doesn't validate "
        'against its own JSON. $revalidateHint Validation errors:\n'
        '  at slides.0.identifier: Input should be a valid string',
      ),
    );
  });
}
