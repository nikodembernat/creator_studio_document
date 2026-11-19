// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// tests/validation/test_string_formats.py.

import 'dart:convert';

import 'package:creator_studio_document/creator_studio_document.dart'
    hide Pattern;
import 'package:creator_studio_document/validation.dart';
import 'package:test/test.dart';

import 'builders.dart';

KeyxDocument _docWithCanvas(CanvasObject canvasObject) => KeyxDocument(
  Presentation(
    slideSize: slideSize(),
    slides: [
      Slide(contents: [SlideObject(object: canvasObject)]),
    ],
  ),
  presets: [],
);

KeyxDocument _docWithTheme(KeynoteTheme theme) => KeyxDocument(
  Presentation(slideSize: slideSize(), slides: [Slide()], theme: theme),
  presets: [],
);

KeyxDocument _docWithNote(Text note) => KeyxDocument(
  Presentation(
    slideSize: slideSize(),
    slides: [Slide(note: note)],
  ),
  presets: [],
);

void _expectValidation(KeyxDocument doc, Pattern? expected) {
  if (expected == null) {
    validateDocument(doc);
  } else {
    expect(() => validateDocument(doc), throwsValueError(expected));
  }
}

KeyxDocument _docWithBezierPath(String path) => _docWithCanvas(
  CanvasObject(
    shape: Shape(
      path: Path(bezier: BezierPath(path: path)),
    ),
  ),
);

KeyxDocument _docWithInstantAlphaPath(String path) {
  final image = Image(
    resource: Resource(indirect: IndirectResource(filename: 'x.png')),
    instantAlphaPath: InstantAlphaPath(path: path),
  );
  final doc = _docWithCanvas(CanvasObject(image: image));
  doc.resources['x.png'] = png;
  return doc;
}

KeyxDocument _docWithCurrencyViaCell(String code) => _docWithCanvas(
  CanvasObject(
    table: Table(
      numberOfColumns: 1,
      numberOfRows: 1,
      content: [
        Row(
          cells: [
            Cell(
              value: '1',
              cellFormat: CellFormat(
                formatType: FormatType.currency,
                currencyFormat: CurrencyFormat(currencyCode: code),
              ),
            ),
          ],
        ),
      ],
    ),
  ),
);

KeyxDocument _docWithCurrencyViaCustomFormat(String code) => _docWithCanvas(
  CanvasObject(
    table: Table(
      numberOfColumns: 1,
      numberOfRows: 1,
      customFormats: [
        CustomFormat(
          identifier: 'cf1',
          formatString: '#,##0',
          formatType: CustomFormatType.number,
          numberFormatData: NumberFormatData(currencyCode: code),
        ),
      ],
    ),
  ),
);

KeyxDocument _docWithHyperlink(Hyperlink link) => _docWithNote(
  Text(
    paragraphs: [
      Paragraph(
        contents: [
          Constituent(
            hyperlink: HyperlinkField(
              target: link,
              run: TextRun(string: 'click me'),
            ),
          ),
        ],
      ),
    ],
  ),
);

KeyxDocument _docWithBase64Image(String b64) => _docWithCanvas(
  CanvasObject(
    image: Image(
      resource: Resource(
        base64Encoded: Base64EncodedResource(string: b64, filename: 'i.png'),
      ),
    ),
  ),
);

// Python's `base64.encodebytes`: lines of 76 characters, each ending in a
// newline.
String _encodebytes(List<int> data) {
  final text = base64Encode(data);
  final lines = [
    for (var i = 0; i < text.length; i += 76)
      text.substring(i, i + 76 > text.length ? text.length : i + 76),
  ];
  return '${lines.join('\n')}\n';
}

