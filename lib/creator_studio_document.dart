// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// Keynote Interchange Format models, and the codec that reads and writes
/// them.
///
/// Every model has a `fromJson` constructor and a `toJson` method. Some model
/// names, such as `Duration`, `Pattern`, and `Image`, are also names in
/// `dart:core` or in other packages; import this library with a prefix where
/// that matters.
///
/// `KeyxDocument` reads and writes a whole `.keyx` package: the presentation,
/// its presets, its manifest, and its resources.
library;

export 'src/core/errors.dart';
export 'src/core/json.dart' show sameJson;
export 'src/core/keyx.dart';
export 'src/core/models.g.dart';
export 'src/core/override.dart';
export 'src/core/package.dart'
    show Manifest, Package, PreSaveHook, supportedPackageMajor;
export 'src/core/preset.dart';
export 'src/core/resources.dart' show ResourceStore;
export 'src/core/version.dart';
export 'src/core/wire.dart'
    hide decodeWireValue, designatedPrimaryCase, revalidateWireModel;
export 'src/package_version.dart';
