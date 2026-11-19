// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python),
// tests/authoring/test_slide_layouts.py.

import 'package:creator_studio_document/authoring.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/src/authoring/slide_layouts.dart'
    show firstText, livePlaceholders, placeholderName;
import 'package:test/test.dart';

import 'helpers.dart';

typedef PlaceholderKind = SlideObjectPlaceholderInfoPlaceholderDefinitionKind;

Resource _resource(String filename) =>
    Resource(indirect: IndirectResource(filename: filename));

Slide _mediaSlide(Image image) => Slide(
  contents: [
    SlideObject(
      object: CanvasObject(image: image),
      sourceKind: SourceKind.placeholder,
      placeholderInfo: PlaceholderInfo(tagged: 'Media'),
    ),
  ],
);

SlideObject _textObject(
  String string, {
  required SourceKind? sourceKind,
  PlaceholderKind? kind,
  String? tag,
  bool isVisible = true,
}) {
  PlaceholderInfo? info;
  if (kind != null) {
    info = PlaceholderInfo(
      defined: PlaceholderDefinition(kind: kind, isVisible: isVisible),
    );
  } else if (tag != null) {
    info = PlaceholderInfo(tagged: tag);
  }
  final paragraph = Paragraph(
    contents: [Constituent(run: TextRun(string: string))],
  );
  final textbox = Textbox(text: Text(paragraphs: [paragraph]));
  return SlideObject(
    object: CanvasObject(textbox: textbox),
    sourceKind: sourceKind,
    placeholderInfo: info,
  );
}

SlideObject _imageObject(
  String filename, {
  required SourceKind? sourceKind,
  String? tag,
}) {
  final image = Image(
    resource: Resource(indirect: IndirectResource(filename: filename)),
    isPlaceholder: true,
  );
  return SlideObject(
    object: CanvasObject(image: image),
    sourceKind: sourceKind,
    placeholderInfo: tag != null ? PlaceholderInfo(tagged: tag) : null,
  );
}

KeynoteTheme _theme() {
  final layout = [
    _textObject('Decoration', sourceKind: SourceKind.layout),
    _textObject(
      'Title Text',
      sourceKind: SourceKind.placeholder,
      kind: PlaceholderKind.title,
    ),
    _textObject('Caption', sourceKind: SourceKind.placeholder, tag: 'Caption'),
    _textObject(
      'Body',
      sourceKind: null,
      kind: PlaceholderKind.body,
      isVisible: false,
    ),
  ];
  return KeynoteTheme(
    name: 'Test',
    slideLayouts: [SlideLayout(name: 'Title', contents: layout)],
  );
}

Label _label(String s) => Label(
  text: Text(
    paragraphs: [
      Paragraph(
        contents: [Constituent(run: TextRun(string: s))],
      ),
    ],
  ),
);

Text _firstTextOf(SlideObject obj) {
  final text = firstText(obj);
  expect(text, isNotNull);
  return text!;
}

Image _maskedImage() => Image(
  resource: Resource(indirect: IndirectResource(filename: 'theme.jpg')),
  geometry: Geometry(
    position: Position(x: -3, y: -96),
    size: Size(width: 1926, height: 1271),
  ),
  mask: Mask(
    geometry: Geometry(
      position: Position(x: 0, y: 0),
      size: Size(width: 1920, height: 1080),
    ),
  ),
);

KeynoteTheme _leveledTheme({String? identifier}) {
  Paragraph sample(int? level, String preset) => Paragraph(
    listLevel: level,
    style: ParagraphProperties(presetIdentifier: preset),
    contents: [Constituent(run: TextRun(string: 'Body Level $level'))],
  );

  final body = _textObject(
    '',
    sourceKind: SourceKind.placeholder,
    kind: PlaceholderKind.body,
  );
  _firstTextOf(body).paragraphs = [
    sample(null, 'Subtitle'),
    sample(1, 'Deep'),
    sample(2, 'Deeper'),
  ];
  final layout = SlideLayout(
    name: 'Photo',
    identifier: identifier,
    contents: [body],
  );
  return KeynoteTheme(name: 'T', slideLayouts: [layout]);
}

List<String?> _presets(List<Paragraph> paragraphs) => [
  for (final p in paragraphs) p.style?.presetIdentifier,
];

// The object a slide object holds, through any nested union such as a
// chart's.
Object _payload(SlideObject obj) {
  final payload = obj.object.unionPrimary()?.payload;
  expect(payload, isNotNull);
  var out = payload!;
  while (out is TaggedUnionModel) {
    final inner = out.unionPrimary();
    expect(inner, isNotNull);
    out = inner!.payload;
  }
  return out;
}

String? _identifierOf(Object payload) =>
    (payload as WireModel).wireGet('identifier') as String?;