void main() {
  for (final (id, makeDoc, expected)
      in <(String, KeyxDocument Function(), Pattern?)>[
        ('bezier-valid', () => _docWithBezierPath('M 0 0 L 10 10 Z'), null),
        (
          'bezier-malformed',
          () => _docWithBezierPath('not a path'),
          "'not a path' isn't SVG path data",
        ),
        ('bezier-empty', () => _docWithBezierPath(''), 'is empty or blank'),
        (
          'bezier-no-command-letter',
          () => _docWithBezierPath('1,2,3'),
          "'1,2,3' isn't SVG path data",
        ),
        (
          'alpha-malformed',
          () => _docWithInstantAlphaPath('!!!'),
          "`InstantAlphaPath.path` '!!!' isn't SVG path data (at "
              'slides[0].contents[0].object.image.instant_alpha_path.path). Use '
              "the syntax of an SVG `<path>` element's `d` attribute.",
        ),
      ]) {
    test('SVG path format: $id (test_svg_path_format[$id])', () {
      _expectValidation(makeDoc(), expected);
    });
  }

  for (final (id, makeDoc, expected)
      in <(String, KeyxDocument Function(), Pattern?)>[
        ('currency-format-valid', () => _docWithCurrencyViaCell('USD'), null),
        (
          'currency-format-lowercase',
          () => _docWithCurrencyViaCell('usd'),
          "`CurrencyFormat.currency_code` 'usd' isn't three uppercase letters (at "
              'slides[0].contents[0].object.table.content[0].cells[0].cell_format'
              ".currency_format.currency_code). Use a code such as 'USD' or "
              "'EUR'.",
        ),
        (
          'number-format-data-symbol',
          () => _docWithCurrencyViaCustomFormat(r'Us$'),
          r"`NumberFormatData.currency_code` 'Us$' isn't three uppercase letters",
        ),
      ]) {
    test('ISO 4217 format: $id (test_iso4217_format[$id])', () {
      _expectValidation(makeDoc(), expected);
    });
  }

  for (final (id, locale, expected) in <(String, String, Pattern?)>[
    ('bcp47-simple', 'en_US', null),
    ('icu-extension', 'en@calendar=buddhist;numbers=thai', null),
    (
      'space-and-bang',
      'en US!',
      "`KeynoteTheme.locale` 'en US!' isn't a locale identifier (at "
          "theme.locale). Use a value such as 'en_US'.",
    ),
    ('empty', '', "`KeynoteTheme.locale` '' isn't a locale identifier"),
    ('dot-only', '.', "`KeynoteTheme.locale` '.' isn't a locale identifier"),
    (
      'semicolons-only',
      ';;;',
      "`KeynoteTheme.locale` ';;;' isn't a locale identifier",
    ),
  ]) {
    test('locale format: $id (test_locale_format[$id])', () {
      _expectValidation(_docWithTheme(KeynoteTheme(locale: locale)), expected);
    });
  }

  const linkPath = 'slides[0].note.paragraphs[0].contents[0].hyperlink.target';
  for (final (id, makeLink, expected)
      in <(String, Hyperlink Function(), Pattern?)>[
        ('https-valid', () => Hyperlink(url: 'https://example.com'), null),
        (
          'mailto-valid',
          () => Hyperlink(url: 'mailto:someone@example.com'),
          null,
        ),
        ('scheme-less-relative-ok', () => Hyperlink(url: 'example.com'), null),
        ('bookmark-ok', () => Hyperlink(url: '#bookmark'), null),
        ('sectionid-ok', () => Hyperlink(url: '?sectionid=abc'), null),
        (
          'file-scheme-belongs-in-file-case',
          () => Hyperlink(url: 'file:///tmp/x.pdf'),
          "`Hyperlink.url` 'file:///tmp/x.pdf' has a 'file:' scheme (at "
              '$linkPath.url). Use `Hyperlink.file` instead.',
        ),
        (
          'empty-url',
          () => Hyperlink(url: ''),
          "`Hyperlink.url` '' is empty or blank (at $linkPath.url)",
        ),
        (
          'empty-file',
          () => Hyperlink(file: ''),
          "`Hyperlink.file` '' is empty or blank (at $linkPath.file)",
        ),
        ('scheme-only-ok', () => Hyperlink(url: 'https:'), null),
        (
          'urlparse-crash-wrapped',
          () => Hyperlink(url: 'http://[malformed'),
          "`Hyperlink.url` 'http://[malformed' isn't a URL (at $linkPath.url). "
              'Invalid IPv6 URL.',
        ),
      ]) {
    test('hyperlink format: $id (test_hyperlink_format[$id])', () {
      _expectValidation(_docWithHyperlink(makeLink()), expected);
    });
  }

  final pngData = [...png, ...utf8.encode('HelloWorld')];
  for (final (id, b64, expected) in <(String, String, Pattern?)>[
    ('valid', base64Encode(pngData), null),
    (
      'undecodable',
      '!!!not base64!!!',
      RegExp("`Base64EncodedResource.string` .* isn't valid Base64"),
    ),
    ('empty', '', "`Base64EncodedResource.string` '' is empty or blank"),
    ('valid-len-4', 'QUJD', null),
    (
      'bad-length',
      'QUJDR',
      "`Base64EncodedResource.string` 'QUJDR' isn't valid Base64 (at "
          'slides[0].contents[0].object.image.resource.base64_encoded.string)'
          ". Use letters, digits, '+' and '/', padded with '=' to a multiple "
          'of 4 characters.',
    ),
    ('wrapped', _encodebytes([...png, ...List.filled(200, 0x78)]), null),
    (
      'whitespace-only',
      '   \n\t ',
      RegExp('`Base64EncodedResource.string` .* is empty or blank'),
    ),
  ]) {
    test('Base64 resource format: $id (test_base64_resource_format[$id])', () {
      _expectValidation(_docWithBase64Image(b64), expected);
    });
  }

  test('an empty Base64 resource filename is rejected '
      '(test_base64_resource_filename_empty)', () {
    final image = Image(
      resource: Resource(
        base64Encoded: Base64EncodedResource(
          string: base64Encode(png),
          filename: '',
        ),
      ),
    );
    expect(
      () => validateDocument(_docWithCanvas(CanvasObject(image: image))),
      throwsValueError("`Base64EncodedResource.filename` '' is empty or blank"),
    );
  });

  test('the message carries the iteration path '
      '(test_validate_error_message_carries_iteration_path)', () {
    expect(
      () => validateDocument(_docWithBezierPath('not-a-path')),
      throwsValueError(RegExp(r'at slides\[0\]\.contents\[0\]')),
    );
  });

  test('a long invalid Base64 string is shortened', () {
    final value = '!' * 50;
    expect(
      () => validateDocument(_docWithBase64Image(value)),
      throwsValueError(
        "`Base64EncodedResource.string` '${'!' * 40}… (50 characters)' "
        "isn't valid Base64",
      ),
    );
  });
}
