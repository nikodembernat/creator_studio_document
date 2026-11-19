// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/core/wire.dart';
import 'package:creator_studio_document/src/navigation/navigation.dart';
import 'package:creator_studio_document/src/package_version.dart';
import 'package:logging/logging.dart';

/// The logger that `validateDocument` reports a [DocumentVersionWarning]
/// through.
final validationLogger = Logger('creator_studio_document.validation');

/// A warning about a union case this version of the library doesn't
/// implement.
///
/// A newer version of the app can write a value as several cases at once. The
/// new case is the primary, and an older case is a fallback for readers that
/// predate it. This version of the library doesn't implement the primary, so
/// `unionPrimary` and `unionCases` return the fallback, which can be a
/// different kind of value. A save still writes the primary back.
///
/// `validateDocument` issues the warning, where upstream issues a Python
/// warning of the same name: it logs a [Level.WARNING] record to
/// [validationLogger], the logger `creator_studio_document.validation`, with
/// the warning as the record's [LogRecord.object] and its [message] as the
/// record's message. Listen to the logger, and test
/// `record.object is DocumentVersionWarning`, to detect that a document was
/// read through a fallback. The message names the primary and the fallback.
/// Every check logs it again; nothing deduplicates it.
final class DocumentVersionWarning(
  /// The text of the warning.
  final String message, {

  /// The name of the model class that holds the union.
  required final String model,

  /// The primary case, as the document designates it.
  required final Object primary,

  /// The case that `unionPrimary` reads instead, or `null` if it reads none.
  required final String? fallback,

  /// The path of the union in the document, or `''` for the root.
  required final String path,
}) {
  /// Creates a warning.
  this;

  @override
  String toString() => message;
}

/// Logs a [DocumentVersionWarning] for every union in [payload] whose
/// designated primary case this library doesn't implement.
///
/// Throws [ArgumentError] for a primary case that's a list or an object, as
/// upstream raises `TypeError` for it.
void validateVersionDrift(WireModel payload) {
  for (final iterated in iterateModels(payload)) {
    final model = iterated.model;
    if (model is! TaggedUnionModel) {
      continue;
    }
    final primary = designatedPrimaryCase(model);
    if (primary == null) {
      continue;
    }
    // Upstream tests `primary in known_cases` on a set, which raises
    // `TypeError` for a list or a dictionary.
    if (primary case List<Object?>() || Map<Object?, Object?>()) {
      throw ArgumentError(
        "unhashable type: '${primary is List ? 'list' : 'dict'}'",
        'primary_case',
      );
    }
    final schema = model.wireSchema as UnionSchema<TaggedUnionModel>;
    if (primary is String && schema.caseSpec(primary) != null) {
      continue;
    }
    final fallback = model.unionPrimaryName();
    final reads = fallback == null ? 'no case' : pyStringRepr(fallback);
    final path = iterated.path;
    final where = path.isEmpty ? '<root>' : path;
    validationLogger.warning(
      DocumentVersionWarning(
        "`${schema.name}` primary case ${pyRepr(primary)} isn't implemented "
        'in this version of the library ($packageVersion), so `unionPrimary` '
        'reads $reads instead (at $where). Upgrade `creator_studio_document` '
        'to read and validate it.',
        model: schema.name,
        primary: primary,
        fallback: fallback,
        path: path,
      ),
    );
  }
}
