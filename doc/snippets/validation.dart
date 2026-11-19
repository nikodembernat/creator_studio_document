// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// docs/snippets/validation.py.

/// The code of the guide's "Validating a document" section of `README.md`.
///
/// Each `// [name]` … `// [/name]` region is a code block of the guide, and
/// `test/examples/snippets_test.dart` runs this file in a directory that holds
/// the files it reads.
library;

import 'dart:io';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';

void errors(String path) {
  // [errors]
  try {
    KeyxDocument.open(path);
  } on DocumentVersionError {
    stdout.writeln('$path needs a newer version of the library.');
  } on DocumentPackageError catch (e) {
    // Branch on `kind`. The message text varies.
    if (e.kind == DocumentPackageErrorKind.notAPackage) {
      stdout.writeln("$path isn't a document.");
    } else {
      stdout.writeln('$path is corrupt (${e.kind.value}).');
    }
  } on ModelValidationError {
    stdout.writeln("$path doesn't match this library's models.");
  } on FileSystemException catch (e) {
    stdout.writeln("Can't read $path: ${e.osError?.message ?? e.message}.");
  }
  // [/errors]
}

void validate() {
  // [validate]
  final doc = KeyxDocument.open('presentation.keyx');
  final slides = doc.presentation.slides;
  slides.first.note = Text(string: 'Checked before saving.');

  // Writes nothing if the document is invalid.
  doc.save('out.keyx', preSaveHooks: [validateDocument]);
  // [/validate]
}

/// Reports the error of opening each path in [args], which defaults to
/// `not-a-presentation.keyx`, then validates and saves `presentation.keyx`.
void main(List<String> args) {
  (args.isEmpty ? ['not-a-presentation.keyx'] : args).forEach(errors);
  validate();
}
