// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python): the encoding half of
// `_wire.py` (`ObjectModel._wire_after`, `TaggedUnionModel._wire_encode`,
// `_object_version`, `_ser_override`, `_ser_payload`).

part of 'wire.dart';

// Pydantic's limit on how deeply the values that it serializes nest: the
// model that a dump starts at is at depth 1, and each model, list, and map
// inside it, and each value they hold, one deeper. A nested model's own dump
// counts on from its parent's.
const _maxSerializationDepth = 256;

// The depth of the value being encoded.
int _serializationDepth = 0;

// Encodes a model, list, or map one level deeper.
R _nested<R>(R Function() encode) {
  _checkDepth();
  _serializationDepth++;
  try {
    return encode();
  } finally {
    _serializationDepth--;
  }
}

// Throws if a value one level deeper than the current one is too deep.
void _checkDepth() {
  if (_serializationDepth >= _maxSerializationDepth) {
    throw SerializationDepthError();
  }
}

// Pydantic's JSON-mode serialization of a value that a model holds. A NaN or
// infinity, which only an in-place change can put there, is written as null.
Object? _encodeValue(Object? value, WireContext? ctx) {
  switch (value) {
    case WireModel():
      return value.toJson(ctx);
    // `_ser_override`: only a value is written; the codec decides about nulls.
    case OverrideValue(:final value):
      return _encodeValue(value, ctx);
    case final List<Object?> list:
      return _nested(() => [for (final v in list) _encodeValue(v, ctx)]);
    case final Map<Object?, Object?> map:
      return _nested(
        () => <String, Object?>{
          for (final e in map.entries)
            _wireKey('${e.key}'): _encodeValue(e.value, ctx),
        },
      );
  }
  _checkDepth();
  return switch (value) {
    final double d when !d.isFinite => null,
    final WireEnum e => e.wireValue,
    Override() => null,
    _ => value,
  };
}

// A key of an unknown JSON object. Python holds a lone surrogate in a string,
// but Pydantic can't encode one in a key as UTF-8, so neither does this.
String _wireKey(String key) {
  if (loneSurrogate(key) case (final index, final unit)) {
    throw StateError(
      "'utf-8' codec can't encode character ${pyStringRepr(String.fromCharCode(unit))} "
      'in position $index: surrogates not allowed',
    );
  }
  return key;
}

// `_object_version`: the newest version among the base fields, raised by any
// newer optional field that's present.
Version _objectVersion(Iterable<FieldSpec> specs, Set<String> present) {
  var base = const Version(1);
  for (final f in specs) {
    if (f._isBase && f.added > base) {
      base = f.added;
    }
  }
  var ver = base;
  for (final f in specs) {
    if (!f._isBase &&
        present.contains(f.key) &&
        f.added > base &&
        f.added > ver) {
      ver = f.added;
    }
  }
  return ver;
}

Version _maxVersion(Version a, Version b) => a >= b ? a : b;

// `_ser_payload`: a model or an enum as JSON, and anything else as it is. A
// list of models therefore stays a list of models, which never matches a
// preset's JSON, so a list case that's set is always written.
Object? _serPayload(Object? value, WireContext? ctx) => switch (value) {
  final WireModel m => m.toJson(ctx),
  final WireEnum e => e.wireValue,
  _ => value,
};

// `ObjectModel._wire_after`.
final class _ObjectEncoder(final ObjectModel model, final WireContext? ctx) {
  this {
    final resolved = _resolvedPresetProps(model, ctx);
    props = resolved?.$2;
    adoption = resolved == null
        ? null
        : _Adoption(
            resolved.$1,
            model._presetIdentifier,
            resolved.$2,
            false,
            _presetGateContext(ctx).$2,
          );
  }

  final ObjectSchema<ObjectModel> schema = model._schema;
  final Map<String, Object?> raw = {
    'preset_identifier': model._presetIdentifier,
    for (final f in model._schema.fields)
      f.key: _encodeValue(model._values[f.key], ctx),
    for (final e in model._extras.entries)
      _wireKey(e.key): _encodeValue(e.value, ctx),
  };
  late final Map<String, Object?>? props;
  late final _Adoption? adoption;

  final Map<String, Object?> out = {};
  final Set<String> present = {};
  final Map<String, Version> nulls = {};

  bool _isSet(String key) => model._fieldsSet.contains(key);

  Object? _value(String key) => model._values[key];

  Object? _presetValue(FieldSpec spec) {
    final adoption = this.adoption;
    if (adoption == null) {
      return _noFill;
    }
    try {
      return _fieldPresetSupply(schema, spec, adoption, strict: false);
    } on DocumentVersionError {
      return _noFill;
    }
  }

  // `_default`. A value that a model holds is already decoded, so
  // `_as_decoded` is the identity here.
  Object? _default(FieldSpec spec) {
    final value = spec.defaultValue!();
    return value is Override ? value.get() : value;
  }

