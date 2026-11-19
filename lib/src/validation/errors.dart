// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// A value in a document that breaks the format's rules, which
/// `validateDocument` reports before the document is saved.
///
/// Upstream raises Python's built-in errors instead. Each subclass stands for
/// one of them:
///
/// - [DocumentValueError], for upstream's `ValueError`: a value violates an
///   invariant, such as a duplicate identifier, a malformed string, or a value
///   that its field's declaration rejects.
/// - [DocumentReferenceError], for upstream's `LookupError`: a preset,
///   identifier, or reference doesn't resolve.
///
/// Catch the base class to report any violation, and a subclass to tell a
/// dangling reference from a malformed value. [message] matches upstream's
/// text and names the path of the offending value, such as
/// `(at slides[0].contents[1].object.shape.identifier)`. The hint about a
/// value that skipped validation is the exception: upstream's names three
/// Python ways to skip it, in-place mutation, `model_construct`, and
/// `model_copy(update=...)`, and the port's names the only one Dart has, an
/// in-place change.
sealed class DocumentValidationError(
  /// The text that [toString] returns.
  final String message, {

  /// The error that led to this one, such as the `ModelValidationError` of
  /// a value that doesn't decode, or `null`.
  final Object? cause,
}) implements Exception {
  /// Creates an error with a message.
  this;

  @override
  String toString() => message;
}

/// A value violates an invariant of the format, as upstream's `ValueError`
/// reports it.
final class DocumentValueError(super.message, {super.cause})
    extends DocumentValidationError {
  /// Creates an error with a message.
  this;
}

/// A preset, identifier, or reference doesn't resolve, as upstream's
/// `LookupError` reports it.
final class DocumentReferenceError(super.message, {super.cause})
    extends DocumentValidationError {
  /// Creates an error with a message.
  this;
}
