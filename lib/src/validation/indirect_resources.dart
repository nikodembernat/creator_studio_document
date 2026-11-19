// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:creator_studio_document/src/core/models.g.dart';
import 'package:creator_studio_document/src/core/package.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/core/wire.dart';
import 'package:creator_studio_document/src/navigation/navigation.dart';
import 'package:creator_studio_document/src/validation/errors.dart';
import 'package:creator_studio_document/src/validation/py_text.dart';
import 'package:creator_studio_document/src/validation/string_formats.dart';

/// Checks that every `IndirectResource` in [resolved], the payload with its
/// presets filled in, names a resource that [doc] stores.
///
/// It looks a resource up by its `identifier`, or by its `filename` when it
/// has none, as `ResourceStore.canResolve` matches names, and reads no
/// resource bytes.
///
/// Throws [DocumentValueError] for a blank name, and
/// [DocumentReferenceError] for a name that matches no stored resource.
void validateIndirectResources<T extends ObjectModel>(
  Package<T> doc,
  WireModel resolved,
) {
  for (final iterated in iterateModels(resolved)) {
    final model = iterated.model;
    if (model is! IndirectResource) {
      continue;
    }
    final path = iterated.path;
    final identifier = model.identifier;
    final (field, name) = identifier == null
        ? ('filename', model.filename)
        : ('identifier', identifier);
    if (pyIsBlank(name)) {
      throw DocumentValueError(
        '`IndirectResource.$field` ${pyStringRepr(name)} is empty or blank '
        '(at $path.$field)',
      );
    }
    if (field == 'identifier') {
      rejectEmpty(model.filename, path, 'filename', cls: 'IndirectResource');
    }
    if (doc.resources.resolveKey(name) == null) {
      throw DocumentReferenceError(
        '`IndirectResource.$field` ${pyStringRepr(name)} matches no stored '
        'resource (at $path.$field)',
      );
    }
  }
}
