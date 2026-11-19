// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python), tests/test_navigation.py.

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/navigation.dart';
import 'package:test/test.dart';

import 'test_models.dart';

Gradient _gradient(List<Stop> stops) => Gradient(
  stops: stops,
  flavor: Flavor(linear: Linear(angle: 0)),
);

void main() {
  test('root is first and has empty path and ancestors', () {
    final root = RGBA();
    final visits = iterateModels(root).toList();
    expect(visits, isNotEmpty);
    final first = visits.first;
    expect(first, isA<IteratedModel>());
    expect(first.model, same(root));
    expect(first.path, '');
    expect(first.ancestors, isEmpty);
    expect(first.indexPath, isEmpty);
  });

  test('path shape for nested list and single model descents', () {
    final color = Color(rgba: RGBA(red: 0.5, green: 0.5, blue: 0.5));
    final stop = Stop(color: color, fraction: 0);
    final gradient = _gradient([stop]);

    final paths = {
      for (final visit in iterateModels(gradient))
        visit.model.wireSchema.name: visit.path,
    };

    expect(paths['Gradient'], '');
    expect(paths['Stop'], 'stops[0]');
    expect(paths['Color'], 'stops[0].color');
    expect(paths['RGBA'], 'stops[0].color.rgba');
  });

  test('ancestors at depth returns outermost to innermost chain', () {
    final color = Color(rgba: RGBA());
    final stop = Stop(color: color, fraction: 0);
    final gradient = _gradient([stop]);

    final rgbaVisit = iterateModels(gradient)
        .firstWhere((v) => v.model is RGBA);
    final ancestors = rgbaVisit.ancestors;

    expect(
      [for (final a in ancestors) a.wireSchema.name],
      ['Gradient', 'Stop', 'Color'],
    );
    expect(ancestors[0], same(gradient));
    expect(ancestors[1], same(stop));
    expect(ancestors[2], same(color));
  });

  test('index path encodes only list indices, not field names', () {
    final color = Color(rgba: RGBA());
    final stops = [
      Stop(color: color, fraction: 0),
      Stop(color: Color(rgba: RGBA()), fraction: 0.5),
      Stop(color: Color(rgba: RGBA()), fraction: 1),
    ];
    final gradient = _gradient(stops);

    final rgbaIndexPaths = [
      for (final v in iterateModels(gradient))
        if (v.model is RGBA) v.indexPath,
    ]..sort((a, b) => a.first.compareTo(b.first));
    expect(rgbaIndexPaths, [
      [0],
      [1],
      [2],
    ]);
  });

  test('a map of models field is iterated', () {
    final parent = Parent(children: {'a': Child(n: 1), 'b': Child(n: 2)});

    final childVisits = [
      for (final v in iterateModels(parent))
        if (v.model is Child) v,
    ];
    final ns = [for (final v in childVisits) (v.model as Child).n]..sort();
    expect(ns, [1, 2]);

    final paths = [for (final v in childVisits) v.path]..sort();
    expect(paths, ["children['a']", "children['b']"]);

    expect(childVisits.every((v) => v.indexPath.isEmpty), isTrue);
  });

  test('cycle is cut silently and iterator terminates', () {
    final a = Cyclic();
    final b = Cyclic(child: a);
    a.child = b;
    expect(a.child, same(b));
    expect(b.child, same(a));

    final visits = iterateModels(a).toList();

    expect(visits.first.model, same(a));
    expect(visits.any((v) => identical(v.model, b)), isTrue);
    final aVisits = visits.where((v) => identical(v.model, a));
    expect(aVisits, hasLength(1));
  });

  test('sibling shared subtree yields distinct visits', () {
    final shared = RGBA(red: 0.1);
    final colorA = Color(rgba: shared);
    final colorB = Color(rgba: shared);
    final stops = [
      Stop(color: colorA, fraction: 0),
      Stop(color: colorB, fraction: 1),
    ];
    final gradient = _gradient(stops);

    final rgbaVisits = [
      for (final v in iterateModels(gradient))
        if (v.model is RGBA) v,
    ];

    expect(rgbaVisits, hasLength(2));
    final paths = [for (final v in rgbaVisits) v.path]..sort();
    expect(paths, ['stops[0].color.rgba', 'stops[1].color.rgba']);
  });

  test('override value is descended and not set is skipped', () {
    final root = Holder();
    final visits = iterateModels(root).toList();

    final leaves = [
      for (final v in visits)
        if (v.model is Leaf) v,
    ];
    expect(leaves, hasLength(1));
    expect((leaves[0].model as Leaf).n, 1);
    expect(leaves[0].path, 'set_field');
  });

  // Beyond upstream's tests: behavior that upstream has but doesn't test.

  group('beyond upstream', () {
    test('visits fields and union cases in declaration order', () {
      final gradient = _gradient([
        Stop(color: Color(rgba: RGBA()), fraction: 0),
      ]);
      expect(
        [
          for (final v in iterateModels(gradient))
            (v.path, v.model.wireSchema.name),
        ],
        [
          ('', 'Gradient'),
          ('stops[0]', 'Stop'),
          ('stops[0].color', 'Color'),
          ('stops[0].color.rgba', 'RGBA'),
          ('flavor', 'Flavor'),
          ('flavor.linear', 'Linear'),
        ],
      );
    });

    test('exposes the parent, field name, list index, and map key', () {
      final child = Child(n: 1);
      final parent = Parent(children: {3: child});
      final [root, visit] = iterateModels(parent).toList();
      expect(root.parent, isNull);
      expect(root.fieldName, isNull);
      expect(visit.parent, same(root));
      expect(visit.model, same(child));
      expect(visit.fieldName, 'children');
      expect(visit.listIndex, isNull);
      expect(visit.dictKey, 3);
      expect(visit.ancestors, [same(parent)]);
    });

    test('writes map keys as Python repr does', () {
      final parent = Parent(
        children: {
          3: Child(n: 1),
          "it's": Child(n: 2),
          null: Child(n: 3),
          1.0: Child(n: 4),
          true: Child(n: 5),
        },
      );
      expect(
        [for (final v in iterateModels(parent).skip(1)) v.path],
        [
          'children[3]',
          'children["it\'s"]',
          'children',
          'children[1.0]',
          'children[True]',
        ],
      );
    });

    test('skips non-model values in lists and maps', () {
      final child = Child(n: 1);
      final parent = Parent(children: {'a': 1, 'b': child, 'c': null});
      final visits = iterateModels(parent).toList();
      expect(visits, hasLength(2));
      expect(visits[1].path, "children['b']");
    });

    test('a cleared override and a not-set override hold no model', () {
      final root = Holder()
        ..wireSet('set_field', const Override<Leaf>.cleared())
        ..wireSet('cleared_field', Leaf(n: 2));
      final leaves = [
        for (final v in iterateModels(root))
          if (v.model is Leaf) v,
      ];
      expect([for (final v in leaves) v.path], ['cleared_field']);
    });

    test('compares visits by identity', () {
      final root = RGBA();
      final first = iterateModels(root).single;
      final second = iterateModels(root).single;
      expect(first.model, same(second.model));
      expect(first, isNot(second));
      expect({first, second}, hasLength(2));
    });

    test('is lazy and each iterator starts over', () {
      final a = Cyclic();
      final b = Cyclic(child: a);
      a.child = b;
      final iterable = iterateModels(a);
      // Abandoning one iterator midway doesn't affect the next.
      expect(iterable.first.model, same(a));
      expect([for (final v in iterable) v.path], ['', 'child']);
      expect([for (final v in iterable) v.path], ['', 'child']);
    });
  });
}
