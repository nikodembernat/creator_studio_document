// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// Creates slides from a theme's layouts, and fills in their text and image
/// placeholders.
library;

import 'dart:math' as math;

import 'package:creator_studio_document/src/authoring/slide_layout_refs.dart';
import 'package:creator_studio_document/src/core/models.g.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/core/wire.dart';
import 'package:creator_studio_document/src/navigation/navigation.dart';
import 'package:meta/meta.dart';

typedef _PlaceholderKind = SlideObjectPlaceholderInfoPlaceholderDefinitionKind;

const _clearedKinds = {_PlaceholderKind.title, _PlaceholderKind.body};

// Upstream names a predefined placeholder by its enum member's Python name.
String _kindName(_PlaceholderKind kind) => switch (kind) {
  _PlaceholderKind.body => 'BODY',
  _PlaceholderKind.object => 'OBJECT',
  _PlaceholderKind.slideNumber => 'SLIDE_NUMBER',
  _PlaceholderKind.title => 'TITLE',
};

void _setOnlyCase(TaggedUnionModel union, String only, Object? value) {
  final schema = union.wireSchema as UnionSchema<TaggedUnionModel>;
  for (final c in schema.cases) {
    union.wireSet(c.key, c.key == only ? value : null);
  }
}

Paragraph _styledLine(
  Paragraph template,
  String line,
  CharacterProperties? style,
) {
  // Every argument upstream passes counts as set, `None` included.
  final run = TextRun(string: line)..style = style;
  final paragraph = Paragraph(contents: [Constituent(run: run)])
    ..style = template.style
    ..listStyle = template.listStyle
    ..listLevel = template.listLevel
    ..writingDirection = template.writingDirection;
  return paragraph.deepCopy();
}

CharacterProperties? _runStyle(Paragraph paragraph) {
  for (final c in paragraph.contents ?? const <Constituent>[]) {
    if (c.run?.style case final style?) {
      return style;
    }
  }
  return null;
}

List<Paragraph> _writeText(Text text, List<String> lines, [List<int>? levels]) {
  final existing = text.paragraphs;
  if (existing == null || existing.isEmpty) {
    _setOnlyCase(text, 'string', lines.join('\n'));
    return [];
  }
  final List<Paragraph> paragraphs;
  if (lines.isEmpty) {
    paragraphs = [existing[0]..contents = null];
  } else {
    final template = existing[0];
    final style = _runStyle(template);
    paragraphs = [];
    for (var i = 0; i < lines.length; i++) {
      final paragraph = _styledLine(template, lines[i], style);
      if (levels != null) {
        paragraph.listLevel = levels[i] == 0 ? null : levels[i];
      }
      paragraphs.add(paragraph);
    }
    paragraphs[0].listStart = existing[0].listStart;
  }
  _setOnlyCase(text, 'paragraphs', paragraphs);
  return paragraphs;
}

/// Returns the objects of [slide] that are live placeholders, those whose
/// source is [SourceKind.placeholder], in depth-first order.
@internal
List<SlideObject> livePlaceholders(Slide slide) => [
  for (final item in iterateModels(slide))
    if (item.model case final SlideObject obj
        when obj.sourceKind == SourceKind.placeholder)
      obj,
];

/// Returns the name of the placeholder [obj], or `null` if it isn't one.
///
/// A custom placeholder's name is its tag, and a predefined one's is its
/// kind's upstream member name, such as `'TITLE'`.
@internal
String? placeholderName(SlideObject obj) {
  final info = obj.placeholderInfo;
  if (info == null) {
    return null;
  }
  if (info.defined case final defined?) {
    return _kindName(defined.kind);
  }
  return info.tagged;
}

