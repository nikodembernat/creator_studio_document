// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// docs/snippets/authoring.py.

/// The code of the guide's "Authoring from a theme" section of `README.md`.
///
/// Each `// [name]` … `// [/name]` region is a code block of the guide, and
/// `test/examples/snippets_test.dart` runs this file in a directory that holds
/// the files it reads.
library;

import 'dart:io';

import 'package:creator_studio_document/authoring.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';

(KeyxDocument, KeynoteTheme) summarize() {
  // [summarize]
  final doc = KeyxDocument.open('themed.keyx');
  final theme = doc.presentation.theme!;

  for (final MapEntry(key: layout, value: placeholders)
      in summarizeSlideLayouts(theme).entries) {
    stdout.writeln('$layout ${[for (final p in placeholders) p.name]}');
  }
  // [/summarize]
  return (doc, theme);
}

Slide fromLayout(KeynoteTheme theme) {
  // [slide-from-layout]
  final slide = slideFromLayout(theme, 'Title & Bullets');
  // [/slide-from-layout]
  return slide;
}

void setText(Slide slide) {
  // [set-slide-placeholder-text]
  setSlidePlaceholderText(slide, 'TITLE', ['Baking Sourdough']);
  setSlidePlaceholderText(
    slide,
    'BODY',
    ['Feed the starter', 'Twice a day'],
    // Sets each line's list level. Every level keeps the placeholder's
    // paragraph style.
    listLevels: [0, 1],
  );
  // Passing null clears the tagged placeholder's sample text.
  setSlidePlaceholderText(slide, 'Presentation Name', null);
  // [/set-slide-placeholder-text]
}

Slide setImage(KeyxDocument doc, KeynoteTheme theme) {
  // [set-slide-placeholder-image]
  final photo = slideFromLayout(theme, 'Title, Bullets & Photo');
  final filename = doc.resources.uniqueFilename('cover.png');
  doc.resources[filename] = File('cover.png').readAsBytesSync();
  setSlidePlaceholderImage(
    photo,
    'Media',
    Resource(indirect: IndirectResource(filename: filename)),
    // The width and height of cover.png, so the image fills the
    // placeholder's mask without stretching.
    size: Size(width: 1200, height: 792),
  );
  // [/set-slide-placeholder-image]
  return photo;
}

KeyxDocument together() {
  // [together]
  final sections = [
    ('Baking Sourdough', ['Feed the starter', 'Shape the loaf']),
    ('Baking Day', ['Preheat the oven']),
  ];

  final doc = KeyxDocument.open('themed.keyx');
  final theme = doc.presentation.theme!;

  final slides = <Slide>[];
  for (final (title, bullets) in sections) {
    final slide = slideFromLayout(theme, 'Title & Bullets');
    setSlidePlaceholderText(slide, 'TITLE', [title]);
    setSlidePlaceholderText(slide, 'BODY', bullets);
    setSlidePlaceholderText(slide, 'Presentation Name', null);
    slides.add(slide);
  }

  // Replacing the slides in place keeps the theme, its presets, and
  // everything else in the document.
  doc.presentation.slides = slides;
  doc.save('presentation.keyx', preSaveHooks: [validateDocument]);
  // [/together]
  return doc;
}

void presets(KeyxDocument doc) {
  // [presets]
  final styles = {
    for (final style in doc.presentation.stylesheet!.paragraphStyles!)
      if (style.properties.presetIdentifier.isNotEmpty)
        style.name: style.properties.presetIdentifier,
  };
  final registry = PresetRegistry(doc.presets);
  final font =
      registry.resolvedProperties(styles['Body']!)['character_properties']!
          as Map<String, Object?>;
  stdout.writeln('${font['font_name']} ${font['font_size']}');
  // [/presets]
}

void main() {
  final (doc, theme) = summarize();
  final slide = fromLayout(theme);
  setText(slide);
  final photo = setImage(doc, theme);
  doc.presentation.slides.addAll([slide, photo]);
  doc.save('slides.keyx', preSaveHooks: [validateDocument]);
  presets(together());
}
