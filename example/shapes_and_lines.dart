// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// src/creator_studio_doc_format/examples/shapes_and_lines.py.

/// Builds a presentation with shapes, a connection line, and shared
/// decoration.
///
/// ```sh
/// dart run example/shapes_and_lines.dart [output]
/// ```
///
/// `Shape` and `ConnectionLine` are the canvas objects you build by hand,
/// unlike `Image`, `Movie`, `Table`, and `Chart`, which wrap external content
/// or structured data.
///
/// A `BezierPath` carries only the outline, so position, size, rotation, and
/// flip all come from the owner's `Geometry`. To reuse a path at another size
/// or angle, change the `Geometry` and leave the path as is.
library;

import 'dart:math' as math;

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';

import 'src/support.dart';

final _rgbaAccent = RGBA(red: 0.58, green: 0.47, blue: 0.96);
final _rgbaBackground = RGBA(red: 0.06, green: 0.05, blue: 0.12);
final _rgbaText = RGBA(red: 1, green: 1, blue: 1);

// Slide 1: canonical shape outlines (unit box, x right, y down).
//
// Ovals and rounded corners use elliptical arcs, written
// `A rx,ry x-rot large-arc sweep x,y`. `"Polygon"` and `"Star"` come from a
// vertex formula.
const _rectangle = 'M 0,0 H 1 V 1 H 0 Z';
const _roundedRectangle =
    'M 0.15,0 H 0.85 A 0.15,0.15 0 0 1 1,0.15 V 0.85 '
    'A 0.15,0.15 0 0 1 0.85,1 H 0.15 A 0.15,0.15 0 0 1 0,0.85 '
    'V 0.15 A 0.15,0.15 0 0 1 0.15,0 Z';
const _oval = 'M 0,0.5 A 0.5,0.5 0 1 1 1,0.5 A 0.5,0.5 0 1 1 0,0.5 Z';

/// Rounds [value] to 3 decimal places, as the vertices of a path are written.
double _round3(double value) => double.parse(value.toStringAsFixed(3));

double _radians(double degrees) => degrees * math.pi / 180;

/// Returns a regular [sides]-gon's vertices, inscribed in the unit box.
List<(double, double)> _polygonPoints(int sides, {double startDeg = -90}) {
  const r = 0.5;
  final step = 2 * math.pi / sides;
  final start = _radians(startDeg);
  return [
    for (var k = 0; k < sides; k++)
      (
        _round3(0.5 + r * math.cos(start + step * k)),
        _round3(0.5 + r * math.sin(start + step * k)),
      ),
  ];
}

/// Returns a [points]-pointed star's vertices, with outer radius 0.5.
///
/// The inner radius is `0.5 * innerRatio`.
List<(double, double)> _starPoints(
  int points, {
  double innerRatio = 0.4,
  double startDeg = -90,
}) {
  const outer = 0.5;
  final inner = 0.5 * innerRatio;
  // Half a step, because vertices alternate outer and inner.
  final step = math.pi / points;
  final start = _radians(startDeg);
  return [
    for (var k = 0; k < points * 2; k++)
      (
        _round3(0.5 + (k.isEven ? outer : inner) * math.cos(start + step * k)),
        _round3(0.5 + (k.isEven ? outer : inner) * math.sin(start + step * k)),
      ),
  ];
}

/// Returns a closed polyline `d` string through [points].
String _polyPath(List<(double, double)> points) {
  final [(hx, hy), ...tail] = points;
  return 'M $hx,$hy ${[for (final (x, y) in tail) 'L $x,$y'].join(' ')} Z';
}

final _hexagonPath = _polyPath(_polygonPoints(6));
final _starPath = _polyPath(_starPoints(5));
final shapes = [
  ('Rectangle', _rectangle),
  ('Rounded Rectangle', _roundedRectangle),
  ('Oval', _oval),
  ('Polygon', _hexagonPath),
  ('Star', _starPath),
];

final _unitSpace = Rect(
  position: Position(x: 0, y: 0),
  size: Size(width: 1, height: 1),
);

/// Returns the centered off-white label used beneath each shape.
Label _label(String name, {double size = 32}) => Label(
  text: Text(string: name),
  paragraphProperties: ParagraphProperties(
    alignment: const Override.value(AlignmentType.center),
    characterProperties: CharacterProperties(
      fontSize: Override.value(size),
      characterFill: Override.value(
        Fill(color: Color(presetIdentifier: 'color_text')),
      ),
    ),
  ),
);

