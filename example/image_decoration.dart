// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// src/creator_studio_doc_format/examples/image_decoration.py.

/// Builds a presentation with every `Image` decoration and a `Shape` with an
/// `ImageFill`.
///
/// ```sh
/// dart run example/image_decoration.dart [output]
/// ```
///
/// `Movie` and `Audio` aren't shown.
library;

import 'dart:io';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';

import 'src/support.dart';

final _rgbaBackground = RGBA(red: 0.90, green: 0.94, blue: 0.98);
final _rgbaInk = RGBA(red: 0.07, green: 0.12, blue: 0.22);
final _rgbaAccent = RGBA(red: 0.10, green: 0.30, blue: 0.60);

/// Returns the slide's colors and background fill as presets, plus a `Shape`
/// base.
///
/// The slide references them through `Color(presetIdentifier: …)` and
/// `Fill(presetIdentifier: …)`, which suit a color that's shared or
/// inherited.
List<Preset> _presets() => [
  Preset('color_ink', {'rgba': _rgbaInk.toJson()}),
  Preset('fill_slide_bg', {
    'color': {'rgba': _rgbaBackground.toJson()},
  }),
  Preset('shape_base', {'stroke': 'empty'}),
];

/// Builds a slide with every decoration field on `Image`, plus `ImageFill`.
Slide _slide() {
  final photo = Resource(indirect: IndirectResource(filename: 'photo.png'));

  // `Mask.geometry` uses slide coordinates, as the image's geometry does.
  // `Mask.path` is drawn in a unit square `space` that maps onto the mask's
  // geometry.
  final tileAGeometry = Geometry(
    position: Position(x: 240, y: 90),
    size: Size(width: 600, height: 396),
    angle: -4,
  );
  final tileA = SlideObject(
    object: CanvasObject(
      image: Image(
        geometry: tileAGeometry,
        resource: photo,
        mask: Mask(
          geometry: tileAGeometry,
          path: Path(
            bezier: BezierPath(
              path:
                  'M 0.05,0 L 0.95,0 '
                  'Q 1,0 1,0.15 L 1,0.85 '
                  'Q 1,1 0.95,1 L 0.05,1 '
                  'Q 0,1 0,0.85 L 0,0.15 '
                  'Q 0,0 0.05,0 Z',
              space: Rect(
                position: Position(x: 0, y: 0),
                size: Size(width: 1, height: 1),
              ),
            ),
          ),
        ),
        shadow: Override.value(
          Shadow(
            dropShadow: DropShadow(
              angle: 270,
              opacity: 0.5,
              color: Color(presetIdentifier: 'color_ink'),
              offset: 6,
              radius: 18,
            ),
          ),
        ),
      ),
    ),
  );

  final tileB = SlideObject(
    object: CanvasObject(
      image: Image(
        geometry: Geometry(
          position: Position(x: 1080, y: 90),
          size: Size(width: 600, height: 396),
        ),
        resource: photo,
        stroke: Stroke(
          frame: Frame(name: Name.portfolioInset, scalePercent: 100),
        ),
        reflection: Reflection(opacity: 0.35, fadeAcceleration: 1.2),
      ),
    ),
  );

  final tileC = SlideObject(
    object: CanvasObject(
      image: Image(
        geometry: Geometry(
          position: Position(x: 240, y: 590),
          size: Size(width: 600, height: 396),
        ),
        resource: photo,
        shadow: Override.value(
          Shadow(
            // A contact shadow lies under the image, so it has no angle.
            contactShadow: ContactShadow(
              opacity: 0.6,
              color: Color(presetIdentifier: 'color_ink'),
              offset: 4,
              radius: 32,
            ),
          ),
        ),
        opacity: 0.9,
      ),
    ),
  );

  final tileD = SlideObject(
    object: CanvasObject(
      shape: Shape(
        presetIdentifier: 'shape_base',
        geometry: Geometry(
          position: Position(x: 1080, y: 590),
          size: Size(width: 600, height: 396),
        ),
        fill: Fill(
          image: ImageFill(
            resource: photo,
            technique: Technique.scaleToFit,
            // The tint paints over the image, so an opaque tint would hide
            // it.
            tintColor: Color(rgba: _rgbaAccent.deepCopy()..alpha = 0.4),
          ),
        ),
        shadow: Override.value(
          Shadow(
            curvedShadow: CurvedShadow(
              angle: 270,
              opacity: 0.55,
              color: Color(presetIdentifier: 'color_ink'),
              offset: 8,
              radius: 24,
              curve: 0.6,
            ),
          ),
        ),
      ),
    ),
  );

  return Slide(
    background: Override.value(
      SlideBackground(standard: Fill(presetIdentifier: 'fill_slide_bg')),
    ),
    contents: [tileA, tileB, tileC, tileD],
  );
}

void main(List<String> args) {
  final parsed = parseArguments(
    args,
    script: 'image_decoration',
    description:
        'Builds a presentation with every `Image` decoration and a `Shape` '
        'with an `ImageFill`.',
    names: ['output'],
    defaults: [defaultOutput('image_decoration.keyx')],
  );
  if (parsed == null) {
    return;
  }
  final [output] = parsed;
  final doc = KeyxDocument(
    Presentation(
      slideSize: Size(width: 1920, height: 1080),
      slides: [_slide()],
    ),
    presets: _presets(),
    resources: {
      'photo.png': File(fixture('photo_placeholder.png')).readAsBytesSync(),
    },
  );
  ensureParent(output);
  doc.save(output, preSaveHooks: [validateDocument]);
  reportSaved(output);
}
