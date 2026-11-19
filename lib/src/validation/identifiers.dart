// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/validation/errors.dart';

/// Records that [key], the value of [field] at [path], is taken in [seen].
///
/// Throws [DocumentValueError] if an earlier value took [key].
void claimUnique(
  Map<String, String> seen,
  String key,
  String path,
  String field,
) {
  if (seen[key] case final existingPath?) {
    throw DocumentValueError(
      '`$field` ${pyStringRepr(key)} is a duplicate (at $path). The first '
      'is at $existingPath.',
    );
  }
  seen[key] = path;
}
