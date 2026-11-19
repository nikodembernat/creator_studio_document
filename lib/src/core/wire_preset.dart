// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python): the private helpers of
// `_preset.py`, and the preset parts of `_wire.py`.

part of 'wire.dart';

// A preset supplies nothing for the key.
final class const _NoFill();

const _noFill = _NoFill();

// A preset supplies an explicit null for an override key.
final class const _Clear();

const _clear = _Clear();

// A memoized `DocumentVersionError`, rethrown as a fresh copy.
final class _MemoVersionError(final String message);

// What decoding an object that adopts a preset needs.
final class _Adoption(
  final PresetRegistry registry,
  final String pid,
  final Map<String, Object?> props,
  final bool strict,
  final WireContext gateCtx,
);

// `_adopted_preset`: a null `preset_identifier` reads as absent.
Object? _adoptedPreset(Map<String, Object?> out) {
  if (out.containsKey('preset_identifier') &&
      out['preset_identifier'] == null) {
    out.remove('preset_identifier');
  }
  return out['preset_identifier'];
}

// `_decode_adoption`.
_Adoption? _decodeAdoption(Object? pid, WireContext ctx) {
  final registry = ctx.presets;
  if (registry == null || pid is! String || pid.isEmpty) {
    return null;
  }
  final (strict, gateCtx) = _presetGateContext(ctx);
  final Map<String, Object?> props;
  try {
    props = registry.resolvedProperties(pid);
  } on PresetCycleError catch (e) {
    throw _ValueError('$e');
  }
  return _Adoption(registry, pid, props, strict, gateCtx);
}

// `_preset_gate_context`: the context that validates a preset's values, one
// level deeper. From `_maxPresetGateDepth` on, values fill unvalidated.
(bool, WireContext) _presetGateContext(WireContext? ctx) {
  final strict = ctx?.strictPresets ?? false;
  final parent = ctx ?? WireContext();
  return (strict, WireContext._gate(parent, gateDepth: parent.gateDepth + 1));
}

// `_resolved_preset_props`: the registry and properties for encoding.
(PresetRegistry, Map<String, Object?>)? _resolvedPresetProps(
  WireModel model,
  WireContext? ctx,
) {
  final pid = model._presetIdentifier;
  if (pid.isEmpty) {
    return null;
  }
  final registry = ctx?.presets;
  if (registry == null) {
    throw StateError(
      '${model._name}: adopts preset ${_repr(pid)}, so encoding needs the '
      'presets. Save through Package.save, or pass '
      'WireContext(presets: registry).',
    );
  }
  return (registry, registry.resolvedProperties(pid));
}

// `ObjectModel._field_preset_supply`.
Object? _fieldPresetSupply(
  ObjectSchema<ObjectModel> owner,
  FieldSpec spec,
  _Adoption adoption, {
  required bool strict,
}) {
  if (!adoption.props.containsKey(spec.key)) {
    return _noFill;
  }
  return _presetSupply(
    registry: adoption.registry,
    owner: owner,
    pid: adoption.pid,
    props: adoption.props,
    key: spec.key,
    annotation: spec._presetAnnotation,
    lax: spec.presetGateLax,
    gateCtx: adoption.gateCtx,
    strict: strict,
    clears: spec._isOverride,
    required: spec.kind == FieldKind.req,
  );
}

// `TaggedUnionModel._case_preset_fills`.
(Map<String, Object?>, DocumentVersionError?) _casePresetFills(
  UnionSchema<TaggedUnionModel> owner,
  Iterable<CaseSpec> cases,
  _Adoption adoption, {
  required bool strict,
}) {
  final fills = <String, Object?>{};
  DocumentVersionError? tooNew;
  for (final c in cases) {
    if (!adoption.props.containsKey(c.key)) {
      continue;
    }
    final Object? fill;
    try {
      fill = _presetSupply(
        registry: adoption.registry,
        owner: owner,
        pid: adoption.pid,
        props: adoption.props,
        key: c.key,
        annotation: NullableType(c._payloadType),
        lax: false,
        gateCtx: adoption.gateCtx,
        strict: strict,
        clears: false,
        required: true,
      );
    } on DocumentVersionError catch (e) {
      tooNew ??= e;
      continue;
    }
    if (fill is! _NoFill) {
      fills[c.key] = fill;
    }
  }
  return (fills, tooNew);
}

