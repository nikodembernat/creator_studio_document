// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:meta/meta.dart';

/// The error of encoding a union that has no case to write, which upstream's
/// `_wire_encode` raises as a `ValueError`.
///
/// It's a [StateError] to callers of `toJson` and `Package.save`;
/// `validateDocument` reports it as the `ValueError` that upstream documents.
@internal
final class NoCaseError(super.message) extends StateError {
  /// Creates an error with a message.
  this;
}

/// The error of encoding a value nested deeper than Pydantic's serializer
/// allows, which upstream raises as a `ValueError`.
///
/// It's a [StateError] to callers of `toJson` and `Package.save`;
/// `validateDocument` reports it as the `ValueError` that upstream raises.
@internal
final class SerializationDepthError() extends StateError {
  /// Creates an error.
  this : super('Maximum serialization depth exceeded');
}
