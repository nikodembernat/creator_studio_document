// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:creator_studio_document/src/core/py_repr.dart';

/// The defect that a document package error reports.
///
/// Test [DocumentPackageError.kind] to tell the defects apart. Every member is
/// a defect in the bytes. A caller that skips any [DocumentPackageError]
/// therefore stays correct for a member added later. A limit of the reader
/// throws [DocumentVersionError] instead.
enum DocumentPackageErrorKind(
  /// The kind's name as upstream spells it, such as `malformed_json`.
  final String value,
) {
  /// A ZIP archive that can't be read, such as a truncated or encrypted one, or
  /// one with a checksum that doesn't match.
  malformedArchive('malformed_archive'),

  /// A payload file that isn't valid JSON, or a payload or manifest file
  /// that nests arrays and objects deeper than Python's JSON reader does.
  ///
  /// The payload file is `main.json`. A bad manifest is otherwise defaulted.
  /// No writer that follows the format nests that deep: upstream doesn't save
  /// a value nested more than 256 levels deep.
  malformedJson('malformed_json'),

  /// A presets file that isn't a JSON array or that nests too deeply, as for
  /// [malformedJson], a preset without properties, or a preset cycle that the
  /// payload actually reaches.
  ///
  /// The presets file is `presets.json`, and a preset's properties are its
  /// `properties` key.
  malformedPresets('malformed_presets'),

  /// A package without a payload file.
  ///
  /// The payload file is `main.json`.
  missingMainFile('missing_main_file'),

  /// A file or stream that isn't a ZIP archive, or a path that isn't a regular
  /// file, such as a directory.
  notAPackage('not_a_package'),
}

/// The library can't read the input far enough to validate it.
///
/// Each subclass tells a batch caller what to do with the input:
///
/// - [DocumentPackageError] means the data is wrong. Skip the file.
/// - [DocumentVersionError] means the library is too old for the data. Stop
///   the run and upgrade.
///
/// Catch this base class only to report that the input couldn't be read.
///
/// A payload that parses but doesn't match the models throws neither subclass.
/// Because the mismatch can equally mean that the models are behind the
/// exporter, it throws [ModelValidationError]. A caller's mistakes throw
/// built-in errors.
class DocumentError(
  /// The text that [toString] returns.
  final String message,
) implements Exception {
  /// Creates an error with a message.
  this;

  @override
  String toString() => message;
}

/// The document's bytes are invalid, and no Keynote export produces bytes like
/// them.
class DocumentPackageError(
  /// The defect.
  final DocumentPackageErrorKind kind,
  super.message,
) extends DocumentError {
  /// Creates an error for the defect [kind].
  this;
}

/// An error that means this library is too old to read the document.
///
/// The document can still be valid.
///
/// The library throws this error when the package or any object declares a
/// newer major version. Lenient decoding instead skips a value with a newer
/// major version that a preset supplies for an optional or defaulted field, and
/// leaves the field unset.
///
/// The class itself names the cause, and the error has no kind. This is the
/// one failure with a certain fix, which its message names.
class DocumentVersionError(super.message) extends DocumentError {
  /// Creates an error with a message.
  this;
}

/// A preset's `parent_identifier` chain loops back on itself.
///
/// Upstream raises a `ValueError` for this. Decoding reports it as a
/// [ModelValidationError] issue at the object that adopts the preset, as
/// upstream's validation does.
class PresetCycleError(
  /// The identifier at which the chain revisits a preset.
  ///
  /// It's a [String] unless a preset entry holds an identifier that isn't
  /// one, such as a number, which another entry's `parent_identifier` names.
  final Object identifier,
) implements Exception {
  /// Creates an error for the cycle found at [identifier].
  this;

  @override
  String toString() =>
      'circular preset `parent_identifier` chain at ${pyRepr(identifier)}';
}

/// One problem that decoding or construction found in a value.
class const ValidationIssue(
  /// The path to the value: field names, case names, and list indexes.
  final List<Object> location,

  /// A description of the problem.
  final String message, {

  /// A short machine-readable classifier, such as `missing` or `float_type`.
  final String type = 'value',
}) {
  /// Creates an issue at [location].
  this;

  /// The location joined with dots, as upstream prints it.
  String get path => location.join('.');

  @override
  String toString() => '${path.isEmpty ? '(root)' : path}: $message';
}

/// A payload that parses as JSON but doesn't match the models, or a model
/// constructed or assigned with a value that breaks a constraint.
///
/// It's the Dart counterpart of Pydantic's `ValidationError`. The mismatch can
/// equally mean that the models are behind the exporter.
class ModelValidationError(
  /// The name of the model or type that failed to validate.
  final String title,
  List<ValidationIssue> issues,
) implements Exception {
  /// Creates an error for [title] with its [issues].
  this;

  /// Every problem found, in the order the fields were checked.
  final List<ValidationIssue> issues = List.unmodifiable(issues);

  @override
  String toString() {
    final buffer = StringBuffer(
      '${issues.length} validation error${issues.length == 1 ? '' : 's'} '
      'for $title',
    );
    for (final issue in issues) {
      buffer
        ..write('\n')
        ..write(issue.path.isEmpty ? '(root)' : issue.path)
        ..write('\n  ')
        ..write(issue.message)
        ..write(' [type=${issue.type}]');
    }
    return buffer.toString();
  }
}
