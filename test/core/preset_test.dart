// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python): the `PresetRegistry`
// doctest in core/_preset.py, and the core-level behavior that
// tests/validation/test_presets.py exercises. The `validate_document` messages
// those tests also check belong to the validation layer.

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:test/test.dart';

Size _slideSize() => Size(width: 1024, height: 768);

void main() {
  group('PresetRegistry doctest', () {
    final registry = PresetRegistry([
      Preset('base', {'text_wrap': true, 'vertical_alignment': 'top'}),
      Preset('wrapped', {
        'vertical_alignment': 'middle',
      }, parentIdentifier: 'base'),
    ]);

    test('merges a child over its parent', () {
      expect(registry.resolvedProperties('wrapped'), {
        'text_wrap': true,
        'vertical_alignment': 'middle',
      });
    });

    test('decoding fills from the preset; encoding factors it out', () {
      final context = WireContext(presets: registry);
      final cell = CellProperties.fromJson({
        'preset_identifier': 'wrapped',
      }, context);
      expect(cell.textWrap, isTrue);
      expect(cell.toJson(context).containsKey('text_wrap'), isFalse);
      cell.textWrap = false;
      expect(cell.toJson(context)['text_wrap'], isFalse);
    });
  });

  group('PresetRegistry', () {
    test('returns the same map for every call', () {
      final registry = PresetRegistry([
        Preset('a', {'x': 1}),
      ]);
      expect(
        identical(
          registry.resolvedProperties('a'),
          registry.resolvedProperties('a'),
        ),
        isTrue,
      );
      expect(
        () => registry.resolvedProperties('a')['y'] = 2,
        throwsUnsupportedError,
      );
    });

    test('a later preset replaces an earlier one with the same identifier', () {
      final registry = PresetRegistry([
        Preset('dup', {'x': 1}),
        Preset('dup', {'x': 2}),
      ]);
      expect(registry.resolvedProperties('dup'), {'x': 2});
    });

    test('a missing preset resolves to nothing and warns once', () {
      final registry = PresetRegistry([]);
      expect(registry.resolvedProperties('nope'), isEmpty);
      expect(registry.resolvedProperties('nope'), isEmpty);
      expect(registry.warnings, ["missing preset 'nope'"]);
    });

    test('a missing parent names the parent', () {
      final registry = PresetRegistry([
        Preset('child', {'x': 1}, parentIdentifier: 'missing-parent'),
      ]);
      expect(registry.resolvedProperties('child'), {'x': 1});
      expect(registry.warnings, ["missing preset 'missing-parent'"]);
    });

    test('a cycle throws and is recorded', () {
      // test_validate_detects_preset_cycle
      final registry = PresetRegistry([
        Preset('a', {}, parentIdentifier: 'b'),
        Preset('b', {}, parentIdentifier: 'a'),
      ]);
      expect(
        () => registry.resolvedProperties('a'),
        throwsA(isA<PresetCycleError>().having((e) => e.identifier, 'at', 'a')),
      );
      expect(registry.cycle, 'a');
    });

    test('a DAG of presets resolves', () {
      // test_validate_accepts_dag_of_presets
      final registry = PresetRegistry([
        Preset('root', {'r': 1}),
        Preset('child_a', {'a': 1}, parentIdentifier: 'root'),
        Preset('child_b', {'b': 1}, parentIdentifier: 'root'),
      ]);
      expect(registry.resolvedProperties('child_a'), {'r': 1, 'a': 1});
      expect(registry.resolvedProperties('child_b'), {'r': 1, 'b': 1});
      expect(registry.cycle, isNull);
    });

    test('a top-level preset_identifier property is not a parent link', () {
      // test_validate_top_level_preset_identifier_in_properties_is_not_a_graph_edge
      final registry = PresetRegistry([
        Preset('a', {}, parentIdentifier: 'b'),
        Preset('b', {'preset_identifier': 'a'}),
      ]);
      expect(registry.resolvedProperties('a'), {'preset_identifier': 'a'});
    });
  });

  group('Preset', () {
    test('round-trips through the presets file form', () {
      final json = {
        'identifier': 'p',
        'display_name': 'Pretty',
        'parent_identifier': 'base',
        'properties': {'x': 1},
      };
      final preset = Preset.fromJson(json);
      expect(preset.identifier, 'p');
      expect(preset.displayName, 'Pretty');
      expect(preset.parentIdentifier, 'base');
      expect(preset.toJson(), json);
      expect(Preset('q', {}).toJson(), {
        'identifier': 'q',
        'properties': <String, Object?>{},
      });
    });

    test('rejects an entry without identifier or properties', () {
      expect(() => Preset.fromJson({'properties': {}}), throwsArgumentError);
      expect(() => Preset.fromJson({'identifier': 'x'}), throwsArgumentError);
    });
  });

  group('adoption while decoding', () {
    test('a cycle that an object adopts fails validation', () {
      // test_validate_detects_preset_cycle_an_object_adopts
      final registry = PresetRegistry([
        Preset('a', {}, parentIdentifier: 'b'),
        Preset('b', {}, parentIdentifier: 'a'),
      ]);
      final json = Presentation(
        slideSize: _slideSize(),
        slides: [
          Slide(
            contents: [
              SlideObject(
                object: CanvasObject(shape: Shape(presetIdentifier: 'a')),
              ),
            ],
          ),
        ],
      ).toJson(WireContext(presets: PresetRegistry([Preset('a', {})])));
      expect(
        () => Presentation.fromJson(json, WireContext(presets: registry)),
        throwsA(
          isA<ModelValidationError>().having(
            (e) => e.issues.single.path,
            'path',
            'slides.0.contents.0.object.shape',
          ),
        ),
      );
      expect(registry.cycle, 'a');
    });

    test('a registered preset supplies a nested value', () {
      // test_validate_strict_resolution_passes_with_registered_preset
      final registry = PresetRegistry([
        Preset('mid-red', {'red': 0.5}),
      ]);
      final slide = Slide.fromJson({
        'background': {
          'standard': {
            'color': {
              'rgba': {'preset_identifier': 'mid-red'},
            },
          },
        },
      }, WireContext(presets: registry));
      final rgba = slide.background.get()!.standard!.color!.rgba!;
      expect(rgba.red, 0.5);
      expect(rgba.fieldsSet, {'preset_identifier', '\u0000wire_filled'});
    });

    test('an unknown preset property key is ignored', () {
      // test_validate_accepts_unknown_preset_property_key
      final context = WireContext(
        presets: PresetRegistry([
          Preset('unknown-key', {'not_a_shape_field': 1}),
        ]),
      );
      final shape = Shape.fromJson({
        'preset_identifier': 'unknown-key',
      }, context);
      expect(shape.extras, isEmpty);
      expect(shape.toJson(context), {
        'type_identifier': 'com.apple.apps.content-language.shape',
        'version': '1.0',
        'preset_identifier': 'unknown-key',
      });
    });

    test('a projected preset property is not filled', () {
      // test_validate_ignores_projected_preset_property_key
      final context = WireContext(
        presets: PresetRegistry([
          Preset('proj', {
            'paragraph_properties': {
              'type_identifier': 'paragraph-properties',
              'version': '1.0',
            },
          }),
        ]),
      );
      final line = ConnectionLine.fromJson({
        'preset_identifier': 'proj',
        'tail': {
          'end_point': {'x': 0, 'y': 0},
        },
        'head': {
          'end_point': {'x': 0, 'y': 0},
        },
      }, context);
      expect(line.extras, isEmpty);
    });

    test('a null inherited value leaves a defaulted field at its default', () {
      // test_validate_skips_none_inherited_value_on_known_field
      final context = WireContext(
        presets: PresetRegistry([
          Preset('null-head', {'head': null}),
        ]),
      );
      final shape = Shape.fromJson({'preset_identifier': 'null-head'}, context);
      expect(shape.head, LineEnd.none);
      expect(shape.fieldsSet, {'preset_identifier'});
    });

    test('a type-incompatible inherited value is skipped', () {
      // test_validate_raises_on_type_incompatible_inherited_value (core part)
      final context = WireContext(
        presets: PresetRegistry([
          Preset('bad-rgba', {'red': 'not-a-number'}),
        ]),
      );
      final rgba = RGBA.fromJson({'preset_identifier': 'bad-rgba'}, context);
      expect(rgba.red, 0.0);
    });

    test('a constraint-violating inherited value fails validation', () {
      // test_validate_names_the_preset_cause_on_constraint_violating_inherited_value
      final context = WireContext(
        presets: PresetRegistry([
          Preset('bad-rgba', {'red': 5.0}),
        ]),
      );
      expect(
        () => RGBA.fromJson({'preset_identifier': 'bad-rgba'}, context),
        throwsA(
          isA<ModelValidationError>().having(
            (e) => e.issues.single.type,
            'type',
            'less_than_equal',
          ),
        ),
      );
    });

    test('a strict context fills preset values without the gate', () {
      final context = WireContext(
        presets: PresetRegistry([
          Preset('bad-rgba', {'red': 'not-a-number'}),
        ]),
        strictPresets: true,
      );
      expect(
        () => RGBA.fromJson({'preset_identifier': 'bad-rgba'}, context),
        throwsA(isA<ModelValidationError>()),
      );
    });

    test('a missing preset adds a registry warning', () {
      // test_validate_strict_resolution_raises_on_missing_preset (core part)
      final registry = PresetRegistry([]);
      final shape = Shape.fromJson({
        'preset_identifier': 'not-there',
      }, WireContext(presets: registry));
      expect(shape.presetIdentifier, 'not-there');
      expect(registry.warnings, ["missing preset 'not-there'"]);
    });
  });

  group('encoding', () {
    test('an adopting object needs the presets', () {
      expect(
        () => Shape(presetIdentifier: 'p').toJson(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains("adopts preset 'p'"),
          ),
        ),
      );
    });

    test(
      'a union whose preset only supplies newer cases stashes the error',
      () {
        final context = WireContext(
          presets: PresetRegistry([
            Preset('newer', {
              'color': {
                'rgba': {'red': 1},
                'version': '7.0',
              },
            }),
          ]),
        );
        expect(
          () => Fill(presetIdentifier: 'newer').toJson(context),
          throwsA(isA<DocumentVersionError>()),
        );
        expect(
          context.versionError?.message,
          'Color: input declares version 7.0 but this library implements 1.x. '
          'Update this library to a newer version to read it.',
        );
      },
    );
  });
}
