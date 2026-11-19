// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python),
// tests/authoring/test_slide_layouts_tidal.py.

@TestOn('vm')
library;

import 'package:creator_studio_document/authoring.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/navigation.dart';
import 'package:creator_studio_document/src/authoring/slide_layouts.dart'
    show firstText, placeholderName;
import 'package:creator_studio_document/validation.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _fixture = 'test/fixtures/Tidal_en.keyx';

const _layouts = [
  'Title',
  'Title & Bullets',
  'Hidden Definitions',
  'Layered Decoration',
  'Title, Bullets & Photo',
  'Photo - Horizontal',
  'Captioned Image',
  'Quote',
  'Instructional Prompts',
  'Mixed Content Types',
  'Shared Tag Duplicate',
  'Layered Group Decoration',
  'Title, Bullets & Live Video',
  'Layered Photo Decoration',
  'Nested Lists',
  'Blank',
];

final KeyxDocument _doc = KeyxDocument.open(_fixture);

KeynoteTheme get _theme {
  final theme = _doc.presentation.theme;
  expect(theme, isNotNull);
  return theme!;
}

Map<String, Slide> _realSlides() {
  final names = {
    for (final l in _theme.slideLayouts ?? const <SlideLayout>[])
      ?l.identifier: l.name,
  };
  final laidOut = [
    for (final s in _doc.presentation.slides)
      if (s.layout case final layout?) (layout, s),
  ];
  final slides = {
    for (final (layout, s) in laidOut) names[layout] ?? layout: s,
  };
  final missing = [
    for (final name in _layouts)
      if (!slides.containsKey(name)) name,
  ];
  expect(
    missing,
    isEmpty,
    reason:
        '`Tidal_en.keyx` has no slide for the layouts $missing. Add one slide '
        'per layout in Keynote and export the file again.',
  );
  expect(
    slides,
    hasLength(laidOut.length),
    reason:
        '`Tidal_en.keyx` has more than one slide for some layout. Delete the '
        'extra slides so each test compares against one slide per layout.',
  );
  return slides;
}

List<SlideObject> _objects(WireModel slide) => [
  for (final item in iterateModels(slide))
    if (item.model case final SlideObject obj) obj,
];

