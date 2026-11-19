// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

// Differential tests: every case in test/fixtures/expected/wire_cases.json was
// evaluated by the upstream Python package (tool/make_expected.py), and the
// Dart port must behave the same.

import 'dart:convert';
import 'dart:io';

import 'package:creator_studio_document/creator_studio_document.dart';
// The test assigns JSON to fields the way upstream's validated assignment
// does, which needs the internal decoder.
import 'package:creator_studio_document/src/core/wire.dart'
    show decodeWireValue;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'json_matchers.dart';

void main() {
  final cases = (jsonDecode(
    File('test/fixtures/expected/wire_cases.json').readAsStringSync(),
  ) as List<Object?>).cast<Map<String, Object?>>();

  final logs = <String>[];
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((r) {
    if (r.loggerName.startsWith('creator_studio_document') &&
        r.level >= Level.WARNING) {
      logs.add(r.message);
    }
  });

  test('the corpus is non-trivial', () {
    expect(cases.length, greaterThan(150));
  });

  for (final c in cases) {
    test(c['name'], () {
      logs.clear();
      _run(c, logs);
    });
  }
}

ModelSchema<WireModel> _schemaNamed(String name) =>
    modelSchemas.values.firstWhere((s) => s.name == name);

List<Preset>? _presets(Map<String, Object?> c) {
  final raw = c['presets'] as List<Object?>?;
  return raw
      ?.map((p) => Preset.fromJson((p! as Map).cast<String, Object?>()))
      .toList();
}

void _run(Map<String, Object?> c, List<String> logs) {
  final schema = _schemaNamed(c['type']! as String);
  final presets = _presets(c);
  final registry = presets == null ? null : PresetRegistry(presets);
  final context = registry == null
      ? null
      : WireContext(presets: registry, strictPresets: c['strict'] == true);
  final expected = c['decode'];

  WireModel? model;
  try {
    model = schema.fromJson(c['input'], context);
  } on ModelValidationError catch (e) {
    expect(expected, isA<Map<String, Object?>>(), reason: 'decode failed: $e');
    final want = expected! as Map<String, Object?>;
    expect(want['error'], 'ModelValidationError', reason: '$e');
    expect(_issueSet(e), _expectedIssues(want['issues']), reason: '$e');
  } on DocumentVersionError catch (e) {
    expect(expected, isA<Map<String, Object?>>(), reason: 'decode failed: $e');
    final want = expected! as Map<String, Object?>;
    expect(want['error'], 'DocumentVersionError');
    expect(e.message, want['message']);
  }

  if (model != null) {
    expect(expected, 'ok', reason: 'upstream failed to decode');
    _checkModel(c, schema, model, context, presets, logs);
  } else {
    expect([...logs]..sort(), c['logs']);
  }
  if (registry != null) {
    expect(
      [...registry.warnings]..sort(),
      (c['registry_warnings']! as List<Object?>).cast<String>(),
    );
  }
}

void _checkModel(
  Map<String, Object?> c,
  ModelSchema<WireModel> schema,
  WireModel model,
  WireContext? context,
  List<Preset>? presets,
  List<String> logs,
) {
  expect([...model.fieldsSet]..sort(), c['fields_set']);
  if (model is TaggedUnionModel) {
    expect([for (final u in model.unionCases()) u.name], c['union_cases']);
  }
  if (c.containsKey('redecode_equal')) {
    final again = schema.fromJson(c['input'], context);
    expect(again == model, c['redecode_equal']);
    if (again == model) {
      expect(again.hashCode, model.hashCode);
    }
  }
  for (final op in (c['ops'] as List<Object?>? ?? const [])) {
    _apply(model, (op! as Map).cast<String, Object?>());
  }
  final encodePresets = c['encode_without_presets'] == true ? null : presets;
  final encoded = _encode(model, encodePresets);
  _expectEncoded(encoded, c['encode']! as Map<String, Object?>);
  final twin = model.deepCopy();
  expect(twin == model, c['copy_equal']);
  expect([...logs]..sort(), c['logs']);
  expect(
    _sameOutcome(_encode(twin, encodePresets), encoded),
    c['copy_encode_same'],
  );
}

Object _encode(WireModel model, List<Preset>? presets) {
  final context = presets == null
      ? null
      : WireContext(presets: PresetRegistry(presets));
  try {
    return model.toJson(context);
  } on DocumentVersionError catch (e) {
    return e;
  } catch (err) {
    // Upstream raises `ValueError` for an encoding mistake; the port throws
    // `StateError`.
    if (err is StateError) {
      return err;
    }
    rethrow;
  }
}

bool _sameOutcome(Object a, Object b) => switch ((a, b)) {
  (DocumentVersionError(), DocumentVersionError()) => '$a' == '$b',
  (StateError(), StateError()) => '$a' == '$b',
  (Map<String, Object?>() || String(), Map<String, Object?>() || String()) =>
    sameJson(a, b),
  _ => false,
};

void _expectEncoded(Object encoded, Map<String, Object?> want) {
  switch (want['error']) {
    case null:
      expect(encoded, sameJsonInOrder(want['json']));
    case 'DocumentVersionError':
      expect(encoded, isA<DocumentVersionError>());
      expect('$encoded', want['message']);
    case 'EncodeError':
      expect(encoded, isA<StateError>(), reason: '${want['message']}');
  }
}

Set<String> _issueSet(ModelValidationError e) => {
  for (final i in e.issues) '${jsonEncode(i.location)} ${i.type}',
};

Set<String> _expectedIssues(Object? raw) => {
  for (final i in (raw! as List<Object?>).cast<List<Object?>>())
    '${jsonEncode(i[0])} ${i[1]}',
};

Object? _navigate(WireModel model, List<Object?> path) {
  Object? node = model;
  for (final step in path) {
    node = switch (step) {
      final int i => (node! as List<Object?>)[i],
      final String key => (node! as WireModel).wireGet(key),
      _ => throw ArgumentError.value(step),
    };
    if (node is Override) {
      node = node.get();
    }
  }
  return node;
}

WireType _typeOf(WireModel node, String key) => switch (node.wireSchema) {
  ObjectSchema(:final field) => field(key)!.type,
  UnionSchema(:final caseSpec) => NullableType(
    caseSpec(key)!.type ?? const LiteralTrueType(),
  ),
};

void _apply(WireModel model, Map<String, Object?> op) {
  final node = _navigate(model, op['path']! as List<Object?>)! as WireModel;
  if (op['set'] case final String key) {
    node.wireSet(key, decodeWireValue(_typeOf(node, key), op['json']));
  } else if (op['touch'] case final String key) {
    node.wireSet(key, node.wireGet(key));
  } else if (op['extra'] case final String key) {
    node.extras[key] = op['json'];
  } else if (op['preset_identifier'] case final String pid) {
    node.presetIdentifier = pid;
  } else {
    throw ArgumentError.value(op, 'op');
  }
}
