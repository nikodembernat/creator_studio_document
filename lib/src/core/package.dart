// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// Document packages, and the class that reads and writes them.
///
/// A package is the container a document lives in. Keynote Interchange
/// Format stores a package as a ZIP archive, the `.keyx` file, and that's the
/// only form this library reads and writes. The archive holds these entries:
///
/// - `main.json`: the payload, which is the document's root model, such as a
///   presentation.
/// - `manifest.json`: the manifest, which declares the package version.
/// - `presets.json`: the presets that objects in the payload adopt.
/// - `Data/`: the resources that the payload refers to, in one flat
///   directory.
///
/// [Package] keeps each entry in its own property: [Package.payload],
/// [Package.manifest], [Package.presets], and [Package.resources]. Its type
/// argument names the payload's type, and `KeyxDocument` fixes it to
/// `Presentation`. Each preset's properties stay raw JSON rather than models.
///
/// [Package.fromBytes] and [Package.toBytes] work on every platform. The
/// methods that take a path, [Package.open], [Package.openLazy], and
/// [Package.save], need `dart:io`, and throw [UnsupportedError] without it,
/// such as on the web.
library;

import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:creator_studio_document/src/core/errors.dart';
import 'package:creator_studio_document/src/core/package_io_stub.dart'
    if (dart.library.io) 'package:creator_studio_document/src/core/package_io.dart'
    as io;
import 'package:creator_studio_document/src/core/package_json.dart';
import 'package:creator_studio_document/src/core/package_zip.dart';
import 'package:creator_studio_document/src/core/preset.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/core/resources.dart';
import 'package:creator_studio_document/src/core/version.dart';
import 'package:creator_studio_document/src/core/wire.dart';
import 'package:meta/meta.dart';

/// The major version of the package format this library reads and writes.
///
/// Saving always writes it with minor 0, and a package with a newer major is
/// rejected on open.
const int supportedPackageMajor = 1;

String? _coerceVersionString(Object? raw) => switch (raw) {
  null || bool() => null,
  final String s => s,
  final int n => '$n',
  final BigInt n => '$n',
  final double d => pyFloatRepr(d),
  final Map<Object?, Object?> m => Version.parse(m)?.toString(),
  _ => null,
};

/// The package manifest, which records the version of the package format.
///
/// Saving writes the package format version this library supports, whatever
/// [packageVersion] holds, so the property reports the version that was
/// read, and a round trip doesn't preserve it.
class Manifest({
  /// The package format version that was read, in `major.minor` form, or
  /// `null`.
  var String? packageVersion,
}) {
  /// Creates a manifest with [packageVersion], in `major.minor` form.
  ///
  /// Throws [ArgumentError] if [packageVersion] has a newer major version
  /// than this library supports.
  this {
    if (_tooNew(packageVersion) case final message?) {
      throw ArgumentError(message, 'packageVersion');
    }
  }

  /// Creates a manifest from the decoded contents of a manifest file, which
  /// can be `null` or malformed.
  ///
  /// It reads a `package_version` written as a JSON number, such as `1.0`
  /// (or a [BigInt], for an integer too large for an [int]), or as a
  /// `{"major": ..., "minor": ...}` object as the `"major.minor"` string it
  /// spells, and checks it the same way. A missing or malformed
  /// [data], or one without a `package_version`, gives a default manifest.
  ///
  /// Throws [DocumentVersionError] if the `package_version` in [data] has a
  /// newer major version than this library supports.
  factory parse(Object? data) {
    if (data is! Map<Object?, Object?>) {
      return Manifest();
    }
    final version = _coerceVersionString(data['package_version']);
    if (_tooNew(version) case final message?) {
      throw DocumentVersionError(
        '$message. Update this library to a newer version to read it.',
      );
    }
    return Manifest(packageVersion: version);
  }

  static String? _tooNew(String? packageVersion) {
    if (packageVersion == null) {
      return null;
    }
    final found = Version.parse(packageVersion);
    if (found != null && found.major > supportedPackageMajor) {
      // `toString` spells a major too large for an int exactly.
      final major = found.toString().split('.').first;
      return '`package_version` ${pyStringRepr(packageVersion)} (major '
          '$major) exceeds supported major $supportedPackageMajor';
    }
    return null;
  }

  /// Returns the manifest in the form that the manifest file stores, with
  /// the package format version that this library writes.
  Map<String, String> toJson() => {
    'package_version': '$supportedPackageMajor.0',
  };

  @override
  String toString() => 'Manifest(packageVersion: $packageVersion)';
}