/// Returns the text that a placeholder setter writes into under [root]: the
/// first [Text] that isn't a [Label]'s, else the first [Text], else `null`.
@internal
Text? firstText(WireModel root) {
  Text? first;
  for (final item in iterateModels(root)) {
    final model = item.model;
    if (model is! Text) {
      continue;
    }
    first ??= model;
    final ancestors = item.ancestors;
    if (!(ancestors.isNotEmpty && ancestors.last is Label)) {
      return model;
    }
  }
  return first;
}

String? _placeholderPrompt(SlideObject obj) {
  if (!_accepts(obj, _Want.text)) {
    return null;
  }
  if (obj.instructionalText case final prompt? when prompt.isNotEmpty) {
    return prompt;
  }
  final text = firstText(obj);
  if (text == null) {
    return null;
  }
  for (final paragraph in text.paragraphs ?? const <Paragraph>[]) {
    for (final c in paragraph.contents ?? const <Constituent>[]) {
      if (c.run case final run?) {
        return run.string;
      }
    }
  }
  return text.string;
}

String? _placeholderTag(SlideObject obj) => obj.placeholderInfo?.tagged;

const _mediaCases = {'audio', 'image', 'movie'};

enum _Want() {
  text,
  image,
}

bool _accepts(SlideObject obj, _Want want) {
  final name = obj.object.unionPrimaryName();
  return switch (want) {
    _Want.image => name == 'image',
    _Want.text => !_mediaCases.contains(name),
  };
}

SlideObject _resolvePlaceholder(Slide slide, String name, _Want want) {
  final live = livePlaceholders(slide);
  final matches = [
    for (final o in live)
      if (placeholderName(o) == name) o,
  ];
  if (matches.isEmpty) {
    final available = <String>{
      for (final o in live)
        if (placeholderName(o) case final n? when n.isNotEmpty) n,
    };
    throw ArgumentError.value(
      name,
      'placeholderName',
      'No placeholder ${pyRepr(name)}. '
          'Available: ${available.map(pyRepr).join(', ')}',
    );
  }
  for (final o in matches) {
    if (_accepts(o, want)) {
      return o;
    }
  }
  throw UnsupportedError(
    "Placeholder ${pyRepr(name)} isn't a ${want.name} placeholder",
  );
}

/// Writes [lines] into a text placeholder and returns the paragraphs it
/// wrote.
///
/// Every line takes the placeholder's own paragraph and text style at every
/// level. Some built-in themes style each level of the sample text
/// differently, so a nested line needs that level's style. Set it on the
/// returned paragraph.
///
/// - [slide] is the slide to write into.
/// - [placeholderName] is the text placeholder's name, as
///   [summarizeSlideLayouts] reports it.
/// - [lines] holds one text per paragraph. `null` or `[]` clears the
///   placeholder, and `['']` writes an empty run. A line can hold `\n`, which
///   stays in its paragraph.
/// - [listLevels] holds each line's list level, from 0 for the top level
///   through 8, with one entry per line. A placeholder with text that is a
///   plain string ignores it.
///
/// The returned paragraphs are live, so changing one changes the slide. A
/// placeholder with text that is a plain string has no paragraphs, so the
/// result is `[]` and the function joins the lines with newlines.
///
/// Throws [ArgumentError] if no placeholder named [placeholderName] exists on
/// [slide], or if [listLevels] has a different length than [lines] or a level
/// outside 0 through 8. Throws [UnsupportedError] if [placeholderName] names
/// an image, movie, or audio placeholder, or a text placeholder that has no
/// [Text].
List<Paragraph> setSlidePlaceholderText(
  Slide slide,
  String placeholderName,
  List<String>? lines, {
  List<int>? listLevels,
}) {
  final all = lines ?? const <String>[];
  if (listLevels != null && listLevels.length != all.length) {
    throw ArgumentError.value(
      listLevels,
      'listLevels',
      '`listLevels` has ${listLevels.length} entries for ${all.length} lines',
    );
  }
  if (listLevels != null && listLevels.any((lv) => lv < 0 || lv > 8)) {
    throw ArgumentError.value(
      listLevels,
      'listLevels',
      '`listLevels` must be 0 through 8, not ${pyRepr(listLevels)}',
    );
  }
  final obj = _resolvePlaceholder(slide, placeholderName, _Want.text);
  final text = firstText(obj);
  if (text == null) {
    throw UnsupportedError(
      'Placeholder ${pyRepr(placeholderName)} has no text',
    );
  }
  return _writeText(text, all, listLevels);
}

