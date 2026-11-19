// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// src/creator_studio_doc_format/examples/authoring.py.

/// Builds a themed presentation with `package:creator_studio_document/
/// authoring.dart`.
///
/// ```sh
/// dart run example/authoring.dart [input] [output]
/// ```
///
/// The theme already gives everything a meaningful name: slide layouts,
/// placeholders, placeholder prompts, and styles. The example reads those
/// names back through `summarizeSlideLayouts` and directly from
/// `stylesheet.paragraphStyles`, and addresses content by name instead of by
/// index.
///
/// The following lines inspect the theme in `fixtures/Tidal_en.keyx`:
///
/// ```dart
/// final doc = KeyxDocument.open('example/fixtures/Tidal_en.keyx');
/// summarizeSlideLayouts(doc.presentation.theme!).keys.first; // 'Title'
/// final pairs = [
///   for (final s in doc.presentation.stylesheet!.paragraphStyles!)
///     if (s.properties.presetIdentifier.isNotEmpty)
///       (s.name, s.properties.presetIdentifier),
/// ];
/// // A (style name, preset identifier) pair:
/// pairs.first; // ('Title Small', 'text-1-paragraphstyle-Title Alt')
/// // The preset identifier can differ from the style name:
/// Map.fromEntries([for (final (n, id) in pairs) MapEntry(n, id)])['Title Small'];
/// // 'text-1-paragraphstyle-Title Alt'
/// final reg = PresetRegistry(doc.presets);
/// const body = 'text-2-paragraphstyle-Body'; // Query by identifier.
/// reg.resolvedProperties(body)['space_after']; // 24
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:creator_studio_document/authoring.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';
import 'package:logging/logging.dart';

import 'src/support.dart';

final _log = Logger('authoring');

// The theme has no preset for this color, so it is set inline.
final _accent = RGBA(red: 0.929, green: 0.353, blue: 0.157);

// Vertical extent of the pillar text columns, in points.
const _textTop = 570.0;
const _bodyBottom = 980.0;

/// Maps each style name to its preset identifier, for the (name, preset
/// identifier) pairs of [styles] that have both.
Map<String, String> _presetIdentifiers(Iterable<(String?, String)> styles) => {
  for (final (name, identifier) in styles)
    if (name != null && name.isNotEmpty && identifier.isNotEmpty)
      name: identifier,
};

/// Returns the larger resolved `space_after` of `"Subtitle"` and `"Body"`.
///
/// The registry warns about a missing preset instead of throwing, so this
/// function throws on `reg.warnings` rather than letting the gap fall back to
/// `0.0`.
num _headingGap(List<Preset> presets, Map<String, String> paragraphStyles) {
  final reg = PresetRegistry(presets);
  // A preset that clears `space_after` leaves an explicit `null`, which the
  // `?? 0.0` covers as it covers a missing key.
  num spaceAfter(String style) =>
      reg.resolvedProperties(paragraphStyles[style]!)['space_after'] as num? ??
      0.0;
  final gap = math.max(spaceAfter('Subtitle'), spaceAfter('Body'));
  if (reg.warnings.isNotEmpty) {
    throw StateError('Unresolved preset reference: ${reg.warnings.join(', ')}');
  }
  return gap;
}

/// Builds a freeform column, styled entirely from the document's presets.
SlideObject _column(
  double x,
  String heading,
  List<String> lines,
  Map<String, String> paragraphStyles,
  String textboxPresetId, {
  required double headingGap,
  bool accent = false,
}) {
  final runStyle = accent
      ? CharacterProperties(
          characterFill: Override.value(Fill(color: Color(rgba: _accent))),
        )
      : null;
  // The heading gets a wide gap below it, and the items get tight spacing.
  // The presets give `"Subtitle"` the smaller `space_after`, so the caller
  // passes the larger.
  final headingParagraph = Paragraph(
    style: ParagraphProperties(
      presetIdentifier: paragraphStyles['Subtitle'],
      spaceAfter: Override.value(headingGap),
    ),
    contents: [
      Constituent(
        run: TextRun(string: heading, style: runStyle),
      ),
    ],
  );
  final body = [
    for (final line in lines)
      Paragraph(
        style: ParagraphProperties(
          presetIdentifier: paragraphStyles['Body'],
          spaceAfter: const Override.value(6),
        ),
        contents: [Constituent(run: TextRun(string: line))],
      ),
  ];
  return SlideObject(
    object: CanvasObject(
      textbox: Textbox(
        presetIdentifier: textboxPresetId,
        stroke: Stroke(empty: true),
        // Top alignment keeps the gap above the heading the same at any line
        // count.
        layoutProperties: LayoutProperties(
          verticalAlignment: const Override.value(VerticalAlignmentType.top),
          padding: Override.value(
            Insets(top: 0, bottom: 0, left: 24, right: 24),
          ),
        ),
        geometry: Geometry(
          position: Position(x: x, y: _textTop),
          size: Size(width: 500, height: _bodyBottom - _textTop),
        ),
        text: Text(paragraphs: [headingParagraph, ...body]),
      ),
    ),
  );
}

