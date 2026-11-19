// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// docs/snippets/navigation.py.

/// The code of the guide's "Navigating a document efficiently" section of
/// `README.md`.
///
/// Each `// [name]` … `// [/name]` region is a code block of the guide, and
/// `test/examples/snippets_test.dart` runs this file in a directory that holds
/// the files it reads.
library;

import 'dart:convert';
import 'dart:io';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/navigation.dart';

KeyxDocument iterate() {
  // [iterate]
  final doc = KeyxDocument.open('presentation.keyx');
  // Per slide, because the presentation also holds placeholder text from
  // slide layouts.
  for (final (index, slide) in doc.presentation.slides.indexed) {
    for (final item in iterateModels(slide)) {
      if (item.model
          case TextRun(:final String string) || Text(:final String string)
          when string.isNotEmpty) {
        stdout.writeln('${index + 1} ${jsonEncode(string)}');
      }
    }
  }
  // [/iterate]
  return doc;
}

void captions(KeyxDocument doc) {
  // [captions]
  for (final (index, slide) in doc.presentation.slides.indexed) {
    for (final item in iterateModels(slide)) {
      if (item.model
          case TextRun(:final String string) || Text(:final String string)
          when string.isNotEmpty) {
        if (item.ancestors.any((ancestor) => ancestor is Image)) {
          stdout.writeln('${index + 1} ${jsonEncode(string)}');
        }
      }
    }
  }
  // [/captions]
}

void lazy() {
  // [lazy]
  final big = KeyxDocument.openLazy('big-presentation.keyx');
  try {
    stdout.writeln(big.presentation.slides.length); // This reads no resource.
    final photo = big.resources['sample_photo.jpg']; // This reads only that.
    stdout.writeln('${photo!.length} bytes');
  } finally {
    big.close();
  }
  // [/lazy]
}

void main() {
  captions(iterate());
  lazy();
}