/// Points an image placeholder at [resource] and returns the image.
///
/// The function doesn't store the image's bytes. An indirect [resource] needs
/// them in the document's resources, and by default the document's `save`
/// throws without them.
///
/// - [slide] is the slide to write into.
/// - [placeholderName] is the image placeholder's name, as
///   [summarizeSlideLayouts] reports it.
/// - [resource] is the image's resource. The image holds a copy of it.
/// - [size] is the width and height of the image [resource] holds. The
///   function then fills the placeholder's mask with the image and centers it
///   there, as Replace Image does in Keynote. Only the aspect ratio matters.
///   `null` keeps the placeholder's geometry, and the image stretches to it.
///
/// The returned image is live, so changing its `geometry` adjusts the crop.
///
/// Throws [ArgumentError] if no placeholder named [placeholderName] exists on
/// [slide], or if [size] has a width or height that isn't positive. Throws
/// [UnsupportedError] if [placeholderName] names a text, movie, or audio
/// placeholder.
Image setSlidePlaceholderImage(
  Slide slide,
  String placeholderName,
  Resource resource, {
  Size? size,
}) {
  if (size != null && !(size.width > 0 && size.height > 0)) {
    throw ArgumentError.value(
      size,
      'size',
      '`size` must be positive, not $size',
    );
  }
  final obj = _resolvePlaceholder(slide, placeholderName, _Want.image);
  final image = obj.object.image;
  if (image == null) {
    throw UnsupportedError(
      'Placeholder ${pyRepr(placeholderName)} has no image',
    );
  }
  image.resource = resource.deepCopy();
  if (size != null) {
    _fillMask(image, size);
  }
  image
    ..instantAlphaPath = null
    ..description = null
    ..wasMediaReplaced = true;
  return image;
}

void _fillMask(Image image, Size size) {
  var mask = image.mask;
  if (mask == null) {
    final geometry = image.geometry;
    if (geometry == null) {
      return;
    }
    mask = image.mask = Mask(geometry: geometry.deepCopy());
  }
  final frame = mask.geometry;
  if (frame == null) {
    return;
  }
  final scale = math.max(
    frame.size.width / size.width,
    frame.size.height / size.height,
  );
  final fitted = Size(width: size.width * scale, height: size.height * scale);
  final geometry = image.geometry ??= Geometry(
    position: Position(x: 0, y: 0),
    size: fitted,
  );
  final (frameW, frameH) = _bounds(frame.size, frame.angle);
  final (imageW, imageH) = _bounds(fitted, geometry.angle);
  geometry
    ..size = fitted
    ..position = Position(
      x: frame.position.x + (frameW - imageW) / 2,
      y: frame.position.y + (frameH - imageH) / 2,
    );
}

// Python's `math.radians` multiplies by `pi / 180`.
const _degToRad = math.pi / 180;

(double, double) _bounds(Size size, double angle) {
  final cos = math.cos(angle * _degToRad).abs();
  final sin = math.sin(angle * _degToRad).abs();
  return (
    size.width * cos + size.height * sin,
    size.width * sin + size.height * cos,
  );
}