const _main = 'main.json';
const _manifest = 'manifest.json';
const _presets = 'presets.json';
const _indirectTypeId =
    'com.apple.apps.content-language.resource.indirect-resource';

/// A function that `Package.save` and `Package.toBytes` call before writing,
/// with the package and the exact value they write to `main.json`.
///
/// A hook is the only supported way to reach that value, and it must not
/// mutate it. A hook that throws stops the save.
typedef PreSaveHook<T extends ObjectModel> = void Function(
  Package<T> package,
  Map<String, Object?> main,
);

/// Returns every indirect resource name that [value], the encoded payload,
/// refers to, as `(field, name)` pairs, where `field` is `identifier` or
/// `filename`.
///
/// It follows upstream's `_iter_indirect_identifiers`: an object that adopts
/// a preset through [registry] takes the preset's `identifier` and
/// `filename` when it omits them, and the values that the preset supplies
/// for keys the object omits are searched too.
@internal
Iterable<(String, String)> iterIndirectIdentifiers(
  Object? value,
  PresetRegistry registry,
) => _iterIndirect(value, registry, const {}, {});

Iterable<(String, String)> _iterIndirect(
  Object? value,
  PresetRegistry registry,
  Set<String> adopting,
  Map<(String, String, String), List<(String, String)>> memo,
) sync* {
  switch (value) {
    case final Map<Object?, Object?> map:
      Map<String, Object?>? props;
      var within = adopting;
      final pid = switch (map['preset_identifier']) {
        final String p => p,
        _ => '',
      };
      if (pid.isNotEmpty) {
        props = registry.resolvedProperties(pid);
        within = {...adopting, pid};
      }
      if (map['type_identifier'] == _indirectTypeId) {
        final node = <Object?, Object?>{
          if (props != null)
            for (final k in const ['identifier', 'filename'])
              if (props[k] case final String s) k: s,
          ...map,
        };
        final field = node['identifier'] != null ? 'identifier' : 'filename';
        if (node[field] case final String name) {
          yield (field, name);
        }
      }
      for (final v in map.values) {
        yield* _iterIndirect(v, registry, adopting, memo);
      }
      if (props != null && !adopting.contains(pid)) {
        final adoptingKey = (adopting.toList()..sort(compareCodePoints)).join(
          '\u0000',
        );
        for (final MapEntry(:key, value: v) in props.entries) {
          if (map.containsKey(key)) {
            continue;
          }
          final memoKey = (pid, key, adoptingKey);
          yield* memo[memoKey] ??= _iterIndirect(
            v,
            registry,
            within,
            memo,
          ).toList();
        }
      }
    case final List<Object?> list:
      for (final v in list) {
        yield* _iterIndirect(v, registry, adopting, memo);
      }
  }
}

