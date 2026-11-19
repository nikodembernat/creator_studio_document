// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// The file access of a package, through `dart:io`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:creator_studio_document/src/core/errors.dart';
import 'package:creator_studio_document/src/core/package_zip.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:meta/meta.dart';

// `_open_package_file`: classified by `stat`, not by the error of opening,
// so a directory or a named pipe is `notAPackage` on every platform rather
// than an error of the file system, or a read that blocks.
void _checkRegularFile(String path) {
  final type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.notFound ||
      type == FileSystemEntityType.file) {
    // A missing path fails when it's opened, with the file system's error.
    return;
  }
  final what = type == FileSystemEntityType.directory
      ? 'a directory'
      : 'not a regular file';
  throw DocumentPackageError(
    DocumentPackageErrorKind.notAPackage,
    '${pyStringRepr(path)} is $what, not a ZIP package',
  );
}

/// Returns the bytes of the package file at [path].
///
/// Throws [DocumentPackageError] if [path] isn't a regular file, and
/// [FileSystemException] if it can't be read.
@internal
Uint8List readPackageFile(String path) {
  _checkRegularFile(path);
  return File(path).readAsBytesSync();
}

/// Opens the package file at [path] for random access.
///
/// Throws as [readPackageFile] does.
@internal
ZipSource openPackageFile(String path) {
  _checkRegularFile(path);
  return _FileZipSource(File(path).openSync());
}

final class _FileZipSource(final RandomAccessFile _file) implements ZipSource {
  late final int _length = _file.lengthSync();
  bool _closed = false;

  @override
  int get length => _length;

  @override
  Uint8List read(int offset, int count) {
    if (offset < 0 || offset >= _length || count <= 0) {
      return Uint8List(0);
    }
    _file.setPositionSync(offset);
    return _file.readSync(count);
  }

  @override
  void close() {
    if (!_closed) {
      _closed = true;
      _file.closeSync();
    }
  }
}

FileSystemException _overDirectory(String path, [OSError? osError]) =>
    FileSystemException("can't save a package over a directory", path, osError);

/// Throws [FileSystemException] if [path] is an existing directory.
@internal
void checkSaveDestination(String path) {
  if (FileSystemEntity.isDirectorySync(path)) {
    throw _overDirectory(path);
  }
}

// [e] as it would be for [path], of the same type, as upstream's
// `type(exc)(exc.errno, exc.strerror, path)` keeps `FileNotFoundError` and
// `PermissionError`.
FileSystemException _naming(FileSystemException e, String path) => switch (e) {
  PathNotFoundException() => PathNotFoundException(
    path,
    e.osError ?? const OSError(),
    e.message,
  ),
  PathAccessException() => PathAccessException(
    path,
    e.osError ?? const OSError(),
    e.message,
  ),
  PathExistsException() => PathExistsException(
    path,
    e.osError ?? const OSError(),
    e.message,
  ),
  _ => FileSystemException(e.message, path, e.osError),
};

/// Writes [bytes] to a temporary file next to [path] and renames it over
/// [path], as upstream's `_write_zip` does.
///
/// An error of the temporary file names [path] instead. The temporary file is
/// removed whatever happens.
@internal
void writePackageFile(String path, Uint8List bytes) {
  final tmp = File('$path.tmp-$pid');
  try {
    tmp.writeAsBytesSync(bytes);
    try {
      tmp.renameSync(path);
    } on FileSystemException catch (e) {
      if (FileSystemEntity.isDirectorySync(path)) {
        throw _overDirectory(path, e.osError);
      }
      rethrow;
    }
  } on FileSystemException catch (e) {
    if (e.path != tmp.path) {
      rethrow;
    }
    throw _naming(e, path);
  } finally {
    if (tmp.existsSync()) {
      tmp.deleteSync();
    }
  }
}