/// A read-only summary of a placeholder in a slide layout.
///
/// One summary stands for every placeholder that shares its name and setter.
/// You don't create a summary directly. [summarizeSlideLayouts] returns them.
@immutable
final class const LayoutPlaceholderSummary({
  /// The placeholder's name within its layout, which a setter takes.
  ///
  /// A custom placeholder's name is its tag. Any other placeholder's name is
  /// its kind's upstream member name, such as `'TITLE'`.
  required final String name,

  /// The case the placeholder's canvas object holds.
  ///
  /// A text placeholder holds a case such as `'shape'` or `'textbox'`, and an
  /// image placeholder holds `'image'`.
  required final String objectCase,

  /// The prompt or sample text Keynote shows in the placeholder.
  ///
  /// It's `null` when there's none, as for an image, movie, or audio
  /// placeholder.
  required final String? prompt,

  /// The label the theme's designer gives a custom placeholder.
  ///
  /// It's `null` for a predefined one such as `'TITLE'`.
  required final String? tag,
}) {
  /// Creates a summary.
  this;

  @override
  bool operator ==(Object other) =>
      other is LayoutPlaceholderSummary &&
      other.name == name &&
      other.objectCase == objectCase &&
      other.prompt == prompt &&
      other.tag == tag;

  @override
  int get hashCode => Object.hash(name, objectCase, prompt, tag);

  @override
  String toString() =>
      'LayoutPlaceholderSummary(name: ${pyRepr(name)}, '
      'objectCase: ${pyRepr(objectCase)}, prompt: ${pyRepr(prompt)}, '
      'tag: ${pyRepr(tag)})';
}

String _setterFor(SlideObject obj) {
  if (_accepts(obj, _Want.image)) {
    return 'image';
  }
  if (_accepts(obj, _Want.text)) {
    return 'text';
  }
  return obj.object.unionPrimaryName() ?? '?';
}

/// Returns the placeholders of each slide layout of [theme], keyed by layout
/// name in the theme's order, or `{}` when `theme.slideLayouts` is absent.
///
/// A layout that another layout shadows, because a slide naming it would
/// resolve to the other, is left out.
Map<String, List<LayoutPlaceholderSummary>> summarizeSlideLayouts(
  KeynoteTheme theme,
) {
  final layouts = theme.slideLayouts ?? const <SlideLayout>[];
  final summaries = <String, List<LayoutPlaceholderSummary>>{};
  for (final layout in layouts) {
    if (!identical(resolveSlideLayout(layouts, layout.name), layout)) {
      continue;
    }
    final placeholders = <LayoutPlaceholderSummary>[];
    final seen = <(String, String)>{};
    for (final obj in livePlaceholders(Slide(contents: layout.contents))) {
      final name = placeholderName(obj);
      if (name == null || !seen.add((name, _setterFor(obj)))) {
        continue;
      }
      placeholders.add(
        LayoutPlaceholderSummary(
          name: name,
          objectCase: obj.object.unionPrimaryName() ?? '?',
          prompt: _placeholderPrompt(obj),
          tag: _placeholderTag(obj),
        ),
      );
    }
    summaries[layout.name] = placeholders;
  }
  return summaries;
}

bool _instantiates(SlideObject obj, {required bool layers}) =>
    switch (obj.sourceKind) {
      SourceKind.placeholder => true,
      SourceKind.layout => layers,
      null => switch (obj.placeholderInfo?.defined) {
        null => true,
        final defined => defined.kind != _PlaceholderKind.object,
      },
      SourceKind.user => false,
    };

void _renewIdentifiers(
  List<SlideObject> objs,
  String Function() newIdentifier,
) {
  final renamed = <String, String>{};
  final anchors = <Anchor>[];
  final cellRefs = <CellReference>[];
  final refs = <Reference>[];
  for (final obj in objs) {
    for (final item in iterateModels(obj)) {
      switch (item.model) {
        case final Anchor anchor:
          anchors.add(anchor);
        case final CellReference ref:
          cellRefs.add(ref);
        case final Reference ref:
          refs.add(ref);
        case final CanvasObject canvasObject:
          _renew(canvasObject, renamed, newIdentifier);
      }
    }
  }
  for (final anchor in anchors) {
    if (renamed[anchor.objectId] case final id?) {
      anchor.objectId = id;
    }
  }
  for (final ref in cellRefs) {
    if (renamed[ref.tableIdentifier] case final id?) {
      ref.tableIdentifier = id;
    }
  }
  for (final ref in refs) {
    if (renamed[ref.tableIdentifier] case final id?) {
      ref.tableIdentifier = id;
    }
  }
}