/// A document package in memory, with its payload, presets, manifest, and
/// resources.
///
/// [T] is the type of the payload, the document's root model, written to
/// `main.json`. `KeyxDocument` is the package of a Keynote presentation; a
/// package of another root model passes that model's schema, such as
/// `Package.open(path, payloadModel: Presentation.schema)`.
class Package<T extends ObjectModel>(
  /// The document's root model, written to `main.json`.
  var T payload, {
  List<Preset>? presets,
  Manifest? manifest,
  Map<String, Uint8List>? resources,
}) {
  /// Creates a package of [payload] with [presets], [manifest], and
  /// [resources], the `Data/` resources as a map from filename to bytes.
  ///
  /// A lazy [ResourceStore] passed as [resources] hands its archive over to
  /// the new package. Throws [ArgumentError] if a key of [resources] isn't a
  /// flat filename.
  this;

  /// Reads a package from the bytes of a ZIP archive, with every resource.
  ///
  /// [payloadModel] is the schema of the model that `main.json` holds, such
  /// as `Presentation.schema`.
  ///
  /// Throws [DocumentPackageError] if [bytes] isn't a valid package, with a
  /// kind that names the defect; [DocumentVersionError] if it declares a
  /// package or object version this library doesn't implement; and
  /// [ModelValidationError] if `main.json` doesn't match [payloadModel].
  factory fromBytes(Uint8List bytes, {required ObjectSchema<T> payloadModel}) {
    final src = BytesZipSource(bytes);
    probeArchive(src, 'the bytes');
    return _fromEntries(readZipEntries(src), payloadModel);
  }

  /// Opens the package at [path], a ZIP archive, with every resource already
  /// read.
  ///
  /// It doesn't accept an unzipped package directory. Zip it with
  /// `main.json` at the root of the archive.
  ///
  /// Throws as [Package.fromBytes] does, and also [DocumentPackageError] of
  /// kind [DocumentPackageErrorKind.notAPackage] if [path] is a directory or
  /// another file that isn't a regular one, and a `FileSystemException` if
  /// it can't be read, such as a path that doesn't exist. Throws
  /// [UnsupportedError] without `dart:io`.
  factory open(String path, {required ObjectSchema<T> payloadModel}) {
    final bytes = io.readPackageFile(path);
    final src = BytesZipSource(bytes);
    probeArchive(src, pyStringRepr(path));
    return _fromEntries(readZipEntries(src), payloadModel, source: path);
  }

  /// Opens the package at [path] and reads each resource only on first
  /// access.
  ///
  /// [resources] is a lazy [ResourceStore], and the JSON parts are read up
  /// front. `Map.of(pkg.resources)`, iterating its entries or values, and
  /// [save] read every resource, so laziness pays off only when a caller
  /// reads a subset, such as just the payload of a document with large
  /// media.
  ///
  /// The package holds the file open until [close] runs, so close it in a
  /// `finally` block. Throws as [Package.open] does.
  factory openLazy(String path, {required ObjectSchema<T> payloadModel}) {
    final src = io.openPackageFile(path);
    final ZipBackend backend;
    try {
      probeArchive(src, pyStringRepr(path));
      backend = ZipBackend(src);
    } on Object {
      src.close();
      rethrow;
    }
    try {
      final (payload, manifest, presets) = _decodeJsonParts(
        backend.member(_main),
        backend.member(_manifest),
        backend.member(_presets),
        payloadModel,
        source: path,
      );
      return Package(
        payload,
        presets: presets,
        manifest: manifest,
        resources: ResourceStore.lazy(backend),
      );
    } on Object {
      backend.close();
      rethrow;
    }
  }

  static Package<T> _fromEntries<T extends ObjectModel>(
    Map<String, Uint8List> entries,
    ObjectSchema<T> payloadModel, {
    String? source,
  }) {
    final (payload, manifest, presets) = _decodeJsonParts(
      entries[_main],
      entries[_manifest],
      entries[_presets],
      payloadModel,
      source: source,
    );
    return Package(
      payload,
      presets: presets,
      manifest: manifest,
      resources: {
        for (final MapEntry(key: name, value: data) in entries.entries)
          if (name.startsWith(dataDirPrefix) &&
              isValidFlatName(name.substring(dataDirPrefix.length)))
            name.substring(dataDirPrefix.length): data,
      },
    );
  }

  /// The presets, written to `presets.json`.
  List<Preset> presets = presets ?? [];

  /// The manifest, written to `manifest.json`.
  Manifest manifest = manifest ?? Manifest();

  /// The `Data/` resources, as a map from filename to bytes.
  ResourceStore resources = ResourceStore(resources);

  /// Encodes the payload as `main.json` holds it, factoring out the values
  /// that the presets supply.
  ///
  /// Throws [DocumentVersionError] if a union's only case comes from a preset
  /// value too new for this library to read.
  @internal
  Map<String, Object?> toMainJson() {
    final context = WireContext(presets: PresetRegistry(presets));
    try {
      return payload.toJson(context);
    } on Object {
      if (context.versionError case final tooNew?) {
        throw tooNew;
      }
      rethrow;
    }
  }

  Map<String, Uint8List> _entriesFromMain(Map<String, Object?> main) => {
    _main: pyJsonDumps(main),
    _manifest: pyJsonDumps(manifest.toJson()),
    _presets: pyJsonDumps([for (final p in presets) p.toJson()]),
    for (final MapEntry(key: filename, value: data) in resources.entries)
      '$dataDirPrefix$filename': data,
  };

  /// Returns the package as the bytes of a ZIP archive, as [save] writes it.
  ///
  /// It calls each of [preSaveHooks] and checks the resources as [save]
  /// does, and throws as [save] does, apart from the errors of writing a
  /// file.
  Uint8List toBytes({
    bool validateResources = true,
    Iterable<PreSaveHook<T>> preSaveHooks = const [],
  }) => writeZip(_encode(validateResources, preSaveHooks));

  Map<String, Uint8List> _encode(
    bool validateResources,
    Iterable<PreSaveHook<T>> preSaveHooks,
  ) {
    final main = toMainJson();
    for (final hook in preSaveHooks) {
      hook(this, main);
    }
    if (validateResources) {
      final missing = <String, Set<String>>{};
      final registry = PresetRegistry(presets);
      for (final (field, name) in iterIndirectIdentifiers(main, registry)) {
        if (!resources.canResolve(name)) {
          (missing[name] ??= {}).add(field);
        }
      }
      if (missing.isNotEmpty) {
        final names = missing.keys.toList()..sort(compareCodePoints);
        final listed = names
            .map(
              (name) =>
                  '${pyStringRepr(name)} (looked up by '
                  '${(missing[name]!.toList()..sort()).join(' and ')})',
            )
            .join(', ');
        throw StateError('indirect resources missing from Data/: $listed');
      }
    }
    return _entriesFromMain(main);
  }

  /// Writes the package to [path] as a ZIP archive.
  ///
  /// It writes a temporary file next to [path] and then renames it over
  /// [path], so a failed save leaves [path] untouched.
  ///
  /// It calls each of [preSaveHooks], in order, as `hook(this, main)`, where
  /// `main` is the exact value it writes to `main.json`. A hook that throws
  /// stops the save, and the error propagates unchanged.
  ///
  /// With [validateResources], it checks that every indirect resource the
  /// payload references resolves in [resources] before writing anything.
  ///
  /// A saved package doesn't match the one it came from, or an earlier save,
  /// byte for byte, but it's semantically the same. `sameJson` compares two
  /// JSON values while ignoring key order and number spelling, such as `1`
  /// and `1.0`.
  ///
  /// Throws [StateError] if [validateResources] is set and the payload
  /// references an indirect resource missing from [resources], if the
  /// payload can't be encoded, such as a union with no case set, a string
  /// with a lone surrogate, or a value nested more than 256 levels deep, and
  /// if a filename in [resources] holds a lone surrogate, which UTF-8 can't
  /// encode; [PresetCycleError] if the presets'
  /// `parent_identifier` chain that the payload reaches has a cycle; a
  /// `FileSystemException` if [path] is an existing directory, which it checks
  /// before calling any hook, or can't be written, such as a
  /// `PathNotFoundException` for a missing parent directory and a
  /// `PathAccessException` for one it may not write to;
  /// [DocumentPackageError] if a lazily opened package has a corrupt
  /// resource; and [DocumentVersionError] if a union's only case comes from a
  /// preset value too new for this library to read. Throws [UnsupportedError]
  /// without `dart:io`.
  void save(
    String path, {
    bool validateResources = true,
    Iterable<PreSaveHook<T>> preSaveHooks = const [],
  }) {
    io.checkSaveDestination(path);
    final entries = _encode(validateResources, preSaveHooks);
    io.writePackageFile(path, writeZip(entries));
  }

  /// Releases the file that a lazily opened package holds open.
  ///
  /// Calling `close` again does nothing, and so does calling it on an eagerly
  /// opened package. A lazily opened package keeps only the resources already
  /// read, so a later [save] drops the rest or, with `validateResources`,
  /// throws for one the payload references. Save before closing, or read
  /// every resource first with `Map.of(pkg.resources)`.
  void close() => resources.close();
}

