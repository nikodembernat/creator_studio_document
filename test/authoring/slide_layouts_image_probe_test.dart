// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python),
// tests/authoring/test_slide_layouts_image_probe.py.

@TestOn('vm')
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:creator_studio_document/authoring.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _fixtures = 'test/fixtures';
const _exports = [
  'image_probe_replaced_wide.keyx',
  'image_probe_replaced_tall.keyx',
];

Image _media(Slide slide) =>
    [for (final o in slide.contents ?? const <SlideObject>[]) ?o.object.image]
        .first;

Size _pixelSize(Uint8List png) {
  final data = ByteData.sublistView(png);
  return Size(
    width: data.getUint32(16).toDouble(),
    height: data.getUint32(20).toDouble(),
  );
}

void _expectGeometry(Geometry? got, Geometry? want) {
  expect(got, isNotNull);
  expect(want, isNotNull);
  // pytest.approx: a relative tolerance of 1e-6 with an absolute floor of
  // 1e-12.
  Matcher approx(double v) => closeTo(v, math.max(v.abs() * 1e-6, 1e-12));
  expect(got!.position.x, approx(want!.position.x));
  expect(got.position.y, approx(want.position.y));
  expect(got.size.width, approx(want.size.width));
  expect(got.size.height, approx(want.size.height));
  expect(got.angle, approx(want.angle));
  expect(got.flipHorizontally, want.flipHorizontally);
}

void main() {
  final docs = {
    for (final name in _exports)
      name: KeyxDocument.open(p.join(_fixtures, name)),
  };

  for (final MapEntry(key: export, value: doc) in docs.entries) {
    for (var index = 0; index < doc.presentation.slides.length; index++) {
      test('replaced image matches Keynote: $export-$index', () {
        final theme = doc.presentation.theme;
        expect(theme, isNotNull);
        final saved = doc.presentation.slides[index];
        expect(saved.layout, isNotNull);
        final want = _media(saved);
        final filename = want.resource.indirect?.filename;
        expect(filename, isNotNull);

        final got = setSlidePlaceholderImage(
          slideFromLayout(theme!, saved.layout!),
          'Media',
          want.resource,
          size: _pixelSize(doc.resources[filename]!),
        );

        _expectGeometry(got.geometry, want.geometry);
        expect(got.mask, isNotNull);
        expect(want.mask, isNotNull);
        _expectGeometry(got.mask!.geometry, want.mask!.geometry);
        expect(got.instantAlphaPath, want.instantAlphaPath);
        expect(got.description, want.description);
        expect(got.wasMediaReplaced, want.wasMediaReplaced);
      });
    }
  }
}