String? _identifier(SlideObject obj) {
  final payload = obj.object.unionPrimary()?.payload;
  if (payload is! ObjectModel) {
    return null;
  }
  final schema = payload.wireSchema as ObjectSchema<ObjectModel>;
  return schema.field('identifier') == null
      ? null
      : payload.wireGet('identifier') as String?;
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

// `str(uuid.UUID(value)) == value.lower()`.
bool _isUuid(String value) => _uuid.hasMatch(value.toLowerCase());

(String?, String?, String?) _signature(SlideObject obj) =>
    (obj.sourceKind?.name, obj.object.unionPrimaryName(), placeholderName(obj));

SlideObject _named(Slide slide, String name) =>
    _objects(slide).firstWhere((o) => placeholderName(o) == name);

void main() {
  test('the fixture slides carry Keynote-generated identifiers', () {
    final layoutIdentifiers = {
      for (final layout in _theme.slideLayouts ?? const <SlideLayout>[])
        for (final obj in _objects(layout)) ?_identifier(obj),
    };
    for (final MapEntry(key: name, value: slide) in _realSlides().entries) {
      expect(
        slide.identifier != null && _isUuid(slide.identifier!),
        isTrue,
        reason:
            "The slide for layout '$name' has identifier "
            "'${slide.identifier}', which isn't a UUID. Keynote writes a UUID "
            'there, so check whether someone edited the fixture by hand.',
      );
      for (final obj in _objects(slide)) {
        final placeholder = placeholderName(obj);
        if (placeholder == null) {
          continue;
        }
        final identifier = _identifier(obj);
        expect(
          identifier != null &&
              _isUuid(identifier) &&
              !layoutIdentifiers.contains(identifier),
          isTrue,
          reason:
              "Placeholder '$placeholder' on the slide for layout '$name' "
              "has identifier '$identifier'. Each placeholder on a slide "
              "needs its own UUID, distinct from the layout's.",
        );
      }
    }
  });

  for (final layout in _layouts) {
    test("slideFromLayout matches Keynote's object set: $layout", () {
      final real = _realSlides()[layout]!;
      final made = slideFromLayout(_theme, layout);
      expect(
        [for (final o in _objects(made)) _signature(o)],
        [for (final o in _objects(real)) _signature(o)],
      );
    });
  }

  test('clearing the title drops the run, like Keynote', () {
    final real = _realSlides()['Title & Bullets']!;
    final made = slideFromLayout(_theme, 'Title & Bullets');
    final realText = firstText(_named(real, 'TITLE'));
    final madeText = firstText(_named(made, 'TITLE'));
    expect(realText?.paragraphs, isNotNull);
    expect(madeText?.paragraphs, isNotNull);
    expect(realText!.paragraphs![0].contents, isNull);
    expect(madeText!.paragraphs![0].contents, isNull);
  });

  test('the image flags and crop match Keynote', () {
    final real = _realSlides()['Title, Bullets & Photo']!;
    final made = slideFromLayout(_theme, 'Title, Bullets & Photo');
    final realImg = _named(real, 'Media').object.image;
    final madeImg = _named(made, 'Media').object.image;
    expect(realImg, isNotNull);
    expect(madeImg, isNotNull);
    expect(realImg!.wasMediaReplaced, isFalse);
    expect(madeImg!.wasMediaReplaced, isFalse);
    expect(realImg.isPlaceholder, isTrue);
    expect(madeImg.isPlaceholder, isTrue);
    expect(madeImg.geometry, realImg.geometry);
    expect(madeImg.mask, realImg.mask);
  });

  test('the caption survives, like Keynote', () {
    final real = _realSlides()['Captioned Image']!;
    final made = slideFromLayout(_theme, 'Captioned Image');
    final realImg = _named(real, 'Media').object.image;
    final madeImg = _named(made, 'Media').object.image;
    expect(realImg?.caption?.text, isNotNull);
    expect(madeImg?.caption?.text, isNotNull);
    final realRuns = paragraphRuns(
      realImg!.caption!.text!.paragraphs ?? const [],
    );
    final madeRuns = paragraphRuns(
      madeImg!.caption!.text!.paragraphs ?? const [],
    );
    expect(madeRuns, realRuns);
    expect(realRuns, ['Photo caption sample']);
  });

  test('a live video placeholder takes an image like an image placeholder', () {
    const layout = 'Title, Bullets & Live Video';
    final real = _realSlides()[layout]!;
    final made = slideFromLayout(_theme, layout);

    final realObj = _named(real, 'Live Video');
    final madeObj = _named(made, 'Live Video');
    expect(realObj.object.image, isNotNull);
    expect(madeObj.object.image, isNotNull);
    expect(madeObj.object.image!.resource, realObj.object.image!.resource);

    final image = setSlidePlaceholderImage(
      made,
      'Live Video',
      Resource(indirect: IndirectResource(filename: 'frame.png')),
    );
    expect(image.wasMediaReplaced, isTrue);
  });

  test('nested list text keeps its list style and levels, like Keynote', () {
    const layout = 'Nested Lists';
    final real = _realSlides()[layout]!;
    final made = slideFromLayout(_theme, layout);

    List<(String?, int?)> levels(Slide slide, String tag) {
      final text = firstText(_named(slide, tag));
      expect(text, isNotNull);
      return [
        for (final p in text!.paragraphs ?? const <Paragraph>[])
          (p.listStyle?.presetIdentifier, p.listLevel),
      ];
    }

    const outline = 'text-5-liststyle-Outline';
    expect(levels(made, 'Text'), levels(real, 'Text'));
    expect(levels(made, 'Text'), [
      for (final level in [null, 1, 2, 3, 4, 5]) (outline, level),
    ]);
    expect(levels(made, 'Text-1'), levels(real, 'Text-1'));
    expect(
      {for (final (style, _) in levels(made, 'Text-1')) style},
      {'text-1-liststyle-Bullet'},
    );
  });

  test('a layered slide copies the layout image, like Keynote', () {
    const layout = 'Layered Photo Decoration';
    final real = _realSlides()[layout]!;
    final made = slideFromLayout(_theme, layout);
    final realObjs = _objects(real);
    final madeObjs = _objects(made);
    expect(
      [for (final o in madeObjs) o.sourceKind],
      [for (final o in realObjs) o.sourceKind],
    );
    final realImg = realObjs.firstWhere((o) => o.object.image != null);
    final madeImg = madeObjs.firstWhere((o) => o.object.image != null);
    expect(madeImg.object.image!.resource, realImg.object.image!.resource);
    expect(
      madeImg.object.image!.wasMediaReplaced,
      realImg.object.image!.wasMediaReplaced,
    );
  });

  for (final layout in _layouts) {
    test('slides from one layout can share a document: $layout', () {
      final doc = KeyxDocument.open(_fixture);
      final theme = doc.presentation.theme;
      expect(theme, isNotNull);
      doc.presentation.slides = [
        ...doc.presentation.slides,
        for (var i = 0; i < 2; i++) slideFromLayout(theme!, layout),
      ];
      validateDocument(doc);
    });
  }
}