(T, Manifest, List<Preset>) _decodeJsonParts<T extends ObjectModel>(
  Uint8List? main,
  Uint8List? manifest,
  Uint8List? presets,
  ObjectSchema<T> payloadModel, {
  String? source,
}) {
  final where = source != null ? '${pyStringRepr(source)}: ' : '';
  if (main == null) {
    throw DocumentPackageError(
      DocumentPackageErrorKind.missingMainFile,
      '$where$_main is required',
    );
  }
  final Manifest manifestObj;
  try {
    manifestObj = Manifest.parse(_maybeJson(manifest, where));
  } on DocumentVersionError catch (e) {
    throw DocumentVersionError('$where${e.message}');
  }
  var presetList = <Preset>[];
  if (presets != null) {
    final Object? presetsRaw;
    try {
      presetsRaw = pyJsonLoads(presets);
    } on PyJsonError catch (e) {
      throw DocumentPackageError(
        DocumentPackageErrorKind.malformedPresets,
        '$where$_presets: $e',
      );
    }
    if (presetsRaw is! List<Object?>) {
      throw DocumentPackageError(
        DocumentPackageErrorKind.malformedPresets,
        "$where$_presets isn't a JSON array",
      );
    }
    final entries = [
      for (final e in presetsRaw)
        if (e is Map<String, Object?> && e['identifier'] is String) e,
    ];
    if (entries.firstWhereOrNull((e) => !e.containsKey('properties'))
        case final e?) {
      throw DocumentPackageError(
        DocumentPackageErrorKind.malformedPresets,
        '$where$_presets: no `properties` in preset '
        '${pyStringRepr(e['identifier']! as String)}',
      );
    }
    presetList = [for (final e in entries) Preset.fromJson(e)];
  }
  final registry = PresetRegistry(presetList);
  final Object? mainObj;
  try {
    mainObj = pyJsonLoads(main);
  } on PyJsonError catch (e) {
    throw DocumentPackageError(
      DocumentPackageErrorKind.malformedJson,
      '$where$_main: $e',
    );
  }
  final T payload;
  try {
    payload = payloadModel.fromJson(mainObj, WireContext(presets: registry));
  } on ModelValidationError catch (e) {
    if (registry.cycle case final cycle?) {
      throw DocumentPackageError(
        DocumentPackageErrorKind.malformedPresets,
        '${where}circular preset `parent_identifier` chain at '
        '${pyRepr(cycle)}, so payload validation failed: $e',
      );
    }
    if (e.issues.any((i) => i.type == 'recursion_loop')) {
      throw DocumentPackageError(
        DocumentPackageErrorKind.malformedPresets,
        '${where}a preset property value reaches its own preset, so payload '
        'validation failed: $e',
      );
    }
    rethrow;
  }
  if (registry.cycle case final cycle?) {
    throw DocumentPackageError(
      DocumentPackageErrorKind.malformedPresets,
      '${where}circular preset `parent_identifier` chain at ${pyRepr(cycle)}',
    );
  }
  return (payload, manifestObj, presetList);
}

// Decodes a manifest. An integer reads exactly, so that a `package_version`
// of 2^63 or more reads as the digits it spells, as upstream's `str(raw)`
// gives them. Malformed JSON reads as `null`, apart from JSON nested too
// deeply, whose `RecursionError` escapes upstream's `except ValueError`.
Object? _maybeJson(Uint8List? data, String where) {
  if (data == null) {
    return null;
  }
  try {
    return pyJsonLoads(data);
  } on PyJsonDepthError catch (e) {
    throw DocumentPackageError(
      DocumentPackageErrorKind.malformedJson,
      '$where$_manifest: $e',
    );
  } on PyJsonError {
    return null;
  }
}
