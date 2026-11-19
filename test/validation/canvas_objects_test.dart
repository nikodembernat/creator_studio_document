// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/test_canvas_objects.py.

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/src/validation/canvas_objects.dart';
import 'package:creator_studio_document/validation.dart';
import 'package:test/test.dart';

import 'builders.dart';

KeyxDocument _doc(List<Slide> slides, {KeynoteTheme? theme}) => KeyxDocument(
  Presentation(slideSize: slideSize(), slides: slides, theme: theme),
  presets: [],
);

SlideObject _shape(String identifier, {SourceKind? sourceKind}) => SlideObject(
  object: CanvasObject(shape: Shape(identifier: identifier)),
  sourceKind: sourceKind,
);

SlideObject _line(ConnectionLine line) =>
    SlideObject(object: CanvasObject(connectionLine: line));

ConnectionLine _anchoredLine(String tail, String head) => ConnectionLine(
  tail: End(
    endPoint: Position(x: 0, y: 0),
    anchor: Anchor(objectId: tail),
  ),
  head: End(
    endPoint: Position(x: 100, y: 0),
    anchor: Anchor(objectId: head),
  ),
);

Audio _audio(String identifier) => Audio(
  identifier: identifier,
  resource: Resource(
    base64Encoded: Base64EncodedResource(string: 'AA==', filename: 'a.m4a'),
  ),
  playbackOptions: PlaybackOptions(),
);

