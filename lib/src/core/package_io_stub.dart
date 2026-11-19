// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// The file access of a package where `dart:io` is missing, such as on the
/// web: every function throws [UnsupportedError].
library;

import 'dart:typed_data';

import 'package:creator_studio_document/src/core/package_zip.dart';
import 'package:meta/meta.dart';

Never _unsupported() => throw UnsupportedError(
  'Opening and saving a package by path needs dart:io; use '
  'Package.fromBytes and Package.toBytes instead',
);

/// Returns the bytes of the package file at [path].
@internal
Uint8List readPackageFile(String path) => _unsupported();

/// Opens the package file at [path] for random access.
@internal
ZipSource openPackageFile(String path) => _unsupported();

/// Checks that a package can be saved at [path].
@internal
void checkSaveDestination(String path) => _unsupported();

/// Writes [bytes] to [path] atomically.
@internal
void writePackageFile(String path, Uint8List bytes) => _unsupported();
