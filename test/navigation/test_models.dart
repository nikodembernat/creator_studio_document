// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

// Hand-written models for the navigation tests, standing in for the ad hoc
// Pydantic models that upstream's tests declare.

import 'package:creator_studio_document/creator_studio_document.dart';

/// A model with one integer field.
class Child extends ObjectModel {
  new({required int n}) : super.construct(schema, {'n': n});

  new _() : super.blank(schema);

  static final ObjectSchema<Child> schema = ObjectSchema(
    name: 'Child',
    typeId: 'test.navigation.child',
    version: const Version(1),
    create: Child._,
    fields: [FieldSpec('n', const Version(1), .req, const IntType())],
  );

  int get n => wireGet('n')! as int;
}

/// A model whose `children` field holds a map from keys to [Child] models.
///
/// The codec has no map type, so the field's declared type is only nominal;
/// construction stores the map as given.
class Parent extends ObjectModel {
  new({required Map<Object?, Object?> children})
    : super.construct(schema, {'children': children});

  new _() : super.blank(schema);

  static final ObjectSchema<Parent> schema = ObjectSchema(
    name: 'Parent',
    typeId: 'test.navigation.parent',
    version: const Version(1),
    create: Parent._,
    fields: [
      FieldSpec(
        'children',
        const Version(1),
        .req,
        ModelType(() => Child.schema),
      ),
    ],
  );
}

/// A model that can hold another of its kind.
class Cyclic extends ObjectModel {
  new({Cyclic? child}) : super.construct(schema, {'child': child});

  new _() : super.blank(schema);

  static final ObjectSchema<Cyclic> schema = ObjectSchema(
    name: 'Cyclic',
    typeId: 'test.navigation.cyclic',
    version: const Version(1),
    create: Cyclic._,
    fields: [
      FieldSpec(
        'child',
        const Version(1),
        .opt,
        NullableType(ModelType(() => Cyclic.schema)),
      ),
    ],
  );

  Cyclic? get child => wireGet('child') as Cyclic?;
  set child(Cyclic? value) => wireSet('child', value);
}

/// A model with one integer field, held in overrides.
class Leaf extends ObjectModel {
  new({required int n}) : super.construct(schema, {'n': n});

  new _() : super.blank(schema);

  static final ObjectSchema<Leaf> schema = ObjectSchema(
    name: 'Leaf',
    typeId: 'test.navigation.leaf',
    version: const Version(1),
    create: Leaf._,
    fields: [FieldSpec('n', const Version(1), .req, const IntType())],
  );

  int get n => wireGet('n')! as int;
}

/// A model with one [Leaf] override in each state.
class Holder extends ObjectModel {
  new() : super.construct(schema, const {});

  new _() : super.blank(schema);

  static final ObjectSchema<Holder> schema = ObjectSchema(
    name: 'Holder',
    typeId: 'test.navigation.holder',
    version: const Version(1),
    create: Holder._,
    fields: [
      FieldSpec(
        'set_field',
        const Version(1),
        .ovrdef,
        OverrideType<Leaf>(ModelType(() => Leaf.schema)),
        defaultValue: () => Override<Leaf>.value(Leaf(n: 1)),
      ),
      FieldSpec(
        'unset_field',
        const Version(1),
        .ovrdef,
        OverrideType<Leaf>(ModelType(() => Leaf.schema)),
        defaultValue: Override<Leaf>.notSet,
      ),
      FieldSpec(
        'cleared_field',
        const Version(1),
        .ovrdef,
        OverrideType<Leaf>(ModelType(() => Leaf.schema)),
        defaultValue: Override<Leaf>.cleared,
      ),
    ],
  );
}