// Gives the object that [canvasObject] holds, through any nested union such
// as a chart's, a new identifier.
void _renew(
  CanvasObject canvasObject,
  Map<String, String> renamed,
  String Function() newIdentifier,
) {
  Object? payload = canvasObject.unionCaseEntries().firstOrNull?.$2;
  while (payload is TaggedUnionModel) {
    final inner = payload.unionCaseEntries().firstOrNull;
    if (inner == null) {
      break;
    }
    payload = inner.$2;
  }
  if (payload is! ObjectModel) {
    return;
  }
  final schema = payload.wireSchema as ObjectSchema<ObjectModel>;
  if (schema.field('identifier') == null) {
    return;
  }
  if (payload.wireGet('identifier') case final String old) {
    final id = renamed[old] = newIdentifier();
    payload.wireSet('identifier', id);
  }
}

final math.Random _random = math.Random.secure();

// `str(uuid.uuid4()).upper()`.
String _uuid4() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')]
      .join()
      .toUpperCase();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Returns a new slide made from a layout of [theme], as Keynote creates one.
///
/// [layoutName] is the layout's identifier or name, such as a key of the
/// result of [summarizeSlideLayouts]. The slide's `layout` is [layoutName] as
/// given.
///
/// Only the slide's `'TITLE'` and `'BODY'` placeholders start empty. A custom
/// placeholder keeps its sample text, and an image placeholder keeps its
/// sample photo until a setter replaces it. Add the slide to
/// `presentation.slides` to put it in a document.
///
/// Every object the slide copies from a placeholder gets a new identifier, so
/// slides from one layout can share a document, and the connection lines and
/// formulas that refer to it follow. [newIdentifier] makes each new
/// identifier; it defaults to an uppercase random UUID, as Keynote writes.
///
/// Throws [ArgumentError] if [layoutName] matches no layout identifier or
/// layout name in [theme].
Slide slideFromLayout(
  KeynoteTheme theme,
  String layoutName, {
  String Function()? newIdentifier,
}) {
  final layouts = theme.slideLayouts ?? const <SlideLayout>[];
  final layout = resolveSlideLayout(layouts, layoutName);
  if (layout == null) {
    final available = [
      for (final l in layouts)
        if (l.name.isNotEmpty) l.name,
    ];
    throw ArgumentError.value(
      layoutName,
      'layoutName',
      'No layout ${pyRepr(layoutName)}. '
          'Available: ${available.map(pyRepr).join(', ')}',
    );
  }
  final layers = layout.slideObjectsLayerWithLayout;
  final contents = <SlideObject>[
    for (final obj in layout.contents ?? const <SlideObject>[])
      if (_instantiates(obj, layers: layers))
        obj.deepCopy()..instructionalText = null,
  ];
  _renewIdentifiers([
    for (final o in contents)
      if (o.sourceKind != SourceKind.layout) o,
  ], newIdentifier ?? _uuid4);
  final slide = Slide(layout: layoutName, contents: contents);
  for (final item in iterateModels(slide)) {
    final model = item.model;
    if (model is Image && model.wasMediaReplaced) {
      final owner = item.ancestors.reversed
          .whereType<SlideObject>()
          .firstOrNull;
      if (owner != null && owner.sourceKind == SourceKind.placeholder) {
        model.wasMediaReplaced = false;
      }
    }
    if (model is! SlideObject) {
      continue;
    }
    final defined = model.placeholderInfo?.defined;
    if (defined == null || !_clearedKinds.contains(defined.kind)) {
      continue;
    }
    if (firstText(model) case final text?) {
      _writeText(text, const []);
    }
  }
  return slide;
}
