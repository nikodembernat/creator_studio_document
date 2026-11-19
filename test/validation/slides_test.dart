// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/test_slides.py.

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';
import 'package:test/test.dart';

import 'builders.dart';

typedef PlaceholderKind = SlideObjectPlaceholderInfoPlaceholderDefinitionKind;

SlideObject definedPlaceholder(PlaceholderKind kind, {bool isVisible = true}) =>
    SlideObject(
      object: CanvasObject(shape: Shape()),
      placeholderInfo: PlaceholderInfo(
        defined: PlaceholderDefinition(kind: kind, isVisible: isVisible),
      ),
    );

SlideObject taggedPlaceholder(String tag) => SlideObject(
  object: CanvasObject(shape: Shape()),
  placeholderInfo: PlaceholderInfo(tagged: tag),
);

KeyxDocument _doc(List<Slide> slides, {List<SlideLayout>? layouts}) =>
    KeyxDocument(
      Presentation(
        slideSize: slideSize(),
        slides: slides.isEmpty ? [Slide()] : slides,
        theme: layouts == null ? null : KeynoteTheme(slideLayouts: layouts),
      ),
      presets: [],
    );

void main() {
  test('a duplicate defined kind on a slide is rejected '
      '(test_validate_detects_duplicate_defined_kind_on_slide)', () {
    expect(
      () => validateDocument(
        _doc([
          Slide(
            contents: [
              definedPlaceholder(PlaceholderKind.title),
              definedPlaceholder(PlaceholderKind.title),
            ],
          ),
        ]),
      ),
      throwsValueError(
        "`PlaceholderDefinition.kind` 'title' is a duplicate (at "
        'slides[0].contents[1].placeholder_info.defined.kind). The first is '
        'at slides[0].contents[0].placeholder_info.defined.kind.',
      ),
    );
  });

  test('a duplicate defined kind on a slide layout is rejected '
      '(test_validate_detects_duplicate_defined_kind_on_slide_layout)', () {
    final layout = SlideLayout(
      name: 'Title',
      contents: [
        definedPlaceholder(PlaceholderKind.body),
        definedPlaceholder(PlaceholderKind.body),
      ],
    );
    expect(
      () => validateDocument(_doc([], layouts: [layout])),
      throwsValueError(
        "`PlaceholderDefinition.kind` 'body' is a duplicate (at "
        'theme.slide_layouts[0].contents[1].placeholder_info.defined.kind)',
      ),
    );
  });

  test('a duplicate defined kind across visibility is rejected '
      '(test_validate_detects_duplicate_defined_kind_across_visibility)', () {
    expect(
      () => validateDocument(
        _doc([
          Slide(
            contents: [
              definedPlaceholder(PlaceholderKind.title, isVisible: false),
              definedPlaceholder(PlaceholderKind.title),
            ],
          ),
        ]),
      ),
      throwsValueError("`PlaceholderDefinition.kind` 'title' is a duplicate"),
    );
  });

  test('one placeholder of each defined kind passes '
      '(test_validate_allows_one_placeholder_of_each_defined_kind)', () {
    validateDocument(
      _doc([
        Slide(
          contents: [
            for (final kind in PlaceholderKind.values) definedPlaceholder(kind),
          ],
        ),
      ]),
    );
  });

  test('the same defined kind on different slides passes '
      '(test_validate_allows_the_same_defined_kind_on_different_slides)', () {
    validateDocument(
      _doc([
        Slide(contents: [definedPlaceholder(PlaceholderKind.title)]),
        Slide(contents: [definedPlaceholder(PlaceholderKind.title)]),
      ]),
    );
  });

  test('duplicate tagged placeholders pass '
      '(test_validate_allows_duplicate_tagged_placeholders)', () {
    validateDocument(
      _doc([
        Slide(
          contents: [taggedPlaceholder('Media'), taggedPlaceholder('Media')],
        ),
      ]),
    );
  });

  test('a tag alongside a defined kind passes '
      '(test_validate_allows_a_tag_alongside_a_defined_kind)', () {
    validateDocument(
      _doc([
        Slide(
          contents: [
            definedPlaceholder(PlaceholderKind.title),
            taggedPlaceholder('Title'),
          ],
        ),
      ]),
    );
  });

  test('a slide layout resolves by identifier '
      '(test_validate_slide_layout_resolves_by_identifier)', () {
    validateDocument(
      _doc(
        [Slide(layout: 'layout-1')],
        layouts: [
          SlideLayout(identifier: 'layout-1', name: 'Title & Subtitle'),
        ],
      ),
    );
  });

  test('a slide layout resolves by name '
      '(test_validate_slide_layout_resolves_by_name)', () {
    validateDocument(
      _doc(
        [Slide(layout: 'Title & Subtitle')],
        layouts: [
          SlideLayout(identifier: 'layout-1', name: 'Title & Subtitle'),
        ],
      ),
    );
  });

  test('a slide layout resolves by name case-insensitively '
      '(test_validate_slide_layout_resolves_by_name_case_insensitively)', () {
    validateDocument(
      _doc(
        [Slide(layout: 'title & subtitle')],
        layouts: [SlideLayout(name: 'Title & Subtitle')],
      ),
    );
  });

  for (final (id, layout, name) in [
    ('turkish-dotless-i', '\u0131stanbul', 'ISTANBUL'),
    ('turkish-dotted-capital-i', '\u0130STANBUL', 'istanbul'),
    ('nfc-vs-nfd', 'caf\u00e9', 'cafe\u0301'),
    ('turkish-dotted-capital-i-with-mark', '\u0130\u0301', '\u00ed'),
    ('dotless-i-with-dot', '\u0131\u0307', 'i'),
    ('dot-reordered-behind-lower-mark', '\u0130\u0323', 'I\u0323'),
    ('ligature', '\ufb01le', 'FILE'),
    ('fullwidth', 'Ｔｉｔｌｅ', 'Title'),
    ('superscript', 'Title²', 'Title2'),
    ('danish-aa', 'aa', 'Å'),
    ('non-ascii-both-sides', 'タイトル', '見出し'),
    ('non-ascii-typo-uncaught', 'タイトレ', 'タイトル'),
  ]) {
    test('a layout name that some locale resolves passes: $id '
        '(test_validate_slide_layout_accepts_names_some_locale_resolves'
        '[$id])', () {
      validateDocument(
        _doc(
          [Slide(layout: layout)],
          layouts: [SlideLayout(name: name)],
        ),
      );
    });
  }

  for (final (id, layout, name) in [
    ('ascii-typo', 'Tilte', 'Title'),
    ('ascii-reference-non-ascii-name', 'Tilte', '見出し'),
    ('non-ascii-reference-ascii-name', '見出し', 'Title'),
  ]) {
    test('a layout name that no locale resolves is rejected: $id '
        '(test_validate_slide_layout_rejects_names_no_locale_resolves'
        '[$id])', () {
      final doc = _doc(
        [Slide(layout: layout)],
        layouts: [SlideLayout(name: name)],
      );
      expect(() => validateDocument(doc), throwsLookupError(layout));
    });
  }

  for (final (id, layout) in [
    ('non-ascii-typo-of-ascii-name', 'Títle'),
    ('invisible-suffix', 'Title\u200b'),
  ]) {
    test('a layout name is rejected against an unrelated non-ASCII name: $id '
        '(test_validate_slide_layout_rejects_against_unrelated_non_ascii_name'
        '[$id])', () {
      final doc = _doc(
        [Slide(layout: layout)],
        layouts: [
          SlideLayout(name: 'Title'),
          SlideLayout(name: '見出し'),
        ],
      );
      expect(
        () => validateDocument(doc),
        throwsLookupError('matches no `SlideLayout`'),
      );
    });
  }

  test('a missing slide layout is rejected '
      '(test_validate_slide_layout_missing_raises)', () {
    final doc = _doc(
      [Slide(layout: 'No Such Layout')],
      layouts: [SlideLayout(name: 'Title & Subtitle')],
    );
    expect(
      () => validateDocument(doc),
      throwsLookupError(
        "`Slide.layout` 'No Such Layout' matches no `SlideLayout` (at "
        "slides[0].layout). The theme's slide layout names are "
        "['Title & Subtitle'].",
      ),
    );
  });

  test('a slide without a layout passes '
      '(test_validate_slide_layout_absent_is_allowed)', () {
    validateDocument(
      _doc([Slide()], layouts: [SlideLayout(name: 'Title & Subtitle')]),
    );
  });

  for (final (id, theme) in [
    ('theme0', null),
    ('theme1', KeynoteTheme(name: 'Gradient')),
  ]) {
    test('a layout is unvalidated without custom layouts: $id '
        '(test_validate_slide_layout_unvalidated_without_custom_layouts'
        '[$id])', () {
      validateDocument(
        KeyxDocument(
          Presentation(
            slideSize: slideSize(),
            slides: [Slide(layout: 'Title & Subtitle')],
            theme: theme,
          ),
          presets: [],
        ),
      );
    });
  }

  test('a layout resolves against any layout, not just the first '
      '(test_validate_slide_layout_resolves_against_any_layout_not_just_the_'
      'first)', () {
    validateDocument(
      _doc(
        [Slide(layout: 'Bullets')],
        layouts: [
          SlideLayout(name: 'Title'),
          SlideLayout(name: 'Bullets'),
        ],
      ),
    );
  });

  test('the slide layout names are listed sorted by code point', () {
    final doc = _doc(
      [Slide(layout: 'zzz')],
      layouts: [
        SlideLayout(name: 'b'),
        SlideLayout(name: 'B'),
        SlideLayout(name: '\u{1F600}'),
        SlideLayout(name: 'Ａ'),
      ],
    );
    expect(
      () => validateDocument(doc),
      // 'B' shares the key of 'b', which came first.
      throwsLookupError("names are ['b', 'Ａ', '😀']."),
    );
  });
}