/// Builds the example presentation from a themed one and saves it.
void main(List<String> args) {
  printLogRecords();
  final parsed = parseArguments(
    args,
    script: 'authoring',
    description:
        'Builds a themed presentation with '
        '`package:creator_studio_document/authoring.dart`.\n'
        'The input is a .keyx exported from Keynote.',
    names: ['input', 'output'],
    defaults: [fixture('Tidal_en.keyx'), defaultOutput('authoring.keyx')],
  );
  if (parsed == null) {
    return;
  }
  final [input, output] = parsed;

  final doc = KeyxDocument.open(input);
  final pres = doc.presentation;
  final theme = pres.theme;
  if (theme != null && theme.slideLayouts != null) {
    for (final MapEntry(key: name, value: placeholders)
        in summarizeSlideLayouts(theme).entries) {
      _log.info(
        [
          name,
          for (final p in placeholders)
            '    ${p.name}:${p.objectCase} ${jsonEncode(p.prompt)}',
        ].join('\n'),
      );
    }

    // Text placeholders differ by name and prompt. On the `"Quote"` layout,
    // `"Text"` is the quotation and `"Text-1"` is the attribution.
    final slideSpecs = [
      (
        'Photo - Horizontal',
        {
          'TITLE': ['Our Community Garden'],
          'BODY': ['Growing food together, one bed at a time'],
        },
      ),
      (
        'Title, Bullets & Photo',
        {
          'TITLE': ['Season Plan'],
        },
      ),
      (
        'Quote',
        {
          'Text': [
            'A garden grows one seed at a time, and so does a community.',
          ],
          'Text-1': ['Community Garden Volunteer'],
        },
      ),
    ];
    final built = <Slide>[];
    for (final (layout, texts) in slideSpecs) {
      final slide = slideFromLayout(theme, layout);
      for (final MapEntry(key: name, value: lines) in texts.entries) {
        setSlidePlaceholderText(slide, name, lines);
      }
      built.add(slide);
    }

    final seasonPlan = built.firstWhere(
      (s) => s.layout == 'Title, Bullets & Photo',
    );
    setSlidePlaceholderText(
      seasonPlan,
      'BODY',
      [
        'Spring',
        'Build raised beds',
        'Sow seeds',
        'Summer',
        'Harvest and share',
      ],
      listLevels: [0, 1, 1, 0, 1],
    );

    // Give the "Season Plan" slide's `"Media"` placeholder a new image. The
    // new resource replaces the theme's sample photo.
    final filename = doc.resources.uniqueFilename('season_plan.png');
    doc.resources[filename] = File(fixture('photo_placeholder.png'))
        .readAsBytesSync();
    setSlidePlaceholderImage(
      seasonPlan,
      'Media',
      Resource(indirect: IndirectResource(filename: filename)),
      size: Size(width: 1200, height: 792), // The PNG's width and height.
    );

    // Content outside the placeholders uses the theme's styles. `stylesheet`
    // is optional, so these maps can be empty.
    final stylesheet = pres.stylesheet;
    final paragraphStyles = _presetIdentifiers([
      for (final s in stylesheet?.paragraphStyles ?? const <ParagraphStyle>[])
        (s.name, s.properties.presetIdentifier),
    ]);
    for (final MapEntry(key: name, value: identifier)
        in paragraphStyles.entries) {
      _log.info('$name -> $identifier');
    }
    // A theme with no textbox style gets a bare `Textbox` with no preset.
    final textboxPresetId =
        _presetIdentifiers([
          for (final s in stylesheet?.textboxStyles ?? const <ShapeStyle>[])
            (s.name, s.properties.presetIdentifier),
        ]).values.firstOrNull ??
        '';
    final headingGap = _headingGap(doc.presets, paragraphStyles);
    _log.info('resolved heading gap: ${headingGap}pt');

    final hybrid = slideFromLayout(theme, 'Title & Bullets');
    setSlidePlaceholderText(hybrid, 'TITLE', ['Three pillars']);
    // Clear the footer's sample text, which `slideFromLayout` keeps.
    setSlidePlaceholderText(hybrid, 'Presentation Name', null);
    // Each pillar holds x, heading, body lines, and whether it's the accent
    // column.
    final pillars = [
      (140.0, 'Plan', ['Map the beds', 'Pick the crops'], false),
      (710.0, 'Plant', ['Water daily', 'Pull weeds'], false),
      (1280.0, 'Harvest', ['Pick when ripe', 'Share the surplus'], true),
    ];
    // `contents` is `null` on a layout with no canvas objects.
    final contents = hybrid.contents ??= [];
    for (final (x, heading, lines, accent) in pillars) {
      contents.add(
        _column(
          x,
          heading,
          lines,
          paragraphStyles,
          textboxPresetId,
          headingGap: headingGap.toDouble(),
          accent: accent,
        ),
      );
    }
    final quoteIndex = built.indexWhere((s) => s.layout == 'Quote');
    built.insert(quoteIndex, hybrid);

    // Assigning the list replaces the slide that the exported file starts
    // with.
    pres.slides = built;
  }

  ensureParent(output);
  doc.save(output, preSaveHooks: [validateDocument]);
  _log.info('Wrote $output');
}
