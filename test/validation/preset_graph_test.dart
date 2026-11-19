// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/test_preset_graph.py.

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/src/validation/preset_graph.dart';
import 'package:test/test.dart';

import 'builders.dart';

void main() {
  test('the deepest child of a chain wins '
      '(test_multi_level_chain_deepest_child_wins)', () {
    final reg = PresetRegistry([
      Preset('gp', {'a': 1, 'b': 1, 'c': 1}),
      Preset('p', {'b': 2, 'c': 2}, parentIdentifier: 'gp'),
      Preset('c', {'c': 3}, parentIdentifier: 'p'),
    ]);
    expect(reg.resolvedProperties('c'), {'a': 1, 'b': 2, 'c': 3});
  });

  test('resolved properties are the raw values '
      '(test_resolved_properties_returns_raw_values)', () {
    final props = {'preset_identifier': 'self_ref', 'opacity': null, 'keep': 1};
    final reg = PresetRegistry([Preset('a', props)]);
    expect(reg.resolvedProperties('a'), {
      'preset_identifier': 'self_ref',
      'opacity': null,
      'keep': 1,
    });
  });

  test("a child's null overrides its parent's value "
      '(test_child_none_overrides_parent_value)', () {
    final reg = PresetRegistry([
      Preset('parent', {'space_after': 10}),
      Preset('child', {'space_after': null}, parentIdentifier: 'parent'),
    ]);
    expect(reg.resolvedProperties('child'), {'space_after': null});
  });

  test('two children of one parent resolve '
      '(test_dag_two_children_one_parent_resolves)', () {
    final reg = PresetRegistry([
      Preset('parent', {'a': 1}),
      Preset('c1', {'b': 2}, parentIdentifier: 'parent'),
      Preset('c2', {'c': 3}, parentIdentifier: 'parent'),
    ]);
    expect(reg.resolvedProperties('c1'), {'a': 1, 'b': 2});
    expect(reg.resolvedProperties('c2'), {'a': 1, 'c': 3});
  });

  test('resolved properties are cached '
      '(test_resolved_properties_is_cached)', () {
    final reg = PresetRegistry([
      Preset('parent', {'a': 1}),
      Preset('child', {'b': 2}, parentIdentifier: 'parent'),
    ]);
    final first = reg.resolvedProperties('child');
    final second = reg.resolvedProperties('child');
    expect(first, {'a': 1, 'b': 2});
    expect(second, first);
    expect(identical(first, second), isTrue);
  });

  test('a missing parent names the child preset '
      '(test_missing_parent_names_the_child_preset)', () {
    expect(
      () => validatePresetGraph([
        Preset('child', {}, parentIdentifier: 'missing'),
      ]),
      throwsLookupError(
        "`Preset.parent_identifier` 'missing' matches no preset "
        "(at preset 'child')",
      ),
    );
  });

  test('a parent cycle is rejected (test_parent_cycle_raises)', () {
    expect(
      () => validatePresetGraph([
        Preset('a', {}, parentIdentifier: 'b'),
        Preset('b', {}, parentIdentifier: 'a'),
      ]),
      throwsValueError('Presets form a cycle: a -> b -> a (at presets)'),
    );
  });

  test('a cycle through a nested reference is rejected '
      '(test_cross_edge_cycle_raises)', () {
    expect(
      () => validatePresetGraph([
        Preset('a', {}, parentIdentifier: 'b'),
        Preset('b', {
          'fill': {'preset_identifier': 'a'},
        }),
      ]),
      throwsValueError('Presets form a cycle'),
    );
  });

  test('a duplicate identifier is rejected '
      '(test_duplicate_identifier_raises)', () {
    expect(
      () => validatePresetGraph([
        Preset('a', {'x': 1}),
        Preset('a', {'y': 2}),
      ]),
      throwsValueError(
        "`Preset.identifier` values ['a'] are duplicates (at presets). Each "
        '`Preset.identifier` must be unique.',
      ),
    );
  });

  test('an empty identifier is rejected (test_empty_identifier_raises)', () {
    expect(
      () => validatePresetGraph([Preset('', {})]),
      throwsValueError(
        '`Preset.identifier` is empty (at presets[0]). Every `Preset` needs '
        'a nonempty `identifier`.',
      ),
    );
  });

  test("a top-level preset_identifier key isn't a graph edge "
      '(test_top_level_preset_identifier_key_is_not_a_graph_edge)', () {
    final presets = [
      Preset('a', {}, parentIdentifier: 'b'),
      Preset('b', {'preset_identifier': 'a'}),
    ];
    validatePresetGraph(presets);
    final reg = PresetRegistry(presets);
    expect(reg.resolvedProperties('a'), {'preset_identifier': 'a'});
  });

  test('a self-parent is a cycle of one', () {
    expect(
      () => validatePresetGraph([Preset('a', {}, parentIdentifier: 'a')]),
      throwsValueError('Presets form a cycle: a -> a (at presets)'),
    );
  });

  test('a cycle through nested lists and maps is found', () {
    expect(
      () => validatePresetGraph([
        Preset('a', {
          'items': [
            {
              'nested': {'preset_identifier': 'b'},
            },
          ],
        }),
        Preset('b', {}, parentIdentifier: 'c'),
        Preset('c', {}, parentIdentifier: 'a'),
      ]),
      throwsValueError('Presets form a cycle: a -> b -> c -> a (at presets)'),
    );
  });

  group('entries that upstream reads as Python values', () {
    // Outcomes checked against upstream, which reads a `Preset`'s attributes
    // as the entry holds them.
    Matcher throwsArgument(String message) => throwsA(
      isA<ArgumentError>().having((e) => e.message, 'message', message),
    );
    Preset raw(
      Object? identifier, [
      Object? properties = const <String, Object?>{},
      Object? parent,
    ]) => Preset.fromJson({
      'identifier': identifier,
      'properties': properties,
      'parent_identifier': ?parent,
    });

    test('properties that are not an object have no values', () {
      for (final (properties, type) in [
        (5, 'int'),
        (null, 'NoneType'),
        ('s', 'str'),
        (true, 'bool'),
        (<Object?>[], 'list'),
        (
          [
            {'preset_identifier': 'a'},
          ],
          'list',
        ),
      ]) {
        expect(
          () => validatePresetGraph([raw('a', properties)]),
          throwsArgument("'$type' object has no attribute 'values'"),
          reason: '$properties',
        );
      }
    });

    test('a duplicate is skipped before its properties are read', () {
      expect(
        () => validatePresetGraph([raw('a'), raw('a', 5)]),
        throwsValueError("`Preset.identifier` values ['a'] are duplicates"),
      );
    });

    test('a list or object parent is unhashable', () {
      expect(
        () => validatePresetGraph([
          raw('s', {}, ['a']),
        ]),
        throwsArgument("unhashable type: 'list'"),
      );
      expect(
        () => validatePresetGraph([
          raw('s', {}, {'a': 1}),
        ]),
        throwsArgument("unhashable type: 'dict'"),
      );
      // Unhashable before the properties are read.
      expect(
        () => validatePresetGraph([
          raw('s', 5, ['a']),
        ]),
        throwsArgument("unhashable type: 'list'"),
      );
    });

    test('a list or object identifier is unhashable unless empty', () {
      expect(
        () => validatePresetGraph([
          raw(['a']),
        ]),
        throwsArgument("unhashable type: 'list'"),
      );
      expect(
        () => validatePresetGraph([
          raw({'a': 1}),
        ]),
        throwsArgument("unhashable type: 'dict'"),
      );
      for (final empty in [<Object?>[], <String, Object?>{}, 0, false, 0.0]) {
        expect(
          () => validatePresetGraph([raw(empty)]),
          throwsValueError('`Preset.identifier` is empty (at presets[0])'),
          reason: '$empty',
        );
      }
    });

    test('a truthy identifier that is not a string is accepted', () {
      for (final identifier in [5, true, 1.5]) {
        validatePresetGraph([raw(identifier)]);
        validatePresetGraph([raw('s'), raw(identifier, {}, 's')]);
      }
      validatePresetGraph([raw(5), raw('b', {}, 5)]);
      validatePresetGraph([raw(5), raw('b', {}, 5.0)]);
      validatePresetGraph([raw(1), raw('b', {}, true)]);
    });

    test('identifiers that Python hashes alike are duplicates', () {
      for (final (presets, spelled) in [
        ([raw(5), raw(5)], '[5]'),
        ([raw(true), raw(1)], '[1]'),
        ([raw(1), raw(true)], '[True]'),
        ([raw(1), raw(1.0)], '[1.0]'),
        (
          [
            for (final i in [3, 1, 2, 3, 2, 1]) raw(i),
          ],
          '[1, 2, 3]',
        ),
        (
          [
            for (final i in ['c', 'a', 'c', 'a']) raw(i),
          ],
          "['a', 'c']",
        ),
      ]) {
        expect(
          () => validatePresetGraph(presets),
          throwsValueError(
            '`Preset.identifier` values $spelled are duplicates (at presets). '
            'Each `Preset.identifier` must be unique.',
          ),
        );
      }
    });

    test('a missing parent that is not a string is named by its repr', () {
      expect(
        () => validatePresetGraph([raw(5, {}, 7)]),
        throwsLookupError(
          '`Preset.parent_identifier` 7 matches no preset (at preset 5)',
        ),
      );
    });

    test('sorting children that mix strings and numbers fails', () {
      // Before the cycle check, which this pair would also fail.
      expect(
        () => validatePresetGraph([raw(5, {}, 'b'), raw('b', {}, 5)]),
        throwsArgument(
          "'<' not supported between instances of 'str' and 'int'",
        ),
      );
      expect(
        () =>
            validatePresetGraph([raw(5, {}, 'x'), raw('b', {}, 'x'), raw('x')]),
        throwsArgument(
          "'<' not supported between instances of 'str' and 'int'",
        ),
      );
      expect(
        () =>
            validatePresetGraph([raw(5, {}, 'x'), raw(2.5, {}, 'y'), raw('x')]),
        throwsLookupError(
          "`Preset.parent_identifier` 'y' matches no preset (at preset 2.5)",
        ),
      );
    });

    test(
      'a cycle through an identifier that is not a string fails to join',
      () {
        expect(
          () => validatePresetGraph([raw(5, {}, 5)]),
          throwsArgument('sequence item 0: expected str instance, int found'),
        );
      },
    );
  });
}