  bool _presetSupplies(FieldSpec spec, Object? fill) {
    if (fill is _NoFill) {
      return false;
    }
    if (spec.kind != FieldKind.ovrdef || fill is _Clear) {
      return true;
    }
    return !_sameValue(fill, _default(spec));
  }

  bool _untouched(FieldSpec spec, Object? value, Object? fill) {
    if (model._filled.contains(spec.key)) {
      return fill is! _NoFill && fill is! _Clear && _sameValue(value, fill);
    }
    return _sameValue(value, _default(spec));
  }

  bool _factorOut(FieldSpec spec, Object? fill, Object? value) {
    final props = this.props;
    if (props == null || fill is _NoFill || fill is _Clear) {
      return false;
    }
    final own = _isSet(spec.key) ? raw[spec.key] : _notSetJson;
    return _sameAsPreset(value, fill, props[spec.key], own);
  }

  void _write(String key) => out[key] = raw[key];

  Map<String, Object?> encode() {
    for (final spec in schema.fields) {
      switch (spec.kind) {
        case FieldKind.req:
          _required(spec);
        case FieldKind.def:
          _defaulted(spec);
        case FieldKind.ovr || FieldKind.ovrdef:
          _override(spec);
        case FieldKind.opt:
          _optional(spec);
      }
    }
    out['type_identifier'] = schema.typeId;
    var ver = _objectVersion(schema.fields, present);
    if (model._floor.holds(model)) {
      ver = _maxVersion(ver, model._floor.version!);
    }
    out['version'] = '$ver';
    for (final MapEntry(:key, :value) in nulls.entries) {
      if (value > ver) {
        out.remove(key);
      }
    }
    if (model._presetIdentifier.isNotEmpty) {
      out['preset_identifier'] = raw['preset_identifier'];
    }
    for (final e in raw.entries) {
      if (schema.field(e.key) == null &&
          e.key != 'preset_identifier' &&
          !out.containsKey(e.key)) {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  void _required(FieldSpec spec) {
    if (!_factorOut(spec, _presetValue(spec), _value(spec.key))) {
      _write(spec.key);
    }
  }

  void _defaulted(FieldSpec spec) {
    final fill = _presetValue(spec);
    final value = _value(spec.key);
    if (_isSet(spec.key)) {
      if (!_factorOut(spec, fill, value)) {
        _write(spec.key);
      }
    } else if (!_untouched(spec, value, fill)) {
      _write(spec.key);
    }
  }

  void _override(FieldSpec spec) {
    final key = spec.key;
    final ov = _value(key)! as Override<Object?>;
    final fill = _presetValue(spec);
    if (spec.kind == FieldKind.ovrdef &&
        !_isSet(key) &&
        (ov.isNotSet || (ov.isValue && _untouched(spec, ov.get(), fill)))) {
      if (ov.isValue && !_sameValue(ov.get(), _default(spec))) {
        present.add(key);
      }
      return;
    }
    if (ov.isCleared) {
      if (_isSet(key) || fill is! _Clear) {
        out[key] = null;
      }
      present.add(key);
    } else if (ov.isValue) {
      present.add(key);
      final holdsDefault =
          spec.kind == FieldKind.ovrdef && _sameValue(ov.get(), _default(spec));
      if (holdsDefault || !_factorOut(spec, fill, ov.get())) {
        _write(key);
      }
    }
  }

  void _optional(FieldSpec spec) {
    final fill = _presetValue(spec);
    final value = _value(spec.key);
    if (value != null) {
      present.add(spec.key);
      if (!_factorOut(spec, fill, value)) {
        _write(spec.key);
      }
    } else if (_isSet(spec.key) && _presetSupplies(spec, fill)) {
      out[spec.key] = null;
      nulls[spec.key] = spec.added;
    }
  }
}

typedef _Present = ({String key, Version added, bool valueless});

// `TaggedUnionModel._wire_encode`.
final class _UnionEncoder(
  final TaggedUnionModel model,
  final WireContext? ctx,
) {
  final UnionSchema<TaggedUnionModel> schema = model._schema;
  final Map<String, Object?> extra = {
    for (final e in model._extras.entries)
      _wireKey(e.key): _encodeValue(e.value, ctx),
  };

  late final List<_Present> present = [
    for (final c in schema.cases)
      if (model._values[c.key] != null)
        (key: c.key, added: c.added, valueless: c.valueless),
  ];

  final Set<String> factored = {};
  final Set<String> nulls = {};
  final Map<String, Object?> payloads = {};

  Object encode() {
    if (present.isEmpty && model._presetIdentifier.isEmpty) {
      throw NoCaseError("${schema.name}: can't encode with no case set");
    }
    if (extra.isEmpty &&
        model._presetIdentifier.isEmpty &&
        present.length == 1 &&
        present[0].valueless) {
      return present[0].key;
    }
    var ver = present.fold(const Version(1), (v, p) => _maxVersion(v, p.added));
    final floored = model._floor.holds(model);
    if (floored) {
      ver = _maxVersion(ver, model._floor.version!);
    }
    final reloadCases = List.of(present);
    ver = _factorPreset(reloadCases, ver);
    return _write(reloadCases, ver, floored: floored);
  }

  // The preset part of `_wire_encode`: which cases the preset supplies, and
  // which of the present ones it can factor out.
  Version _factorPreset(List<_Present> reloadCases, Version version) {
    final resolved = _resolvedPresetProps(model, ctx);
    if (resolved == null) {
      return version;
    }
    var ver = version;
    final (registry, props) = resolved;
    final gateCtx = _presetGateContext(ctx).$2;
    final adoption = _Adoption(
      registry,
      model._presetIdentifier,
      props,
      false,
      gateCtx,
    );
    final (fills, tooNew) = _casePresetFills(
      schema,
      [
        for (final c in schema.cases)
          if (!c.valueless && (present.isEmpty || c.added <= ver)) c,
      ],
      adoption,
      strict: false,
    );
    if (present.isEmpty) {
      for (final c in schema.cases) {
        if (fills.containsKey(c.key)) {
          ver = _maxVersion(ver, c.added);
        }
      }
    }
    for (final c in schema.cases) {
      if (!fills.containsKey(c.key)) {
        continue;
      }
      _factorCase(c, fills[c.key], props, reloadCases);
    }
    if (reloadCases.isEmpty) {
      _throwNoCase(tooNew);
    }
    return ver;
  }

  void _factorCase(
    CaseSpec c,
    Object? fill,
    Map<String, Object?> props,
    List<_Present> reloadCases,
  ) {
    final v = model._values[c.key];
    final isSet = model._fieldsSet.contains(c.key);
    if (v != null) {
      if (isSet) {
        payloads[c.key] = _serPayload(v, ctx);
      }
      final own = payloads.containsKey(c.key) ? payloads[c.key] : _notSetJson;
      if (_sameAsPreset(v, fill, props[c.key], own)) {
        factored.add(c.key);
      }
    } else if (isSet) {
      nulls.add(c.key);
    } else {
      reloadCases.add((key: c.key, added: c.added, valueless: c.valueless));
    }
  }

  Never _throwNoCase(DocumentVersionError? tooNew) {
    final pid = model._presetIdentifier;
    if (tooNew != null) {
      (ctx ?? WireContext())._sink.error ??= tooNew;
      throw tooNew;
    }
    if (nulls.isNotEmpty) {
      final names = (nulls.toList()..sort()).map(_repr).join(', ');
      throw NoCaseError(
        "${schema.name}: can't encode with no case set: the value sets "
        '$names to None over preset ${_repr(pid)}',
      );
    }
    throw NoCaseError(
      "${schema.name}: can't encode with no case set, and preset "
      '${_repr(pid)} supplies none',
    );
  }

  Map<String, Object?> _write(
    List<_Present> reloadCases,
    Version ver, {
    required bool floored,
  }) {
    final unknownCases = extra.keys.toSet();
    final designated = model._designatedPrimary([
      for (final c in reloadCases) c.key,
    ], unknownCases);
    var primary = designated;
    if (primary == null && reloadCases.isNotEmpty) {
      primary = _newestCase([for (final c in reloadCases) (c.key, c.added)]);
    }
    final first = present.isEmpty || present.any((p) => p.key == primary)
        ? primary
        : _newestCase([for (final p in present) (p.key, p.added)]);
    final ordered = List.of(present)
      ..sort((a, b) => _primaryFirst(a.key, b.key, first ?? ''));
    final out = <String, Object?>{};
    if (primary != null && unknownCases.contains(primary)) {
      out[primary] = extra[primary];
    }
    for (final p in ordered) {
      if (factored.contains(p.key)) {
        continue;
      }
      out[p.key] = p.valueless
          ? null
          : _encodeValue(
              payloads.containsKey(p.key)
                  ? payloads[p.key]
                  : model._values[p.key],
              ctx,
            );
    }
    for (final n in nulls.toList()..sort()) {
      out[n] = null;
    }
    for (final e in extra.entries) {
      out.putIfAbsent(e.key, () => e.value);
    }
    final namesKnown = schema.cases.any((c) => c.key == model._primary);
    if (floored && designated == null && namesKnown) {
      primary = model._primary! as String;
    }
    if (primary != null &&
        reloadCases.length + unknownCases.length > 1 &&
        (!floored || designated != null || namesKnown)) {
      out['primary_case'] = primary;
    }
    out['type_identifier'] = schema.typeId;
    out['version'] = '$ver';
    if (model._presetIdentifier.isNotEmpty) {
      out['preset_identifier'] = model._presetIdentifier;
    }
    return out;
  }
}
