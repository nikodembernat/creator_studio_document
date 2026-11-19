// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:creator_studio_document/src/core/wire.dart';
import 'package:creator_studio_document/src/validation/errors.dart';

/// Follows the primary case of [model] through nested unions down to an
/// object, and returns the last case name with that object.
///
/// The name is empty if [model] is an object already. A valueless case holds
/// no model, so the first case that holds one, primary first, is followed.
///
/// Throws [DocumentValueError] if a union holds no case with a model, and
/// [ArgumentError] if [model] is neither an object nor a union of them.
(String, ObjectModel) unwrapPrimaryCase(WireModel model) {
  var name = '';
  var current = model;
  while (current is TaggedUnionModel) {
    (name, current) = _resolveCase(current);
  }
  if (current is! ObjectModel) {
    throw ArgumentError('`${current.wireSchema.name}` is not an object model');
  }
  return (name, current);
}

(String, WireModel) _resolveCase(TaggedUnionModel model) {
  for (final (name, value) in model.unionCaseEntries()) {
    if (value is WireModel) {
      return (name, value);
    }
  }
  throw DocumentValueError('`${model.wireSchema.name}` has no case present');
}
