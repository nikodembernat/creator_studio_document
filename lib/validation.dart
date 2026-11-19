// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// Checks in-place edits, presets, and references across a document before
/// you save it.
///
/// `validateDocument` throws a `DocumentValidationError` on an invalid value
/// in a `Package`, naming its path, before the document is saved. Pass it as
/// a `preSaveHooks` entry of `Package.save` to check every save:
///
/// ```dart
/// doc.save(path, preSaveHooks: [validateDocument]);
/// ```
library;

export 'src/validation/errors.dart';
export 'src/validation/validate_document.dart' show validateDocument;
export 'src/validation/version_drift.dart'
    show DocumentVersionWarning, validationLogger;
