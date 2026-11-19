// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// Keynote `.keyx` documents, a [Package] with a [Presentation] root model.
library;

import 'dart:typed_data';

import 'package:creator_studio_document/src/core/models.g.dart';
import 'package:creator_studio_document/src/core/package.dart';
import 'package:creator_studio_document/src/core/wire.dart';

/// A document that holds a presentation with its presets, manifest, and
/// resources.
///
/// Opening, saving, and closing work as they do for [Package]; see
/// [Package.open], [Package.openLazy], [Package.save], and [Package.close].
/// `main.json` is validated against [Presentation].
class KeyxDocument extends Package<Presentation> {
  /// Creates a document of [payload], the presentation, with [presets],
  /// [manifest], and [resources], the `Data/` resources as a map from
  /// filename to bytes.
  new(super.payload, {super.presets, super.manifest, super.resources});

  new _of(Package<Presentation> package)
    : super(
        package.payload,
        presets: package.presets,
        manifest: package.manifest,
        resources: package.resources,
      );

  /// Reads a document from the bytes of a `.keyx` archive, with every
  /// resource. Throws as [Package.fromBytes] does.
  factory fromBytes(Uint8List bytes) =>
      KeyxDocument._of(Package.fromBytes(bytes, payloadModel: payloadModel));

  /// Opens the `.keyx` file at [path], with every resource already read.
  /// Throws as [Package.open] does.
  factory open(String path) =>
      KeyxDocument._of(Package.open(path, payloadModel: payloadModel));

  /// Opens the `.keyx` file at [path] and reads each resource only on first
  /// access, holding the file open until [close] runs. Throws as
  /// [Package.openLazy] does.
  factory openLazy(String path) =>
      KeyxDocument._of(Package.openLazy(path, payloadModel: payloadModel));

  /// The schema that `main.json` is validated against, [Presentation]'s.
  static ObjectSchema<Presentation> get payloadModel => Presentation.schema;

  /// The document's presentation, decoded from `main.json`.
  ///
  /// [presentation] and [payload] return the same object.
  Presentation get presentation => payload;
}