// `_preset_supply`: the value that a preset supplies for one key, validated
// once per registry.
Object? _presetSupply({
  required PresetRegistry registry,
  required ModelSchema<WireModel> owner,
  required String pid,
  required Map<String, Object?> props,
  required String key,
  required WireType annotation,
  required bool lax,
  required WireContext gateCtx,
  required bool strict,
  required bool clears,
  required bool required,
}) {
  final candidate = props[key];
  if (candidate == null) {
    return clears && props.containsKey(key) ? _clear : _noFill;
  }
  final memoKey = (
    owner,
    key,
    pid,
    gateCtx.gateDepth,
    strict,
    gateCtx.strictPresets,
  );
  final memo = registry.gateMemo;
  final Object? fill;
  if (memo.containsKey(memoKey)) {
    fill = memo[memoKey];
  } else {
    try {
      fill = memo[memoKey] = _presetFill(
        annotation: annotation,
        candidate: candidate,
        lax: lax,
        gateCtx: gateCtx,
        strict: strict,
        required: required,
      );
    } on DocumentVersionError catch (e) {
      memo[memoKey] = _MemoVersionError(e.message);
      rethrow;
    }
  }
  if (fill is _MemoVersionError) {
    throw DocumentVersionError(fill.message);
  }
  return fill;
}

// `_preset_fill`.
Object? _presetFill({
  required WireType annotation,
  required Object candidate,
  required bool lax,
  required WireContext gateCtx,
  required bool strict,
  required bool required,
}) {
  if (_declaresForeignType(candidate, annotation)) {
    return _noFill;
  }
  if (strict) {
    return candidate;
  }
  return _presetGate(
    annotation,
    candidate,
    gateCtx,
    lax: lax,
    required: required,
  );
}

// `_preset_gate`: the candidate validated against the bare annotation, or
// `_noFill` if it doesn't validate. The annotation drops the field's own
// constraints, but the models nested in the candidate keep theirs.
Object? _presetGate(
  WireType annotation,
  Object candidate,
  WireContext gateCtx, {
  required bool lax,
  required bool required,
}) {
  final decoder = _Decoder(gateCtx);
  try {
    final value = decoder.value(annotation, candidate, const [], lax: lax);
    return decoder.issues.isEmpty && value is! _Invalid ? value : _noFill;
  } on DocumentVersionError {
    // A skip on a required field would report `Field required` and hide the
    // upgrade message.
    if (required) {
      rethrow;
    }
    return _noFill;
  } on DocumentError {
    return _noFill;
  }
}

// `_fill_from_preset`: writes the supplied raw values into `out`, and returns
// the keys it filled.
Set<String> _fillFromPreset(
  Map<String, Object?> out,
  Map<String, Object?> props,
  Iterable<(String, Object?)> supplies,
) {
  final filled = <String>{};
  for (final (key, fill) in supplies) {
    if (fill is _Clear) {
      out[key] = null;
    } else if (fill is! _NoFill) {
      out[key] = props[key];
      filled.add(key);
    }
  }
  return filled;
}

// `_union_members`.
List<WireType?> _unionMembers(WireType annotation) => switch (annotation) {
  NullableType(:final of) => [of, null],
  _ => [annotation],
};

// `_nested_type_ids`.
Set<String> _nestedTypeIds(WireType annotation) => {
  for (final m in _unionMembers(annotation))
    ...switch (m) {
      ModelType() when m.schema.typeId.isNotEmpty => {m.schema.typeId},
      ListType(:final of) => _nestedTypeIds(of),
      _ => const <String>{},
    },
};

// `_declares_foreign_type`: whether a preset value names a `type_identifier`
// that the field can't hold, so it belongs to a projected property.
bool _declaresForeignType(Object? candidate, WireType annotation) {
  if (candidate is List<Object?>) {
    final elements = [
      for (final m in _unionMembers(annotation))
        if (m case ListType(:final of)) of,
    ];
    return elements.isNotEmpty &&
        elements.every(
          (el) => candidate.any((e) => _declaresForeignType(e, el)),
        );
  }
  if (candidate is! Map<Object?, Object?>) {
    return false;
  }
  final tid = candidate['type_identifier'];
  if (!_truthy(tid)) {
    return false;
  }
  final allowed = _nestedTypeIds(annotation);
  if (allowed.isEmpty) {
    return false;
  }
  // Upstream tests `tid not in allowed` on a set, which raises `TypeError`
  // for a list or a dictionary, so the whole decode or encode fails.
  if (tid case List<Object?>() || Map<Object?, Object?>()) {
    throw ArgumentError(
      "unhashable type: '${tid is List ? 'list' : 'dict'}'",
      'type_identifier',
    );
  }
  return !allowed.contains(tid);
}
