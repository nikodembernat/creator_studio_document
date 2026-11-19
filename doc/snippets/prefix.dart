// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

/// The code of the "Names that clash with `dart:core` and Flutter" section of
/// `README.md`.
///
/// Each `// [name]` … `// [/name]` region is a code block of `README.md`, and
/// `test/examples/snippets_test.dart` runs this file.
library;

import 'dart:io';

import 'package:creator_studio_document/creator_studio_document.dart' as keyx;

void main() {
  // [prefix]
  final text = keyx.Text(string: 'Hello');
  final elapsed = Duration(seconds: text.string!.length); // `dart:core`'s.
  // [/prefix]
  stdout.writeln('${text.string} $elapsed');
}