/// Builds a filled shape from a path in a unit box, placed by `Geometry`
/// alone.
Shape _shape(
  String d,
  Position position,
  Size size, {
  String? label,
  String? identifier,
  String fill = 'color_accent',
  Shadow? shadow,
  Reflection? reflection,
  bool titleOnTop = false,
}) => Shape(
  identifier: identifier,
  presetIdentifier: 'shape_base',
  geometry: Geometry(position: position, size: size),
  path: Path(
    bezier: BezierPath(path: d, space: _unitSpace),
  ),
  fill: Fill(color: Color(presetIdentifier: fill)),
  // `shadow` is an `Override`, so a shape without one clears any shadow a
  // preset would give it.
  shadow: shadow == null ? const Override.cleared() : Override.value(shadow),
  reflection: reflection,
  title: label != null ? _label(label) : null,
  titleIsPositionedOnTop: titleOnTop,
);

// `"empty"` draws no outline. The connection line sets its own visible
// stroke.
List<Preset> _presets() => [
  Preset('shape_base', {'stroke': 'empty'}),
  Preset('color_accent', {'rgba': _rgbaAccent.toJson()}),
  Preset('color_text', {'rgba': _rgbaText.toJson()}),
  Preset('fill_slide_bg', {
    'color': {'rgba': _rgbaBackground.toJson()},
  }),
];

/// Builds a row of the shapes, placing each by its slot's `Geometry`.
Slide _basicShapesSlide() {
  const marginX = 80.0;
  final slotWidth = (1920 - 2 * marginX) / shapes.length;
  const box = 170.0; // Rendered shape size, in points.

  final slideObjects = [
    for (final (i, (name, d)) in shapes.indexed)
      SlideObject(
        object: CanvasObject(
          shape: _shape(
            d,
            Position(
              x: marginX + i * slotWidth + slotWidth / 2 - box / 2,
              y: 540 - box / 2,
            ),
            Size(width: box, height: box),
            label: name,
          ),
        ),
      ),
  ];

  return Slide(
    background: Override.value(
      SlideBackground(standard: Fill(presetIdentifier: 'fill_slide_bg')),
    ),
    contents: slideObjects,
  );
}

/// Builds an anchored connection line with an arrowhead, plus shared
/// decoration.
Slide _connectionLineSlide() {
  final boxA = _shape(
    _roundedRectangle,
    Position(x: 280, y: 200),
    Size(width: 340, height: 180),
    label: 'From',
    identifier: 'box_a',
  );
  final boxB = _shape(
    _roundedRectangle,
    Position(x: 1000, y: 200),
    Size(width: 340, height: 180),
    label: 'To',
    identifier: 'box_b',
    fill: 'color_text',
  );
  final connectionLine = ConnectionLine(
    lineType: LineType(straight: true),
    tail: End(
      endPoint: Position(x: 620, y: 290), // `box_a` east edge midpoint.
      anchor: Anchor(objectId: 'box_a', magnet: Magnet(east: true)),
    ),
    head: End(
      endPoint: Position(x: 1000, y: 290), // `box_b` west edge midpoint.
      anchor: Anchor(objectId: 'box_b', magnet: Magnet(west: true)),
      lineEnd: LineEnd.filledArrow,
    ),
    stroke: Stroke(
      line: Line(color: Color(presetIdentifier: 'color_text'), width: 3),
    ),
  );

  final withShadow = _shape(
    _starPath,
    Position(x: 340, y: 560),
    Size(width: 200, height: 200),
    label: 'dropShadow',
    shadow: Shadow(dropShadow: DropShadow(offset: 8, radius: 10, opacity: 0.6)),
  );
  final withReflection = _shape(
    _oval,
    Position(x: 870, y: 560),
    Size(width: 200, height: 200),
    label: 'reflection',
    reflection: Reflection(opacity: 0.4),
    // The reflection extends below the shape, so the label goes above it.
    titleOnTop: true,
  );

  return Slide(
    background: Override.value(
      SlideBackground(standard: Fill(presetIdentifier: 'fill_slide_bg')),
    ),
    contents: [
      SlideObject(object: CanvasObject(shape: boxA)),
      SlideObject(object: CanvasObject(shape: boxB)),
      SlideObject(object: CanvasObject(connectionLine: connectionLine)),
      SlideObject(object: CanvasObject(shape: withShadow)),
      SlideObject(object: CanvasObject(shape: withReflection)),
    ],
  );
}

void main(List<String> args) {
  final parsed = parseArguments(
    args,
    script: 'shapes_and_lines',
    description:
        'Builds a presentation with shapes, a connection line, and shared '
        'decoration.',
    names: ['output'],
    defaults: [defaultOutput('shapes_and_lines.keyx')],
  );
  if (parsed == null) {
    return;
  }
  final [output] = parsed;
  final doc = KeyxDocument(
    Presentation(
      theme: KeynoteTheme(name: 'White', locale: 'en_US'),
      slideSize: Size(width: 1920, height: 1080),
      slides: [_basicShapesSlide(), _connectionLineSlide()],
    ),
    presets: _presets(),
  );
  ensureParent(output);
  doc.save(output, preSaveHooks: [validateDocument]);
  reportSaved(output);
}
