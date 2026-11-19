// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'dart:collection';
import 'dart:typed_data';

import 'package:creator_studio_document/src/core/errors.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/core/resources_nfc.dart';
import 'package:meta/meta.dart';

/// Where a lazy [ResourceStore] reads the resources it hasn't read yet.
@internal
abstract interface class ResourceBackend() {
  /// Creates the interface; backends implement it rather than extend it.
  this;

  /// The name of every resource the backend holds.
  Iterable<String> names();

  /// Returns the bytes of the resource [name], one of [names].
  Uint8List read(String name);

  /// Releases what the backend holds open. Calling it again does nothing.
  void close();
}

/// Returns whether [name] is a flat filename: nonempty, not `.` or `..`, and
/// without `/` or `\`.
@internal
bool isValidFlatName(String name) =>
    name.isNotEmpty &&
    name != '.' &&
    name != '..' &&
    !name.contains('/') &&
    !name.contains(r'\');

void _validateResourceFilename(String name) {
  if (!isValidFlatName(name)) {
    throw ArgumentError(
      'invalid resource filename ${pyStringRepr(name)}: expected a flat '
      r"filename (nonempty, no '/', '\', or '..')",
    );
  }
}

String _asciiSkeleton(String name) =>
    String.fromCharCodes(name.codeUnits.where((c) => c < 128));

/// The package's resources, as a map from filename to bytes.
///
/// Saving writes exactly these entries to `Data/`. A resource that the JSON
/// embeds, such as a `Base64EncodedResource`, is never in the store. Any
/// method that adds a key throws [ArgumentError] unless the key is a flat
/// filename: nonempty, not `.` or `..`, and without `/` or `\`.
///
/// A store from `Package.openLazy` knows every name up front but reads each
/// resource from the archive on first access, so [length], [keys], and
/// [containsKey] read nothing. Reading a resource that the archive holds
/// corrupt throws [DocumentPackageError].
///
/// Keys match exactly, as in any map, so storing under a name that's taken
/// replaces that resource. [uniqueFilename] picks a free name instead:
///
/// ```dart
/// final store = ResourceStore({'logo.png': oldBytes});
/// final name = store.uniqueFilename('logo.png'); // 'logo 2.png'
/// store[name] = newBytes;
/// ```
///
/// The payload refers to a file from an `IndirectResource`, by its
/// `identifier` or, when that's absent, its `filename`. That name's spelling
/// can differ from the key's, such as a name that a zip tool stored
/// decomposed. Indexing and [containsKey] miss it, and [canResolve] and
/// [bytesFor] find it:
///
/// ```dart
/// // The key spells é as e and a combining acute accent (NFD).
/// final store = ResourceStore({'café.png': pngBytes});
/// store.containsKey('café.png'); // false
/// store.bytesFor('café.png'); // pngBytes
/// ```
///
/// Keys iterate in archive order, then in the order they were added; upstream
/// leaves the order unspecified.
class ResourceStore extends MapBase<String, Uint8List> {
  /// Creates a store with the resources in [initial].
  ///
  /// A lazy store passed as [initial] hands its archive over: the new store
  /// reads from it, and [initial] keeps only the resources already read.
  /// Throws [ArgumentError] if a key of [initial] isn't a flat filename.
  new([Map<String, Uint8List>? initial]) {
    if (initial is ResourceStore && initial._backend != null) {
      _backend = initial._backend;
      _backendKeys = initial._backendKeys;
      _data.addAll(initial._data);
      _tombstones.addAll(initial._tombstones);
      initial
        .._backend = null
        .._backendKeys = {}
        .._tombstones.clear();
      initial._generation++;
      return;
    }
    if (initial != null) {
      for (final MapEntry(:key, :value) in initial.entries) {
        this[key] = value;
      }
    }
  }

  /// Creates a store that reads each resource from [backend] on first
  /// access.
  @internal
  new lazy(ResourceBackend backend) {
    _backend = backend;
    _backendKeys = LinkedHashSet.of(backend.names());
  }

  ResourceBackend? _backend;
  Set<String> _backendKeys = {};
  final Map<String, Uint8List> _data = {};
  final Set<String> _tombstones = {};

  // Bumped whenever the set of keys changes, so the NFC index can be reused.
  int _generation = 0;
  int _indexedGeneration = -1;
  Map<String, String> _nfcIndex = const {};

  /// Whether the store still reads resources from an archive.
  bool get isLazy => _backend != null;

  bool _inBackend(String key) =>
      _backendKeys.contains(key) && !_tombstones.contains(key);

  List<String> _effectiveKeys() => [
    for (final k in _backendKeys)
      if (!_tombstones.contains(k)) k,
    for (final k in _data.keys)
      if (!_backendKeys.contains(k)) k,
  ];

  @override
  Uint8List? operator [](Object? key) {
    if (key is! String) {
      return null;
    }
    if (_data[key] case final value?) {
      return value;
    }
    final backend = _backend;
    if (backend != null && _inBackend(key)) {
      return _data[key] = backend.read(key);
    }
    return null;
  }

  @override
  void operator []=(String key, Uint8List value) {
    _validateResourceFilename(key);
    if (!_data.containsKey(key) && !_inBackend(key)) {
      _generation++;
    }
    _data[key] = value;
    _tombstones.remove(key);
  }

  /// Removes the resource [key] and returns its bytes, or returns `null` if
  /// there's none.
  ///
  /// To return them, a lazy store reads a resource it hasn't read yet, as
  /// upstream's `pop` does, so a corrupt member throws [DocumentPackageError]
  /// and stays in the store. [delete], upstream's `del`, and [clear] read
  /// nothing.
  @override
  Uint8List? remove(Object? key) {
    if (key is! String || !containsKey(key)) {
      return null;
    }
    final value = this[key];
    delete(key);
    return value;
  }

  /// Removes the resource [key] without reading it, and returns whether
  /// there was one.
  ///
  /// It's upstream's `del store[key]`, which drops a resource from a lazy
  /// store even when the archive holds it corrupt.
  bool delete(String key) {
    // A key can be in the archive and also cached, so both go. Unless they
    // do, a later read brings the key back.
    final inBackend = _backend != null && _inBackend(key);
    if (!inBackend && !_data.containsKey(key)) {
      return false;
    }
    _data.remove(key);
    if (inBackend) {
      _tombstones.add(key);
    }
    _generation++;
    return true;
  }

  /// Removes every resource without reading any.
  @override
  void clear() {
    _data.clear();
    _tombstones.addAll(_backendKeys);
    _generation++;
  }

  /// The filenames, as a snapshot: changing the store while iterating it is
  /// safe.
  @override
  Iterable<String> get keys => List.unmodifiable(_effectiveKeys());

  @override
  int get length =>
      _backendKeys.length -
      _tombstones.length +
      _data.keys.where((k) => !_backendKeys.contains(k)).length;

  @override
  bool get isEmpty => length == 0;

  @override
  bool get isNotEmpty => length != 0;

  @override
  bool containsKey(Object? key) =>
      key is String && (_inBackend(key) || _data.containsKey(key));

  /// Releases the backing archive and keeps only the resources already read.
  ///
  /// Calling `close` again does nothing, and so does calling it on a store
  /// that isn't lazy.
  void close() {
    final backend = _backend;
    if (backend == null) {
      return;
    }
    backend.close();
    _backend = null;
    _backendKeys = {};
    _tombstones.clear();
    _generation++;
  }

  /// Returns the key that [identifier] resolves to, as [bytesFor] matches
  /// it, or `null`.
  @internal
  String? resolveKey(String identifier) {
    if (containsKey(identifier)) {
      return identifier;
    }
    final keys = _effectiveKeys();
    if (_indexedGeneration != _generation) {
      final index = <String, String>{};
      for (final k in keys.toList()..sort(compareCodePoints)) {
        index.putIfAbsent(nfc(k), () => k);
      }
      _nfcIndex = index;
      _indexedGeneration = _generation;
    }
    if (_nfcIndex[nfc(identifier)] case final key?) {
      return key;
    }
    final target = _asciiSkeleton(identifier);
    String? match;
    for (final k in keys) {
      if (_asciiSkeleton(k) == target) {
        if (match != null) {
          return null;
        }
        match = k;
      }
    }
    return match;
  }

  /// Returns the bytes for an indirect resource's identifier or filename.
  ///
  /// Matching tries these in order:
  ///
  /// - The exact key.
  /// - A canonically equivalent key, so NFC and NFD spellings match.
  /// - The only key with the same ASCII characters as the identifier, which
  ///   tolerates mojibake in zip names.
  ///
  /// The ASCII match can return a different file: `é.png` resolves to
  /// `è.png` when that's the only key with the same ASCII characters. The
  /// resource check in `Package.save` accepts the same match.
  ///
  /// Throws [ArgumentError] if no key matches or the ASCII match is
  /// ambiguous, and [DocumentPackageError] if a lazy store reads a corrupt
  /// member.
  Uint8List bytesFor(String identifier) {
    final key = resolveKey(identifier);
    if (key == null) {
      throw ArgumentError(
        'no Data/ bytes for indirect resource ${pyStringRepr(identifier)}',
        'identifier',
      );
    }
    return this[key]!;
  }

  /// Returns whether a resource matches [identifier], an indirect resource's
  /// `identifier` or `filename`.
  ///
  /// It matches names the way [bytesFor] does, and never reads bytes.
  bool canResolve(String identifier) => resolveKey(identifier) != null;

  /// Returns a filename that no resource uses, based on [preferred].
  ///
  /// Reading and saving never rename a resource, so this is only for a
  /// caller adding one. The number goes before the last `.`, so `a.tar.gz`
  /// becomes `a.tar 2.gz` and `.hidden` becomes `" 2.hidden"`. Returns
  /// [preferred] if no entry has it, or else the first free numbered variant,
  /// such as `name 2.ext`.
  String uniqueFilename(String preferred) {
    if (!containsKey(preferred)) {
      return preferred;
    }
    final dot = preferred.lastIndexOf('.');
    final base = dot >= 0 ? preferred.substring(0, dot) : preferred;
    final suffix = dot >= 0 ? preferred.substring(dot) : '';
    var n = 2;
    while (containsKey('$base $n$suffix')) {
      n++;
    }
    return '$base $n$suffix';
  }

  /// Lists the filenames, without reading any bytes.
  @override
  String toString() =>
      'ResourceStore(${_effectiveKeys().map(pyStringRepr).join(', ')})';
}