void main() {
  test('a duplicate canvas object identifier is rejected '
      '(test_validate_detects_duplicate_canvas_object_identifier)', () {
    final doc = _doc([
      Slide(contents: [_shape('dup'), _shape('dup')]),
    ]);
    expect(
      () => validateDocument(doc),
      throwsValueError(
        "`Shape.identifier` 'dup' is a duplicate (at "
        'slides[0].contents[1].object). The first is at '
        'slides[0].contents[0].object.',
      ),
    );
  });

  test('a duplicate across containers is rejected '
      '(test_validate_detects_duplicate_canvas_object_identifier_across_'
      'containers)', () {
    final doc = _doc([
      Slide(contents: [_shape('dup')]),
      Slide(contents: [_shape('dup')]),
    ]);
    expect(
      () => validateDocument(doc),
      throwsValueError(
        RegExp(r"`Shape\.identifier` 'dup' is a duplicate \(at .*slides\[1\]"),
      ),
    );
  });

  test('a duplicate on a nested union payload is rejected '
      '(test_validate_detects_duplicate_identifier_on_a_nested_union_'
      'payload)', () {
    SlideObject chart() => SlideObject(
      object: CanvasObject(
        chart: Chart(column: ColumnChart(identifier: 'dup')),
      ),
    );
    final doc = _doc([
      Slide(contents: [chart()]),
      Slide(contents: [chart()]),
    ]);
    expect(
      () => validateDocument(doc),
      throwsValueError(
        RegExp(
          r"`ColumnChart\.identifier` 'dup' is a duplicate \(at .*slides\[1\]",
        ),
      ),
    );
  });

  test('a duplicate in a group and its slide is rejected '
      '(test_validate_detects_duplicate_identifier_in_group_and_slide)', () {
    final doc = _doc([
      Slide(
        contents: [
          _shape('dup'),
          SlideObject(
            object: CanvasObject(
              group: Group(
                children: [CanvasObject(shape: Shape(identifier: 'dup'))],
              ),
            ),
          ),
        ],
      ),
    ]);
    expect(
      () => validateDocument(doc),
      throwsValueError(
        "`Shape.identifier` 'dup' is a duplicate (at "
        'slides[0].contents[1].object.group.children[0]). The first is at '
        'slides[0].contents[0].object.',
      ),
    );
  });

  test('a layout-sourced object may share its layout identifier '
      '(test_validate_allows_layout_sourced_object_to_share_its_layout_'
      'identifier)', () {
    final doc = _doc(
      [
        Slide(
          layout: 'L',
          contents: [_shape('from-layout', sourceKind: SourceKind.layout)],
        ),
      ],
      theme: KeynoteTheme(
        slideLayouts: [
          SlideLayout(name: 'L', contents: [_shape('from-layout')]),
        ],
      ),
    );
    validateDocument(doc);
  });

  test('a placeholder-sourced object reusing a layout identifier is rejected '
      '(test_validate_detects_placeholder_sourced_object_reusing_a_layout_'
      'identifier)', () {
    final doc = _doc(
      [
        Slide(
          layout: 'L',
          contents: [_shape('reused', sourceKind: SourceKind.placeholder)],
        ),
      ],
      theme: KeynoteTheme(
        slideLayouts: [
          SlideLayout(name: 'L', contents: [_shape('reused')]),
        ],
      ),
    );
    expect(
      () => validateDocument(doc),
      throwsValueError("`Shape.identifier` 'reused' is a duplicate"),
    );
  });

  test('distinct identifiers across slides pass '
      '(test_validate_allows_distinct_canvas_object_identifiers_across_'
      'slides)', () {
    validateDocument(
      _doc([
        Slide(contents: [_shape('a')]),
        Slide(contents: [_shape('b')]),
      ]),
    );
  });

  // Upstream deletes `identifier` from a `Shape`'s `__dict__`, which a Dart
  // model can't do; a model without the field stands in for it.
  test(
    'registering a model without an identifier field throws '
    '(test_register_canvas_object_raises_on_missing_identifier_attribute)',
    () {
      expect(
        () => registerCanvasObject(Position(x: 0, y: 0), 'path', {}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('identifier'),
          ),
        ),
      );
    },
  );

  test('a connection line anchor resolves within slide contents '
      '(test_validate_connection_line_anchor_resolves_within_slide_'
      'contents)', () {
    validateDocument(
      _doc([
        Slide(
          contents: [
            _shape('shape1'),
            _shape('shape2'),
            _line(_anchoredLine('shape1', 'shape2')),
          ],
        ),
      ]),
    );
  });

  test('a connection line anchor resolves within group children '
      '(test_validate_connection_line_anchor_resolves_within_group_'
      'children)', () {
    final group = Group(
      children: [
        CanvasObject(shape: Shape(identifier: 'shape1')),
        CanvasObject(shape: Shape(identifier: 'shape2')),
        CanvasObject(connectionLine: _anchoredLine('shape1', 'shape2')),
      ],
    );
    validateDocument(
      _doc([
        Slide(
          contents: [SlideObject(object: CanvasObject(group: group))],
        ),
      ]),
    );
  });

  test('an anchor into a sibling group is rejected '
      '(test_validate_connection_line_anchor_missing_in_sibling_group_'
      'raises)', () {
    final group1 = Group(
      children: [CanvasObject(shape: Shape(identifier: 'shape-in-group1'))],
    );
    final line = ConnectionLine(
      tail: End(
        endPoint: Position(x: 0, y: 0),
        anchor: Anchor(objectId: 'shape-in-group1'),
      ),
      head: End(endPoint: Position(x: 100, y: 0)),
    );
    final group2 = Group(children: [CanvasObject(connectionLine: line)]);
    final doc = _doc([
      Slide(
        contents: [
          SlideObject(object: CanvasObject(group: group1)),
          SlideObject(object: CanvasObject(group: group2)),
        ],
      ),
    ]);
    expect(
      () => validateDocument(doc),
      throwsLookupError(
        "`ConnectionLine.End.Anchor.object_id` 'shape-in-group1' matches no "
        'sibling of the line (at '
        'slides[0].contents[1].object.group.children[0].tail.anchor'
        '.object_id)',
      ),
    );
  });

  test(
    'a missing anchor in a slide layout is rejected '
    '(test_validate_connection_line_anchor_missing_in_slide_layout_raises)',
    () {
      final doc = docWithSlideLayout(
        SlideLayout(
          name: 'Layout',
          contents: [
            _shape('shape1'),
            _line(_anchoredLine('shape1', 'no-such-shape')),
          ],
        ),
      );
      expect(() => validateDocument(doc), throwsLookupError('no-such-shape'));
    },
  );

  test(
    'an anchor resolves within a slide layout '
    '(test_validate_connection_line_anchor_resolves_within_slide_layout)',
    () {
      validateDocument(
        docWithSlideLayout(
          SlideLayout(
            name: 'Layout',
            contents: [
              _shape('shape1'),
              _shape('shape2'),
              _line(_anchoredLine('shape1', 'shape2')),
            ],
          ),
        ),
      );
    },
  );

  test('a slide target resolves a forward reference '
      '(test_validate_slide_target_by_identifier_resolves_forward_'
      'reference)', () {
    validateDocument(
      _doc([
        slideWithHyperlink(SlideTarget(byIdentifier: 'later-slide')),
        Slide(identifier: 'later-slide'),
      ]),
    );
  });

  test('a slide target to a missing slide is rejected '
      '(test_validate_slide_target_by_identifier_missing_raises)', () {
    final doc = _doc([
      slideWithHyperlink(SlideTarget(byIdentifier: 'no-such-slide')),
    ]);
    expect(
      () => validateDocument(doc),
      throwsLookupError(
        "`SlideTarget.by_identifier` 'no-such-slide' matches no "
        '`Slide.identifier` (at slides[0].note.paragraphs[0].contents[0]'
        '.hyperlink.target.slide_jump.by_identifier)',
      ),
    );
  });

  test('a duplicate slide identifier is rejected '
      '(test_validate_detects_duplicate_slide_identifier)', () {
    final doc = _doc([Slide(identifier: 'dup'), Slide(identifier: 'dup')]);
    expect(
      () => validateDocument(doc),
      throwsValueError(
        "`Slide.identifier` 'dup' is a duplicate (at slides[1]). The first is "
        'at slides[0].',
      ),
    );
  });

  test('distinct slide identifiers pass '
      '(test_validate_allows_distinct_slide_identifiers)', () {
    validateDocument(_doc([Slide(identifier: 's1'), Slide(identifier: 's2')]));
  });

  test('a duplicate slide layout identifier is rejected '
      '(test_validate_detects_duplicate_slide_layout_identifier)', () {
    final doc = _doc(
      [Slide()],
      theme: KeynoteTheme(
        slideLayouts: [
          SlideLayout(name: 'A', identifier: 'dup'),
          SlideLayout(name: 'B', identifier: 'dup'),
        ],
      ),
    );
    expect(
      () => validateDocument(doc),
      throwsValueError(RegExp(r'`SlideLayout\.identifier` .* is a duplicate')),
    );
  });

  test('distinct slide layout identifiers pass '
      '(test_validate_allows_distinct_slide_layout_identifiers)', () {
    validateDocument(
      _doc(
        [Slide()],
        theme: KeynoteTheme(
          slideLayouts: [
            SlideLayout(name: 'A', identifier: 't1'),
            SlideLayout(name: 'B', identifier: 't2'),
          ],
        ),
      ),
    );
  });

  test('a slide layout and a slide may share an identifier '
      '(test_validate_slide_layout_and_slide_may_share_identifier)', () {
    validateDocument(
      _doc(
        [Slide(identifier: 'shared')],
        theme: KeynoteTheme(
          slideLayouts: [SlideLayout(name: 'A', identifier: 'shared')],
        ),
      ),
    );
  });

  test("a positional slide target isn't checked "
      '(test_validate_slide_target_positional_case_is_not_checked)', () {
    validateDocument(_doc([slideWithHyperlink(SlideTarget(next: true))]));
  });

  test('an end point without an anchor is fine '
      '(test_validate_connection_line_end_point_without_anchor_is_fine)', () {
    final line = ConnectionLine(
      tail: End(endPoint: Position(x: 0, y: 0)),
      head: End(
        endPoint: Position(x: 100, y: 0),
        anchor: Anchor(objectId: 'shape1'),
      ),
    );
    validateDocument(
      _doc([
        Slide(contents: [_shape('shape1'), _line(line)]),
      ]),
    );
  });

  test(
    'an anchored end without an end point is rejected '
    '(test_validate_connection_line_anchored_end_without_end_point_raises)',
    () {
      final line = ConnectionLine(
        tail: End(endPoint: Position(x: 0, y: 0)),
        head: End(anchor: Anchor(objectId: 'shape1')),
      );
      final doc = _doc([
        Slide(contents: [_shape('shape1'), _line(line)]),
      ]);
      expect(
        () => validateDocument(doc),
        throwsValueError(
          '`ConnectionLine.End.end_point` is missing (at '
          'slides[0].contents[1].object.head.end_point)',
        ),
      );
    },
  );

  test("a line anchored to an audio clip isn't checked "
      '(test_validate_connection_line_anchored_to_audio_is_not_checked)', () {
    final line = ConnectionLine(
      tail: End(endPoint: Position(x: 0, y: 0)),
      head: End(
        endPoint: Position(x: 100, y: 0),
        anchor: Anchor(objectId: 'clip'),
      ),
    );
    validateDocument(
      _doc([
        Slide(
          contents: [
            SlideObject(object: CanvasObject(audio: _audio('clip'))),
            _line(line),
          ],
        ),
      ]),
    );
  });

  test('an inline object claims its identifier document-wide', () {
    final slide = Slide(
      contents: [_shape('dup')],
      note: Text(
        paragraphs: [
          Paragraph(
            contents: [
              Constituent(
                inlineObject: CanvasObject(shape: Shape(identifier: 'dup')),
              ),
            ],
          ),
        ],
      ),
    );
    expect(
      () => validateDocument(_doc([slide])),
      throwsValueError(
        "`Shape.identifier` 'dup' is a duplicate (at "
        'slides[0].note.paragraphs[0].contents[0].inline_object). The first '
        'is at slides[0].contents[0].object.',
      ),
    );
  });
}