void main() {
  test('setSlidePlaceholderText writes and returns paragraphs', () {
    final theme = _theme();
    final slide = Slide(contents: theme.slideLayouts![0].contents);
    final title = setSlidePlaceholderText(slide, 'TITLE', ['Hi']);
    expect(paragraphRuns(title), ['Hi']);
    final caption = setSlidePlaceholderText(slide, 'Caption', ['a', 'b']);
    expect(paragraphRuns(caption), ['a', 'b']);
    expect(
      () => setSlidePlaceholderText(slide, 'Nonexistent', null),
      throwsArgumentErrorMatching(
        "No placeholder 'Nonexistent'. Available: .*'TITLE'",
      ),
    );
  });

  test('setSlidePlaceholderText returns the live paragraphs', () {
    final obj = _textObject(
      'Prompt',
      sourceKind: SourceKind.placeholder,
      tag: 'TITLE',
    );
    final slide = Slide(contents: [obj]);
    final paragraphs = setSlidePlaceholderText(slide, 'TITLE', ['a', 'b', 'c']);
    paragraphs[1].listLevel = 1;

    final stored = firstText(livePlaceholders(slide)[0]);
    expect(stored?.paragraphs, isNotNull);
    expect(stored!.paragraphs![1], same(paragraphs[1]));
    expect(stored.paragraphs![1].listLevel, 1);
  });

  test('setSlidePlaceholderImage swaps the named placeholder', () {
    final deco = _imageObject(
      'deco.png',
      sourceKind: SourceKind.layout,
      tag: 'Deco',
    );
    final media = _imageObject(
      'sample.jpg',
      sourceKind: SourceKind.placeholder,
      tag: 'Media',
    );
    final slide = Slide(contents: [deco, media]);
    setSlidePlaceholderImage(slide, 'Media', _resource('p.png'));
    final img = media.object.image;
    expect(img?.resource.indirect, isNotNull);
    expect(img!.resource.indirect!.filename, 'p.png');
    expect(img.wasMediaReplaced, isTrue);

    expect(
      () => setSlidePlaceholderImage(slide, 'Deco', _resource('p.png')),
      throwsArgumentErrorMatching("No placeholder 'Deco'"),
    );
  });

  test('setSlidePlaceholderImage on a text placeholder throws', () {
    final theme = _theme();
    final slide = Slide(contents: theme.slideLayouts![0].contents);
    expect(
      () => setSlidePlaceholderImage(slide, 'TITLE', _resource('p.png')),
      throwsUnsupportedError,
    );
  });

  test('captioned media is an image placeholder, not a text one', () {
    final caption = _label('A caption');
    final image = Image(
      resource: Resource(indirect: IndirectResource(filename: 'photo.jpg')),
      caption: caption,
    );
    final obj = SlideObject(
      object: CanvasObject(image: image),
      sourceKind: SourceKind.placeholder,
      placeholderInfo: PlaceholderInfo(tagged: 'Media'),
    );
    final slide = Slide(contents: [obj]);
    expect(
      () => setSlidePlaceholderText(slide, 'Media', ['x']),
      throwsUnsupportedError,
    );
    setSlidePlaceholderImage(slide, 'Media', _resource('new.png'));
    expect(image.resource.indirect, isNotNull);
    expect(image.resource.indirect!.filename, 'new.png');
  });

  test(
    'setSlidePlaceholderText prefers the body over the caption and title',
    () {
      final shape = Shape(
        title: _label('Title Sample'),
        caption: _label('Caption Sample'),
        text: Text(
          paragraphs: [
            Paragraph(
              contents: [Constituent(run: TextRun(string: 'Body Sample'))],
            ),
          ],
        ),
      );
      final obj = SlideObject(
        object: CanvasObject(shape: shape),
        sourceKind: SourceKind.placeholder,
        placeholderInfo: PlaceholderInfo(
          defined: PlaceholderDefinition(kind: PlaceholderKind.body),
        ),
      );
      final slide = Slide(contents: [obj]);

      expect(paragraphRuns(setSlidePlaceholderText(slide, 'BODY', ['New'])), [
        'New',
      ]);
      expect(shape.title?.text?.paragraphs, isNotNull);
      expect(paragraphRuns(shape.title!.text!.paragraphs!), ['Title Sample']);
      expect(shape.caption?.text?.paragraphs, isNotNull);
      expect(paragraphRuns(shape.caption!.text!.paragraphs!), [
        'Caption Sample',
      ]);
    },
  );

  test('setSlidePlaceholderText ignores a stale primary case', () {
    final paragraph = Paragraph(
      contents: [Constituent(run: TextRun(string: 'Fill me'))],
    );
    final canvas = CanvasObject.unionOf(
      'image',
      image: Image(
        resource: Resource(indirect: IndirectResource(filename: 'photo.jpg')),
      ),
      textbox: Textbox(text: Text(paragraphs: [paragraph])),
    )..image = null;
    final obj = SlideObject(
      object: canvas,
      sourceKind: SourceKind.placeholder,
      placeholderInfo: PlaceholderInfo(tagged: 'Shared'),
    );
    final slide = Slide(contents: [obj]);
    expect(canvas.unionPrimaryName(), 'textbox');
    expect(setSlidePlaceholderText(slide, 'Shared', ['Fill me']), isNotEmpty);
  });

  test('a setter resolves by kind when a name is shared', () {
    for (final contents in [
      [
        _imageObject(
          'photo.jpg',
          sourceKind: SourceKind.placeholder,
          tag: 'Shared',
        ),
        _textObject(
          'Fill me',
          sourceKind: SourceKind.placeholder,
          tag: 'Shared',
        ),
      ],
      [
        _textObject(
          'Fill me',
          sourceKind: SourceKind.placeholder,
          tag: 'Shared',
        ),
        _imageObject(
          'photo.jpg',
          sourceKind: SourceKind.placeholder,
          tag: 'Shared',
        ),
      ],
    ]) {
      final slide = Slide(contents: contents);
      expect(
        paragraphRuns(setSlidePlaceholderText(slide, 'Shared', ['Fill me'])),
        ['Fill me'],
      );
      final image = setSlidePlaceholderImage(
        slide,
        'Shared',
        _resource('p.png'),
      );
      expect(image.resource.indirect, isNotNull);
      expect(image.resource.indirect!.filename, 'p.png');
    }
  });

  test('summarizeSlideLayouts lists the layouts and names', () {
    expect(summarizeSlideLayouts(_theme()), {
      'Title': [
        const LayoutPlaceholderSummary(
          name: 'TITLE',
          objectCase: 'textbox',
          prompt: 'Title Text',
          tag: null,
        ),
        const LayoutPlaceholderSummary(
          name: 'Caption',
          objectCase: 'textbox',
          prompt: 'Caption',
          tag: 'Caption',
        ),
      ],
    });
  });

  test('a summary carries the object case, prompt, and tag', () {
    final layout = [
      _textObject(
        'Type a quote here.',
        sourceKind: SourceKind.placeholder,
        tag: 'Text',
      ),
      _imageObject(
        'sample.jpg',
        sourceKind: SourceKind.placeholder,
        tag: 'Media',
      ),
    ];
    final theme = KeynoteTheme(
      name: 'T',
      slideLayouts: [SlideLayout(name: 'Quote', contents: layout)],
    );
    expect(summarizeSlideLayouts(theme), {
      'Quote': [
        const LayoutPlaceholderSummary(
          name: 'Text',
          objectCase: 'textbox',
          prompt: 'Type a quote here.',
          tag: 'Text',
        ),
        const LayoutPlaceholderSummary(
          name: 'Media',
          objectCase: 'image',
          prompt: null,
          tag: 'Media',
        ),
      ],
    });
  });

  test('an empty theme has no layouts', () {
    expect(summarizeSlideLayouts(KeynoteTheme(name: 'Empty')), isEmpty);
  });

  test('slideFromLayout copies the placeholders and clears them', () {
    final slide = slideFromLayout(_theme(), 'Title');

    expect(slide.layout, 'Title');
    for (final name in ['TITLE', 'Caption']) {
      expect(
        paragraphRuns(setSlidePlaceholderText(slide, name, null)),
        anyOf(isEmpty, [null]),
      );
    }
  });

  test('slideFromLayout empties hidden title and body definitions', () {
    final layout = [
      _textObject(
        'Body Level One',
        sourceKind: null,
        kind: PlaceholderKind.body,
        isVisible: false,
      ),
    ];
    final theme = KeynoteTheme(
      name: 'T',
      slideLayouts: [SlideLayout(name: 'L', contents: layout)],
    );

    final slide = slideFromLayout(theme, 'L');
    expect(slide.contents, isNotNull);
    final text = firstText(slide.contents![0]);
    expect(text?.paragraphs, isNotNull);
    expect(text!.paragraphs, hasLength(1));
    expect(text.paragraphs![0].contents ?? const <Constituent>[], isEmpty);
  });

  test('slideFromLayout resets wasMediaReplaced', () {
    final obj = _imageObject(
      'sample.jpg',
      sourceKind: SourceKind.placeholder,
      tag: 'Media',
    );
    obj.object.image!.wasMediaReplaced = true;
    final theme = KeynoteTheme(
      name: 'T',
      slideLayouts: [
        SlideLayout(name: 'L', contents: [obj]),
      ],
    );

    final made = slideFromLayout(theme, 'L').contents![0];
    expect(made.object.image, isNotNull);
    expect(made.object.image!.wasMediaReplaced, isFalse);

    final unset = _imageObject(
      's.jpg',
      sourceKind: SourceKind.placeholder,
      tag: 'Media',
    );
    final theme2 = KeynoteTheme(
      name: 'T',
      slideLayouts: [
        SlideLayout(name: 'L', contents: [unset]),
      ],
    );
    final got = slideFromLayout(theme2, 'L').contents![0];
    expect(got.object.image, isNotNull);
    expect(
      got.object.image!.toJson().containsKey('was_media_replaced'),
      isFalse,
    );
  });

  test('slideFromLayout keeps a layout object wasMediaReplaced when '
      'layering', () {
    final deco = _imageObject(
      'deco.png',
      sourceKind: SourceKind.layout,
      tag: 'Deco',
    );
    deco.object.image!.wasMediaReplaced = true;
    final theme = KeynoteTheme(
      name: 'T',
      slideLayouts: [
        SlideLayout(
          name: 'L',
          contents: [deco],
          slideObjectsLayerWithLayout: true,
        ),
      ],
    );

    final made = slideFromLayout(theme, 'L').contents![0];
    expect(made.object.image, isNotNull);
    expect(made.object.image!.wasMediaReplaced, isTrue);
  });

  test('slideFromLayout carries hidden definitions except the object', () {
    final layout = [
      _textObject(
        'Title',
        sourceKind: SourceKind.placeholder,
        kind: PlaceholderKind.title,
      ),
      _textObject(
        'Body',
        sourceKind: null,
        kind: PlaceholderKind.body,
        isVisible: false,
      ),
      _textObject(
        'Slide number',
        sourceKind: null,
        kind: PlaceholderKind.slideNumber,
        isVisible: false,
      ),
      _textObject(
        'Object',
        sourceKind: null,
        kind: PlaceholderKind.object,
        isVisible: false,
      ),
    ];
    final theme = KeynoteTheme(
      name: 'T',
      slideLayouts: [SlideLayout(name: 'L', contents: layout)],
    );

    final slide = slideFromLayout(theme, 'L');

    expect(slide.contents, isNotNull);
    expect(
      [for (final o in slide.contents!) (placeholderName(o), o.sourceKind)],
      [
        ('TITLE', SourceKind.placeholder),
        ('BODY', null),
        ('SLIDE_NUMBER', null),
      ],
    );
  });

  test('slideFromLayout drops the instructional text', () {
    final obj = _textObject(
      'Prompt',
      sourceKind: SourceKind.placeholder,
      tag: 'Text',
    )..instructionalText = 'Presentation Title';
    final theme = KeynoteTheme(
      name: 'T',
      slideLayouts: [
        SlideLayout(name: 'L', contents: [obj]),
      ],
    );

    final slide = slideFromLayout(theme, 'L');

    expect(slide.contents, isNotNull);
    expect(slide.contents![0].instructionalText, isNull);
    expect(obj.instructionalText, 'Presentation Title');
  });

  test('slideFromLayout clears only the title and body prompts', () {
    final accent = CharacterProperties(
      characterFill: Override.value(
        Fill(color: Color(rgba: RGBA(red: 0, green: 0, blue: 1))),
      ),
    );
    final nav = Paragraph(
      contents: [
        Constituent(
          run: TextRun(string: 'Why Us', style: accent),
        ),
        Constituent(run: TextRun(string: '\tGoals')),
      ],
    );
    final tagged = SlideObject(
      object: CanvasObject(
        textbox: Textbox(text: Text(paragraphs: [nav])),
      ),
      sourceKind: SourceKind.placeholder,
      placeholderInfo: PlaceholderInfo(tagged: 'Text-4'),
    );
    final layout = [
      _textObject(
        'Title Text',
        sourceKind: SourceKind.placeholder,
        kind: PlaceholderKind.title,
      ),
      _textObject(
        'Body Level One',
        sourceKind: SourceKind.placeholder,
        kind: PlaceholderKind.body,
      ),
      tagged,
    ];
    final theme = KeynoteTheme(
      name: 'T',
      slideLayouts: [SlideLayout(name: 'L', contents: layout)],
    );

    final slide = slideFromLayout(theme, 'L');

    expect(
      paragraphRuns(setSlidePlaceholderText(slide, 'TITLE', null)),
      anyOf(isEmpty, [null]),
    );
    expect(
      paragraphRuns(setSlidePlaceholderText(slide, 'BODY', null)),
      anyOf(isEmpty, [null]),
    );
    final kept = livePlaceholders(slide)[2];
    final text = firstText(kept);
    expect(text?.paragraphs, isNotNull);
    final contents = text!.paragraphs![0].contents;
    expect(contents, isNotNull);
    expect(
      [
        for (final c in contents!)
          if (c.run case final run?) run.string,
      ],
      ['Why Us', '\tGoals'],
    );
    expect(contents[0].run?.style, accent);
    expect(contents[1].run, isNotNull);
    expect(contents[1].run!.style, isNull);
  });

  test('slideFromLayout keeps layout objects only when layering', () {
    final deco = _textObject('Decoration', sourceKind: SourceKind.layout);
    final title = _textObject(
      'Title',
      sourceKind: SourceKind.placeholder,
      kind: PlaceholderKind.title,
    );

    List<SourceKind?> kinds({required bool layers}) {
      final theme = KeynoteTheme(
        name: 'T',
        slideLayouts: [
          SlideLayout(
            name: 'L',
            contents: [deco, title],
            slideObjectsLayerWithLayout: layers,
          ),
        ],
      );
      final contents = slideFromLayout(theme, 'L').contents;
      expect(contents, isNotNull);
      return [for (final o in contents!) o.sourceKind];
    }

    expect(kinds(layers: false), [SourceKind.placeholder]);
    expect(kinds(layers: true), [SourceKind.layout, SourceKind.placeholder]);
  });

  test('slideFromLayout with an unknown layout throws', () {
    expect(
      () => slideFromLayout(_theme(), 'Nonexistent'),
      throwsArgumentErrorMatching("No layout 'Nonexistent'. Available: '"),
    );
  });

  test('slideFromLayout resolves layouts like Keynote', () {
    SlideLayout layout(String name, String prompt, [String? identifier]) {
      final obj = _textObject(
        prompt,
        sourceKind: SourceKind.placeholder,
        tag: 'Note',
      );
      return SlideLayout(name: name, identifier: identifier, contents: [obj]);
    }

    final theme = KeynoteTheme(
      name: 'T',
      slideLayouts: [
        layout('Title', 'first'),
        layout('title', 'second'),
        layout('Other', 'by id', 'Plain'),
        layout('Plain', 'by name'),
      ],
    );

    String? prompt(String layoutName) =>
        summarizeSlideLayouts(theme)[layoutName]![0].prompt;

    expect(summarizeSlideLayouts(theme).keys, ['Title', 'Other']);
    expect(prompt('Title'), 'first');

    List<String?> built(String layoutName) {
      final contents = slideFromLayout(theme, layoutName).contents;
      expect(contents, isNotNull);
      return paragraphRuns(_firstTextOf(contents![0]).paragraphs ?? const []);
    }

    expect(built('title'), ['first']);
    expect(built('Plain'), ['by id']);
  });

  test('setSlidePlaceholderText writes lines and clears', () {
    final obj = _textObject(
      'Prompt',
      sourceKind: SourceKind.placeholder,
      tag: 'Body',
    );
    final slide = Slide(contents: [obj]);

    expect(
      paragraphRuns(setSlidePlaceholderText(slide, 'Body', ['One', 'Two'])),
      ['One', 'Two'],
    );

    final cleared = setSlidePlaceholderText(slide, 'Body', null);
    expect(cleared, hasLength(1));
    expect(cleared[0].contents ?? const <Constituent>[], isEmpty);
  });

  // Upstream takes a `str` as one paragraph; the port takes a one-line list.
  test('setSlidePlaceholderText takes one line as one paragraph', () {
    final obj = _textObject(
      'Prompt',
      sourceKind: SourceKind.placeholder,
      tag: 'Body',
    );
    final slide = Slide(contents: [obj]);

    expect(paragraphRuns(setSlidePlaceholderText(slide, 'Body', ['a\nb'])), [
      'a\nb',
    ]);
    expect(paragraphRuns(setSlidePlaceholderText(slide, 'Body', [''])), ['']);
  });

  test('setSlidePlaceholderText clears on an empty list', () {
    final obj = _textObject(
      'Prompt',
      sourceKind: SourceKind.placeholder,
      tag: 'Body',
    );
    final slide = Slide(contents: [obj]);
    final cleared = setSlidePlaceholderText(slide, 'Body', []);
    expect(cleared, setSlidePlaceholderText(slide, 'Body', null));
    expect(cleared, hasLength(1));
    expect(cleared[0].contents ?? const <Constituent>[], isEmpty);
  });

  test('slideFromLayout, then a setter, keeps the run style', () {
    final style = CharacterProperties(
      characterFill: Override.value(
        Fill(color: Color(rgba: RGBA(red: 1, green: 0, blue: 0))),
      ),
    );
    final run = TextRun(string: 'Prompt', style: style);
    final textbox = Textbox(
      text: Text(
        paragraphs: [
          Paragraph(contents: [Constituent(run: run)]),
        ],
      ),
    );
    final obj = SlideObject(
      object: CanvasObject(textbox: textbox),
      sourceKind: SourceKind.placeholder,
      placeholderInfo: PlaceholderInfo(tagged: 'Title'),
    );
    final theme = KeynoteTheme(
      name: 'T',
      slideLayouts: [
        SlideLayout(name: 'L', contents: [obj]),
      ],
    );

    final slide = slideFromLayout(theme, 'L');
    final paragraphs = setSlidePlaceholderText(slide, 'Title', ['Hello']);
    expect(paragraphRuns(paragraphs), ['Hello']);
    final contents = paragraphs[0].contents;
    expect(contents?[0].run, isNotNull);
    final filledStyle = contents![0].run!.style;
    expect(filledStyle, isNotNull);
    expect(filledStyle, style);
  });

  test('setSlidePlaceholderText on a textless placeholder throws', () {
    final obj = SlideObject(
      object: CanvasObject(shape: Shape()),
      sourceKind: SourceKind.placeholder,
      placeholderInfo: PlaceholderInfo(tagged: 'Empty'),
    );
    final slide = Slide(contents: [obj]);
    expect(
      () => setSlidePlaceholderText(slide, 'Empty', ['x']),
      throwsUnsupportedError,
    );
  });

  test('a captioned image summarizes with no prompt', () {
    final image = Image(
      resource: Resource(indirect: IndirectResource(filename: 'p.jpg')),
      caption: _label('Cap'),
      isPlaceholder: true,
    );
    final obj = SlideObject(
      object: CanvasObject(image: image),
      sourceKind: SourceKind.placeholder,
      placeholderInfo: PlaceholderInfo(tagged: 'Media'),
    );
    final theme = KeynoteTheme(
      name: 'T',
      slideLayouts: [
        SlideLayout(name: 'L', contents: [obj]),
      ],
    );
    expect(summarizeSlideLayouts(theme), {
      'L': [
        const LayoutPlaceholderSummary(
          name: 'Media',
          objectCase: 'image',
          prompt: null,
          tag: 'Media',
        ),
      ],
    });
  });

  test('summarizeSlideLayouts collapses same-named placeholders of one '
      'kind', () {
    final layout = [
      _textObject('First', sourceKind: SourceKind.placeholder, tag: 'Text'),
      _textObject('Second', sourceKind: SourceKind.placeholder, tag: 'Text'),
      _imageObject('a.jpg', sourceKind: SourceKind.placeholder, tag: 'Both'),
      _textObject('Body', sourceKind: SourceKind.placeholder, tag: 'Both'),
    ];
    final theme = KeynoteTheme(
      name: 'T',
      slideLayouts: [SlideLayout(name: 'L', contents: layout)],
    );
    expect(summarizeSlideLayouts(theme), {
      'L': [
        const LayoutPlaceholderSummary(
          name: 'Text',
          objectCase: 'textbox',
          prompt: 'First',
          tag: 'Text',
        ),
        const LayoutPlaceholderSummary(
          name: 'Both',
          objectCase: 'image',
          prompt: null,
          tag: 'Both',
        ),
        const LayoutPlaceholderSummary(
          name: 'Both',
          objectCase: 'textbox',
          prompt: 'Body',
          tag: 'Both',
        ),
      ],
    });
  });

  test("setSlidePlaceholderText doesn't alias the run style across lines", () {
    final run = TextRun(string: 'P', style: CharacterProperties());
    final textbox = Textbox(
      text: Text(
        paragraphs: [
          Paragraph(contents: [Constituent(run: run)]),
        ],
      ),
    );
    final obj = SlideObject(
      object: CanvasObject(textbox: textbox),
      sourceKind: SourceKind.placeholder,
      placeholderInfo: PlaceholderInfo(tagged: 'Body'),
    );
    final slide = Slide(contents: [obj]);

    final paragraphs = setSlidePlaceholderText(slide, 'Body', ['One', 'Two']);
    final c0 = paragraphs[0].contents;
    final c1 = paragraphs[1].contents;
    expect(c0, isNotNull);
    expect(c1, isNotNull);
    final r0 = c0![0].run;
    final r1 = c1![0].run;
    expect(r0, isNotNull);
    expect(r1, isNotNull);
    expect(r0!.style, isNot(same(r1!.style)));
    expect(r0.style, r1.style);
  });

  test('setSlidePlaceholderImage swaps the resource and flags', () {
    final image = Image(
      resource: Resource(
        indirect: IndirectResource(
          filename: 'theme_sample.jpg',
          identifier: 'stale-id',
        ),
      ),
    );
    final resource = _resource('myphoto.png');

    final returned = setSlidePlaceholderImage(
      _mediaSlide(image),
      'Media',
      resource,
    );

    expect(returned, same(image));
    expect(image.resource, resource);
    expect(image.wasMediaReplaced, isTrue);
  });

  test('setSlidePlaceholderImage copies the resource', () {
    final resource = Resource(
      indirect: IndirectResource(
        filename: 'sample.jpg',
        identifier: 'data-key',
      ),
    );

    Slide media() => _mediaSlide(Image(resource: _resource('old.png')));

    final a = setSlidePlaceholderImage(media(), 'Media', resource);
    final b = setSlidePlaceholderImage(media(), 'Media', resource);

    expect(a.resource, isNot(same(resource)));
    expect(a.resource, isNot(same(b.resource)));
    expect(a.resource.indirect, isNotNull);
    expect(a.resource.indirect!.identifier, 'data-key');
  });

  test('setSlidePlaceholderImage without a size keeps the geometry', () {
    final image = _maskedImage();
    setSlidePlaceholderImage(_mediaSlide(image), 'Media', _resource('new.png'));

    expect(image.geometry, isNotNull);
    expect(image.geometry!.position.x, -3);
    expect(image.geometry!.position.y, -96);
    expect(image.geometry!.size.width, 1926);
    expect(image.geometry!.size.height, 1271);
  });

  for (final size in [
    Size(width: 0, height: 792),
    Size(width: 1200, height: -792),
  ]) {
    test('setSlidePlaceholderImage rejects the non-positive size $size', () {
      final image = _maskedImage();
      final before = image.deepCopy();

      expect(
        () => setSlidePlaceholderImage(
          _mediaSlide(image),
          'Media',
          _resource('new.png'),
          size: size,
        ),
        throwsArgumentErrorMatching('`size`'),
      );

      expect(image, before);
    });
  }

  test('setSlidePlaceholderImage drops the instant alpha', () {
    final image = Image(
      resource: _resource('theme.png'),
      instantAlphaPath: InstantAlphaPath(path: 'M 0,0 L 1,0 L 1,1 Z'),
    );

    setSlidePlaceholderImage(_mediaSlide(image), 'Media', _resource('new.png'));

    expect(image.instantAlphaPath, isNull);
  });

  test('list levels clone the slide paragraph, not the layout sample', () {
    final slide = slideFromLayout(_leveledTheme(), 'Photo');
    final paragraphs = setSlidePlaceholderText(
      slide,
      'BODY',
      ['a', 'b'],
      listLevels: [0, 1],
    );

    expect([for (final p in paragraphs) p.listLevel], [null, 1]);
    expect(_presets(paragraphs), ['Subtitle', 'Subtitle']);
  });

  test("list levels ignore the slide's existing levels", () {
    final body = _textObject(
      '',
      sourceKind: SourceKind.placeholder,
      kind: PlaceholderKind.body,
    );
    _firstTextOf(body).paragraphs = [
      Paragraph(style: ParagraphProperties(presetIdentifier: 'First')),
      Paragraph(
        listLevel: 2,
        style: ParagraphProperties(presetIdentifier: 'Old'),
      ),
    ];
    final paragraphs = setSlidePlaceholderText(
      Slide(contents: [body]),
      'BODY',
      ['x', 'y'],
      listLevels: [0, 2],
    );

    expect(_presets(paragraphs), ['First', 'First']);
    expect([for (final p in paragraphs) p.listLevel], [null, 2]);
  });

  test("lines don't repeat the template's list start or break", () {
    final theme = _leveledTheme();
    final layoutContents = theme.slideLayouts![0].contents;
    expect(layoutContents, isNotNull);
    final samples = _firstTextOf(layoutContents![0]).paragraphs;
    expect(samples, isNotNull);
    samples![0]
      ..listStart = 1
      ..breakType = BreakType.column;
    final slide = slideFromLayout(theme, 'Photo');
    final paragraphs = setSlidePlaceholderText(
      slide,
      'BODY',
      ['a', 'b', 'c'],
      listLevels: [0, 0, 0],
    );

    expect([for (final p in paragraphs) p.listStart], [1, null, null]);
    expect([for (final p in paragraphs) p.breakType], [null, null, null]);
    expect(_presets(paragraphs), ['Subtitle', 'Subtitle', 'Subtitle']);
  });

  test("lines keep the template's writing direction", () {
    final obj = _textObject(
      'Prompt',
      sourceKind: SourceKind.placeholder,
      tag: 'Body',
    );
    final template = _firstTextOf(obj).paragraphs;
    expect(template, isNotNull);
    template![0].writingDirection = WritingDirectionType.rightToLeft;
    final paragraphs = setSlidePlaceholderText(Slide(contents: [obj]), 'Body', [
      'a',
      'b',
    ]);

    expect(
      [for (final p in paragraphs) p.writingDirection],
      [WritingDirectionType.rightToLeft, WritingDirectionType.rightToLeft],
    );
  });

  test('list levels must match the lines', () {
    final slide = slideFromLayout(_leveledTheme(), 'Photo');
    expect(
      () => setSlidePlaceholderText(slide, 'BODY', ['a', 'b'], listLevels: [0]),
      throwsArgumentErrorMatching('listLevels'),
    );
    expect(
      () => setSlidePlaceholderText(slide, 'BODY', ['a'], listLevels: [0, 1]),
      throwsArgumentErrorMatching('listLevels'),
    );
    for (final level in [-1, 9]) {
      expect(
        () =>
            setSlidePlaceholderText(slide, 'BODY', ['a'], listLevels: [level]),
        throwsArgumentErrorMatching('listLevels'),
      );
    }
  });

  test('an unsupported object is an ordinary image placeholder', () {
    final unsupported = _imageObject(
      'unsupported-object.pdf',
      sourceKind: SourceKind.placeholder,
      tag: 'Live Video',
    );
    unsupported.object.image!.isPlaceholder = false;
    final theme = KeynoteTheme(
      name: 'T',
      slideLayouts: [
        SlideLayout(name: 'L', contents: [unsupported]),
      ],
    );
    expect(
      [
        for (final p in summarizeSlideLayouts(theme)['L']!)
          (p.name, p.objectCase),
      ],
      [('Live Video', 'image')],
    );

    final image = setSlidePlaceholderImage(
      Slide(contents: [unsupported]),
      'Live Video',
      _resource('new.png'),
    );
    expect(image.resource, _resource('new.png'));
    expect(image.isPlaceholder, isFalse);
    expect(image.wasMediaReplaced, isTrue);
  });

  test('slideFromLayout renews identifiers and remaps connection anchors', () {
    final line = ConnectionLine(
      tail: End(
        endPoint: Position(x: 0, y: 0),
        anchor: Anchor(objectId: 'a'),
      ),
      head: End(
        endPoint: Position(x: 1, y: 0),
        anchor: Anchor(objectId: 'b'),
      ),
    );
    final layout = SlideLayout(
      name: 'L',
      contents: [
        SlideObject(
          object: CanvasObject(shape: Shape(identifier: 'a')),
        ),
        SlideObject(
          object: CanvasObject(
            chart: Chart(column: ColumnChart(identifier: 'b')),
          ),
        ),
        SlideObject(object: CanvasObject(connectionLine: line)),
      ],
    );

    final slide = slideFromLayout(KeynoteTheme(slideLayouts: [layout]), 'L');

    expect(slide.contents, isNotNull);
    final [a, b, joined] = [for (final o in slide.contents!) _payload(o)];
    final aId = _identifierOf(a);
    final bId = _identifierOf(b);
    expect({aId, bId}.intersection({'a', 'b'}), isEmpty);
    expect(aId, isNot(bId));
    joined as ConnectionLine;
    expect(joined.tail.anchor!.objectId, aId);
    expect(joined.head.anchor!.objectId, bId);
    expect(layout.contents, isNotNull);
    expect(_identifierOf(_payload(layout.contents![0])), 'a');
  });

  test('slideFromLayout renews group children and remaps their anchors', () {
    final line = ConnectionLine(
      tail: End(
        endPoint: Position(x: 0, y: 0),
        anchor: Anchor(objectId: 'a'),
      ),
      head: End(
        endPoint: Position(x: 1, y: 0),
        anchor: Anchor(objectId: 'b'),
      ),
    );
    final group = Group(
      identifier: 'g',
      children: [
        CanvasObject(shape: Shape(identifier: 'a')),
        CanvasObject(shape: Shape(identifier: 'b')),
        CanvasObject(connectionLine: line),
      ],
    );
    final layout = SlideLayout(
      name: 'L',
      contents: [SlideObject(object: CanvasObject(group: group))],
    );

    final slide = slideFromLayout(KeynoteTheme(slideLayouts: [layout]), 'L');

    expect(slide.contents, isNotNull);
    final renewed = _payload(slide.contents![0]) as Group;
    final [a, b, joined] = [
      for (final c in renewed.children) c.unionPrimary()!.payload,
    ];
    expect(
      {
        renewed.identifier,
        _identifierOf(a),
        _identifierOf(b),
      }.intersection({'g', 'a', 'b'}),
      isEmpty,
    );
    joined as ConnectionLine;
    expect(joined.tail.anchor!.objectId, _identifierOf(a));
    expect(joined.head.anchor!.objectId, _identifierOf(b));
  });

  test('slideFromLayout remaps cross-table formula references', () {
    final ref = CellReference(
      placeholder: '{ref0}',
      startRowIdentifier: 'r',
      startColumnIdentifier: 'c',
      tableIdentifier: 'source',
    );
    final source = Table(
      identifier: 'source',
      numberOfColumns: 1,
      numberOfRows: 1,
      columnHeaders: [ColumnHeader(columnIdentifier: 'c')],
      content: [
        Row(
          rowIdentifier: 'r',
          cells: [Cell(value: '1')],
        ),
      ],
    );
    final target = Table(
      identifier: 'target',
      numberOfColumns: 1,
      numberOfRows: 1,
      content: [
        Row(
          cells: [
            Cell(
              value: '1',
              formula: Formula(
                idBased: IdBasedFormula(
                  expression: '={ref0}',
                  references: [ref],
                ),
              ),
            ),
          ],
        ),
      ],
    );
    final layout = SlideLayout(
      name: 'L',
      contents: [
        SlideObject(object: CanvasObject(table: source)),
        SlideObject(object: CanvasObject(table: target)),
      ],
    );

    final slide = slideFromLayout(KeynoteTheme(slideLayouts: [layout]), 'L');

    expect(slide.contents, isNotNull);
    final [renewedSource, renewedTarget] = [
      for (final o in slide.contents!) _payload(o) as Table,
    ];
    expect(renewedSource.identifier, isNot('source'));
    final renewedRef =
        renewedTarget.content![0].cells![0].formula!.idBased!.references![0];
    expect(renewedRef.tableIdentifier, renewedSource.identifier);
  });

  test('slideFromLayout keeps the identifier of a layout-sourced object', () {
    final layout = SlideLayout(
      name: 'L',
      slideObjectsLayerWithLayout: true,
      contents: [
        SlideObject(
          object: CanvasObject(shape: Shape(identifier: 'deco')),
          sourceKind: SourceKind.layout,
        ),
      ],
    );

    final slide = slideFromLayout(KeynoteTheme(slideLayouts: [layout]), 'L');

    expect(slide.contents, isNotNull);
    expect(_identifierOf(_payload(slide.contents![0])), 'deco');
  });

  // Not upstream: the port's hook for deterministic identifiers.
  group('newIdentifier', () {
    test('names every renewed object, in order, and the anchors follow', () {
      final line = ConnectionLine(
        tail: End(anchor: Anchor(objectId: 'a')),
        head: End(anchor: Anchor(objectId: 'b')),
      );
      final layout = SlideLayout(
        name: 'L',
        contents: [
          SlideObject(
            object: CanvasObject(shape: Shape(identifier: 'a')),
          ),
          SlideObject(
            object: CanvasObject(shape: Shape(identifier: 'b')),
          ),
          SlideObject(object: CanvasObject(connectionLine: line)),
        ],
      );

      final slide = slideFromLayout(
        KeynoteTheme(slideLayouts: [layout]),
        'L',
        newIdentifier: sequentialIdentifiers(),
      );

      final [a, b, joined] = [for (final o in slide.contents!) _payload(o)];
      expect(_identifierOf(a), 'ID-1');
      expect(_identifierOf(b), 'ID-2');
      joined as ConnectionLine;
      expect(joined.tail.anchor!.objectId, 'ID-1');
      expect(joined.head.anchor!.objectId, 'ID-2');
    });

    test('defaults to uppercase random UUIDs', () {
      final layout = SlideLayout(
        name: 'L',
        contents: [
          SlideObject(
            object: CanvasObject(shape: Shape(identifier: 'a')),
          ),
          SlideObject(
            object: CanvasObject(shape: Shape(identifier: 'b')),
          ),
        ],
      );
      final theme = KeynoteTheme(slideLayouts: [layout]);
      final ids = [
        for (var i = 0; i < 2; i++)
          for (final o in slideFromLayout(theme, 'L').contents!)
            _identifierOf(_payload(o))!,
      ];
      final uuid4 = RegExp(
        r'^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$',
      );
      expect(ids, everyElement(matches(uuid4)));
      expect(ids.toSet(), hasLength(4));
    });
  });
}
