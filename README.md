# creator_studio_document

A Dart library for reading, creating, and editing Apple Creator Studio
documents, starting with Keynote.

It's a Dart port of [apple/creator-studio-doc-format](https://github.com/apple/creator-studio-doc-format),
Apple's Python library for the same format, and follows it model for model.
It's an unofficial port, not affiliated with or endorsed by Apple.

## Overview

The library works with Keynote presentations in
[Keynote Interchange Format](https://developer.apple.com/documentation/keynoteinterchangeformat)
(`.keyx`). You can use it to:

- Read the slides, text, images, tables, charts, styles, and more in a
  `.keyx` file exported from Keynote.
- Create a presentation from scratch, or from a theme's slide layouts and
  styles.
- Edit a presentation, and check it against the format's rules before you
  save it.

The library reads and writes `.keyx` files itself, in pure Dart, so it doesn't
need Keynote, an Apple device, or a network connection. Opening and saving
files by path needs `dart:io`; reading and writing a document's bytes
(`KeyxDocument.fromBytes` and `toBytes`) works on every platform, the web
included. To preview a presentation, open it in Keynote on an Apple device.
In other places, use the
[Creator Studio Document Exporting API](https://developer.apple.com/documentation/creatorstudiodocumentexportingapi)
to convert to other formats like PDF.

## Getting started

### Installation

The library needs Dart 3.13.7 or later. Add it to your package:

```sh
dart pub add creator_studio_document
```

### Quick start

Build a `Presentation` with a slide that holds a text box, wrap it in a
`KeyxDocument`, and save it as `hello.keyx`, which you can open in Keynote:

```dart
import 'package:creator_studio_document/creator_studio_document.dart';

void main() {
  final title = Textbox(
    geometry: Geometry(
      position: Position(x: 160, y: 440),
      size: Size(width: 1600, height: 200),
    ),
    stroke: Stroke(empty: true),
    layoutProperties: LayoutProperties(
      verticalAlignment: const Override.value(VerticalAlignmentType.center),
    ),
    paragraphProperties: ParagraphProperties(
      alignment: const Override.value(AlignmentType.center),
      characterProperties: CharacterProperties(
        fontSize: const Override.value(96),
      ),
    ),
    text: Text(string: 'Hello, Keynote'),
  );
  final slide = Slide(
    contents: [SlideObject(object: CanvasObject(textbox: title))],
  );

  final presentation = Presentation(
    // Without a theme, Keynote uses White in the system locale. The name is
    // localized, so pair it with a locale.
    theme: KeynoteTheme(name: 'White', locale: 'en_US'),
    // Without a slide size, Keynote has to supply one, such as the theme's,
    // or reject the document.
    slideSize: Size(width: 1920, height: 1080),
    slides: [slide],
  );

  KeyxDocument(presentation).save('hello.keyx');
}
```

[`example/main.dart`](example/main.dart) is this program, with an output path
argument and a check before the save, and the other scripts in
[`example/`](example/README.md) cover each kind of slide content.

## Libraries

| Library | What it holds |
| --- | --- |
| `package:creator_studio_document/creator_studio_document.dart` | The models, one Dart class per type of the format, such as `Presentation`, `Slide`, and `Textbox`; `KeyxDocument`, which reads and writes a `.keyx` file; `Preset` and `PresetRegistry`; `Override`; `Version`; the errors; and `sameJson`. |
| `package:creator_studio_document/navigation.dart` | `iterateModels`, which walks a model tree, and `IteratedModel`. |
| `package:creator_studio_document/validation.dart` | `validateDocument`, which checks a document against the format's rules, and its errors and warnings. |
| `package:creator_studio_document/authoring.dart` | `slideFromLayout`, `summarizeSlideLayouts`, `setSlidePlaceholderText`, and `setSlidePlaceholderImage`, which build slides from a theme's layouts by placeholder name. |

### Names that clash with `dart:core` and Flutter

The models keep the format's type names, and some of them are also names in
`dart:core` (`Duration` and `Pattern`) or in Flutter (`Image`, `Text`,
`Table`, `Row`, `Size`, `Rect`, `Color`, `Gradient`, `Shadow`, `Path`,
`Offset`, and `Paragraph`, among others). An imported name hides the
`dart:core` one in that file. Where both are needed, as in a Flutter app,
import the library with a prefix:

```dart
import 'package:creator_studio_document/creator_studio_document.dart' as keyx;

final text = keyx.Text(string: 'Hello');
final elapsed = Duration(seconds: text.string!.length); // `dart:core`'s.
```

Alternatively, `hide` the names you don't use, or `show` only the ones you
do.

## Guide

The guide condenses upstream's
[guide](https://apple.github.io/creator-studio-doc-format/#guide) for Dart.
Its code is in [`doc/snippets/`](doc/snippets), which the tests run.

### Creating and editing a presentation

A [*document*](#glossary) is a presentation together with its presets,
manifest, and resources. A `Presentation` is a tree of models. The quick
start above builds one, wraps it in a `KeyxDocument`, and saves it.

Most objects on a slide have a `Geometry`, measured in points. The object sits
inside a `CanvasObject`, which sits inside a `SlideObject`. `slideSize` sets
the slide's size in the same units. A position is measured from the slide's
top-left corner, with *y* increasing downward.

Open a document with `KeyxDocument.open`, change its models, and save it. To
edit a presentation you made in Keynote, export it first by choosing
File > Export To > Keynote X. A `.keyx` file leaves out some Keynote features,
such as transitions, builds, and comments, so the document you edit and save
holds none of them.

Each model is a mutable Dart object. Read and assign its properties, and
change its lists in place. A constructor and every setter check the value at
once, and throw `ModelValidationError` for one the format doesn't allow, such
as `RGBA(red: 2)`:

```dart
final doc = KeyxDocument.open('hello.keyx');
final first = doc.presentation.slides[0]; // Read.
doc.presentation.slides.add(Slide()); // Construct.

first
  // Assign.
  ..note = Text(string: 'Welcome everyone, then move on.')
  // Delete.
  ..contents!.removeAt(0);

doc.save('edited.keyx', preSaveHooks: [validateDocument]);
```

To catch an edit that breaks the format's rules before anything is written,
pass `validateDocument` in the `preSaveHooks` argument of `save`.

### Adding content to a slide

Wrap content in a `CanvasObject`, which has one field for each kind of content,
such as `textbox` or `shape`. The `CanvasObject` goes inside a `SlideObject` in
the slide's `contents`.

#### Set one case of a union

`CanvasObject`, `Fill`, `Color`, `Stroke`, `Path`, and other unions hold one of
several kinds of value, called *cases*. Each case is an optional constructor
parameter. Set the one for the case you want:

```dart
// `Fill.color` holds a `Color`, which is itself a union.
final red = Fill(
  color: Color(rgba: RGBA(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)),
);
final noBorder = Stroke(empty: true); // A case with no payload takes `true`.
```

A union with no case set throws `ModelValidationError`. A union with two cases
set throws nothing, and an app that opens the document uses only one of them.
`unionPrimary()` returns the case a reader acts on, as one of a sealed class
hierarchy per union, so you can `switch` over it exhaustively:

```dart
final description = switch (red.unionPrimary()) {
  FillColorCase(:final payload) => 'solid $payload',
  FillGradientCase() => 'gradient',
  FillImageCase() => 'image',
  null => 'none',
};
```

`unionCases()` returns every case set, and `unionOf(primary, …)` builds a union
with several cases and a designated primary one.

#### Add text

The `text` of a `Textbox` or a `Shape` holds a `Text`, which holds one of three
cases: `string` for plain text, `textRuns` for text with a style that changes
within a line, and `paragraphs` for several lines, alignment, or a list. Use
the simplest case that holds your text:

```dart
final plain = Text(string: 'Stargazing Tips');
final styled = Text(
  textRuns: [
    TextRun(
      string: 'Full moon',
      style: CharacterProperties(bold: const Override.value(true)),
    ),
  ],
);
final lines = Text(
  paragraphs: [
    Paragraph(
      contents: [Constituent(run: TextRun(string: 'First line'))],
    ),
    Paragraph(
      contents: [Constituent(run: TextRun(string: 'Second line'))],
    ),
  ],
);

// A content object goes on a slide inside a `SlideObject` and a
// `CanvasObject`.
final slide = Slide(
  contents: [
    SlideObject(
      object: CanvasObject(textbox: Textbox(text: plain)),
    ),
  ],
);
```

#### Add a shape

A shape's outline is `Shape.path`, which holds a `Path`. The `bezier` case of a
`Path` holds SVG path data, and `BezierPath.space` sets the path's coordinate
space, which Keynote stretches over the shape's `geometry`. To move, resize,
or rotate a shape, change `geometry` rather than the path. The simplest space
is a unit box, where the path's numbers are fractions of the shape:

```dart
final unitBox = Rect(
  position: Position(x: 0, y: 0),
  size: Size(width: 1, height: 1),
);
const oval = 'M 0,0.5 A 0.5,0.5 0 1 1 1,0.5 A 0.5,0.5 0 1 1 0,0.5 Z';

final shape = Shape(
  identifier: 'oval',
  geometry: Geometry(
    position: Position(x: 1000, y: 200),
    size: Size(width: 180, height: 180),
  ),
  path: Path(
    bezier: BezierPath(path: oval, space: unitBox),
  ),
);
```

#### Add an image

An `Image` refers to its bytes through a `Resource`. Most images use an
`IndirectResource`, which names a file in `doc.resources`, a map of filenames
to bytes:

```dart
import 'dart:io';

import 'package:creator_studio_document/creator_studio_document.dart';

void main() {
  final doc = KeyxDocument.open('presentation.keyx');
  final pngBytes = File('cover.png').readAsBytesSync();

  final name = doc.resources.uniqueFilename('cover.png');
  doc.resources[name] = pngBytes;
  final image = Image(
    resource: Resource(
      indirect: IndirectResource(identifier: name, filename: 'cover.png'),
    ),
    geometry: Geometry(
      position: Position(x: 160, y: 120),
      size: Size(width: 600, height: 396),
    ),
  );
  doc.presentation.slides.add(
    Slide(
      contents: [SlideObject(object: CanvasObject(image: image))],
    ),
  );
}
```

`uniqueFilename` returns a name no file in the document uses yet, such as
`cover 2.png` when the document already has a `cover.png`. `identifier` names
the file that holds the bytes, and `filename` is the name Keynote shows.
Without `identifier`, `filename` names the file too. A `Movie` or `Audio`
refers to its file the same way.

#### Add a table

A `Table` states its size in `numberOfRows` and `numberOfColumns`. The counts
must match the rows in `content` and the entries in `columnHeaders`, and every
row needs one cell for each column header. Adding a `Row` doesn't update
`numberOfRows`.

A cell's `value` is its formatted display string. A number, date, or Boolean
cell needs a typed `unformattedValue`; without one, Keynote treats the cell as
text.

```dart
Cell revenueCell(int millions) => Cell(
  value: '$millions',
  unformattedValue: UnformattedValue(number: millions.toDouble()),
);

final table = Table(
  geometry: Geometry(
    position: Position(x: 160, y: 260),
    size: Size(width: 800, height: 160),
  ),
  numberOfRows: 2,
  numberOfColumns: 2,
  columnHeaders: [
    ColumnHeader(columnIdentifier: 'product'),
    ColumnHeader(columnIdentifier: 'revenue'),
  ],
  content: [
    Row(
      rowIdentifier: 'coffee',
      cells: [
        Cell(value: 'Coffee'),
        revenueCell(41),
      ],
    ),
    Row(
      rowIdentifier: 'tea',
      cells: [
        Cell(value: 'Tea'),
        revenueCell(12),
      ],
    ),
  ],
);
```

#### Add a chart

Keynote offers more than 20 kinds of charts. All of them take their data in
the same grid, a `ChartData`, whose `plotDirection` sets whether the grid's
rows or its columns become the series:

```dart
final revenue = ChartData(
  chartDataSource: ChartDataSource.chartDataGrid,
  plotDirection: PlotDirection.rowsAsSeries,
  rowLabels: ['Coffee', 'Tea'],
  columnLabels: ['Q1', 'Q2', 'Q3'],
  rows: [
    ChartDataRow(
      values: [
        for (final n in [42.1, 48.3, 51.0]) ChartDataValue(number: n),
      ],
    ),
    ChartDataRow(
      values: [
        for (final n in [38.5, 41.0, 44.2]) ChartDataValue(number: n),
      ],
    ),
  ],
);
final chart = Chart(
  column: ColumnChart(
    data: revenue,
    geometry: Geometry(
      position: Position(x: 160, y: 200),
      size: Size(width: 1200, height: 700),
    ),
  ),
);
```

#### Add a connection line

A `ConnectionLine` takes its position from its two ends, each an `End`. An end
attaches to an object through its `anchor`, which names the object by
`Anchor.objectId`. The object must be in the same list of objects as the line,
such as the slide's `contents`. Wrap a line as
`CanvasObject(connectionLine: …)`.

Every end needs an `endPoint`, even one that `anchor` attaches: omitting it
drops the whole line. For an attached end, use the object's center. The
following line attaches its head to the oval above and leaves its tail
unattached:

```dart
final arrow = ConnectionLine(
  tail: End(endPoint: Position(x: 450, y: 290)),
  head: End(
    endPoint: Position(x: 1090, y: 290),
    anchor: Anchor(objectId: 'oval'),
    lineEnd: LineEnd.filledArrow,
  ),
);
```

#### Style content with a preset

A [*preset*](#glossary) lets content share one set of properties, which keeps
styling consistent and the document compact. A preset holds raw JSON
properties, with the format's `snake_case` keys:

```dart
final doc = KeyxDocument.open('presentation.keyx');
doc.presets.addAll([
  Preset('body', {'font_name': 'Helvetica Neue', 'font_size': 24}),
  // The title inherits `font_name` from the body.
  Preset('title', {'font_size': 48, 'bold': true}, parentIdentifier: 'body'),
]);

// A model adopts a preset through `presetIdentifier`.
final heading = TextRun(
  string: 'Baking Sourdough',
  style: CharacterProperties(presetIdentifier: 'title'),
);
final step = TextRun(
  string: 'Feed the starter',
  style: CharacterProperties(presetIdentifier: 'body'),
);
```

### Authoring from a theme

A theme already provides the design. Its slide layouts set type, color,
geometry, and spacing, and its presets define styles that new models can
reuse. In Keynote, export a presentation that uses the theme; every document
you build from that file starts with the theme's slide layouts and presets.
`package:creator_studio_document/authoring.dart` fills in the placeholders of
those layouts.

`summarizeSlideLayouts` reports every slide layout by name, with the
placeholders you can set in it:

```dart
import 'dart:io';

import 'package:creator_studio_document/authoring.dart';
import 'package:creator_studio_document/creator_studio_document.dart';

void main() {
  final doc = KeyxDocument.open('themed.keyx');
  final theme = doc.presentation.theme!;

  for (final MapEntry(key: layout, value: placeholders)
      in summarizeSlideLayouts(theme).entries) {
    stdout.writeln('$layout ${[for (final p in placeholders) p.name]}');
  }
}
```

For [`example/fixtures/Tidal_en.keyx`](example/fixtures), part of the output
is:

```text
Title [TITLE, Subtitle]
Title & Bullets [TITLE, BODY, Presentation Name, SLIDE_NUMBER]
Title, Bullets & Photo [TITLE, BODY, Media]
Quote [Text, Text-1]
Blank []
```

Each placeholder is a `LayoutPlaceholderSummary`:

- `name` identifies the placeholder within its layout; you pass it to the
  function that fills the placeholder.
- `objectCase` names the kind of object the placeholder holds. An `'image'`
  placeholder takes an image, and a `'shape'` or `'textbox'` placeholder takes
  text.
- `prompt` holds the placeholder text Keynote shows, such as `'Title Text'`,
  or `null`.
- `tag` holds the label that the theme's designer gives a custom placeholder,
  such as `'Presentation Name'`, or `null` for a predefined one such as
  `'TITLE'`. A tagged placeholder's `name` is its tag.

`slideFromLayout` creates a slide the way Keynote does when you choose that
layout, and returns it for you to add to the document:

```dart
final slide = slideFromLayout(theme, 'Title & Bullets');
```

`setSlidePlaceholderText` fills a text placeholder with one paragraph per
line, each with the placeholder's text style. `setSlidePlaceholderImage` points
an image placeholder at a resource; it doesn't store the image's bytes, so add
them to `doc.resources` first. `slideFromLayout` empties only the `TITLE` and
`BODY` placeholders: as in Keynote, a tagged placeholder keeps its sample text
and an image placeholder keeps its sample photo until you replace them.

```dart
setSlidePlaceholderText(slide, 'TITLE', ['Baking Sourdough']);
setSlidePlaceholderText(
  slide,
  'BODY',
  ['Feed the starter', 'Twice a day'],
  // Sets each line's list level. Every level keeps the placeholder's
  // paragraph style.
  listLevels: [0, 1],
);
// Passing null clears the tagged placeholder's sample text.
setSlidePlaceholderText(slide, 'Presentation Name', null);
```

```dart
final photo = slideFromLayout(theme, 'Title, Bullets & Photo');
final filename = doc.resources.uniqueFilename('cover.png');
doc.resources[filename] = File('cover.png').readAsBytesSync();
setSlidePlaceholderImage(
  photo,
  'Media',
  Resource(indirect: IndirectResource(filename: filename)),
  // The width and height of cover.png, so the image fills the
  // placeholder's mask without stretching.
  size: Size(width: 1200, height: 792),
);
```

The following program replaces a themed document's slides with ones that use
its layouts, and saves the result as a new file:

```dart
final sections = [
  ('Baking Sourdough', ['Feed the starter', 'Shape the loaf']),
  ('Baking Day', ['Preheat the oven']),
];

final doc = KeyxDocument.open('themed.keyx');
final theme = doc.presentation.theme!;

final slides = <Slide>[];
for (final (title, bullets) in sections) {
  final slide = slideFromLayout(theme, 'Title & Bullets');
  setSlidePlaceholderText(slide, 'TITLE', [title]);
  setSlidePlaceholderText(slide, 'BODY', bullets);
  setSlidePlaceholderText(slide, 'Presentation Name', null);
  slides.add(slide);
}

// Replacing the slides in place keeps the theme, its presets, and
// everything else in the document.
doc.presentation.slides = slides;
doc.save('presentation.keyx', preSaveHooks: [validateDocument]);
```

When no layout fits, style the models you create with the theme's presets. To
see what a preset provides, resolve it with `PresetRegistry`:

```dart
final styles = {
  for (final style in doc.presentation.stylesheet!.paragraphStyles!)
    if (style.properties.presetIdentifier.isNotEmpty)
      style.name: style.properties.presetIdentifier,
};
final registry = PresetRegistry(doc.presets);
final font =
    registry.resolvedProperties(styles['Body']!)['character_properties']!
        as Map<String, Object?>;
stdout.writeln('${font['font_name']} ${font['font_size']}');
```

A style property that a preset can supply is often an `Override` field, which
keeps an omitted property apart from an explicit `null`. Pass
`Override.value(x)` to set it, `Override.cleared()` to write `null`, which
removes what a preset gives (`shape.shadow = const Override.cleared()` removes
the shadow of the shape's preset), and nothing, or `Override.notSet()`, to
omit it. `get()` returns `null` for both an omitted and a cleared property;
read `isNotSet` or `isCleared` to tell them apart. On a field that isn't an
`Override`, such as `Shape.fill`, `null` omits the property.

### Navigating a document

A document can hold thousands of models, because even a short presentation
carries its theme's layouts and styles. `iterateModels` takes any model, such
as a presentation or a slide, and yields it and every model nested inside it,
in pre-order. The following program prints the text of every `Text` and
`TextRun` on each slide:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/navigation.dart';

void main() {
  final doc = KeyxDocument.open('presentation.keyx');
  // Per slide, because the presentation also holds placeholder text from
  // slide layouts.
  for (final (index, slide) in doc.presentation.slides.indexed) {
    for (final item in iterateModels(slide)) {
      if (item.model
          case TextRun(:final String string) || Text(:final String string)
          when string.isNotEmpty) {
        stdout.writeln('${index + 1} ${jsonEncode(string)}');
      }
    }
  }
}
```

For `example/fixtures/Tidal_en.keyx`, the output starts with:

```text
1 "A theme built for testing, not for sale"
2 "Example Company"
2 " · Confidential"
3 "#"
7 "Photo caption sample"
```

Each item is an `IteratedModel`, which holds the `model` together with where
it sits in the tree: `ancestors` lists the models that enclose it, starting
from the outermost, `path` names the fields that lead to it, such as
`contents[0].object.textbox`, and `parent`, `fieldName`, and `listIndex`
describe the last step. The following program prints the caption text inside
an `Image`, which for `Tidal_en.keyx` is `7 "Photo caption sample"`:

```dart
for (final (index, slide) in doc.presentation.slides.indexed) {
  for (final item in iterateModels(slide)) {
    if (item.model
        case TextRun(:final String string) || Text(:final String string)
        when string.isNotEmpty) {
      if (item.ancestors.any((ancestor) => ancestor is Image)) {
        stdout.writeln('${index + 1} ${jsonEncode(string)}');
      }
    }
  }
}
```

To explore an unfamiliar document, print only a few fields, or the top levels
of a model's `toJson()` with long lists and strings cut short;
[`example/inspection.dart`](example/inspection.dart) has an `outline` function
that does that.

`KeyxDocument.open` reads every resource into memory. `KeyxDocument.openLazy`
reads a resource's bytes only when you first access them, so a document with
many images or movies opens as fast as its JSON:

```dart
final big = KeyxDocument.openLazy('big-presentation.keyx');
try {
  stdout.writeln(big.presentation.slides.length); // This reads no resource.
  final photo = big.resources['sample_photo.jpg']; // This reads only that.
  stdout.writeln('${photo!.length} bytes');
} finally {
  big.close();
}
```

The document keeps the file open until `close`. Read the resources you need
before closing it; `save` and reading every entry of `doc.resources`, such as
through `values` or `entries`, read every resource, so call them before
`close` too. Listing `doc.resources.keys` reads none. Editing models and running
`validateDocument` read no resources.

### Validating a document

The format places rules on every document, from the type of each field to the
slides that links point to. The library checks them when you open a document,
as you edit its models, and before you save, when you pass `validateDocument`
to `save`.

Opening a document checks the file, and a failure throws an error that says
why:

```dart
import 'dart:io';

import 'package:creator_studio_document/creator_studio_document.dart';

void errors(String path) {
  try {
    KeyxDocument.open(path);
  } on DocumentVersionError {
    stdout.writeln('$path needs a newer version of the library.');
  } on DocumentPackageError catch (e) {
    // Branch on `kind`. The message text varies.
    if (e.kind == DocumentPackageErrorKind.notAPackage) {
      stdout.writeln("$path isn't a document.");
    } else {
      stdout.writeln('$path is corrupt (${e.kind.value}).');
    }
  } on ModelValidationError {
    stdout.writeln("$path doesn't match this library's models.");
  } on FileSystemException catch (e) {
    stdout.writeln("Can't read $path: ${e.osError?.message ?? e.message}.");
  }
}
```

Dart checks the types of a model's fields when it compiles. Constructing a
model, or setting one of its fields, also checks the format's constraints,
such as `slides` needing at least one entry and a color component lying
between `0` and `1`, and throws `ModelValidationError` at the statement
responsible: `Presentation(slides: [])` and `rgba.red = 2` both throw. A
model doesn't check an item added to one of its lists in place, such as with
`slides.add`, and nothing checks the references across a document as you
edit. `validateDocument` checks the whole document before `save` writes it,
including the values that presets supply, the references between objects, and
the resources that the document refers to. Pass it in the `preSaveHooks` of
every `save`; without it, an edit that breaks the format's rules, such as
deleting a slide that a link points to, reaches the saved file unnoticed:

```dart
final doc = KeyxDocument.open('presentation.keyx');
final slides = doc.presentation.slides;
slides.first.note = Text(string: 'Checked before saving.');

// Writes nothing if the document is invalid.
doc.save('out.keyx', preSaveHooks: [validateDocument]);
```

### Glossary

- **document**: a `.keyx` file as a whole, which is the presentation together
  with its presets, manifest, and resources. It's a ZIP archive of
  `main.json` (the presentation), `presets.json` (the presets),
  `manifest.json` (the manifest), and `Data/` (the resources kept as files).
  A `KeyxDocument` holds one in memory.
- **reader**: a program that opens a document, such as Keynote.
- **property**: a key-value pair in a JSON object, such as `"width": 1024`.
- **identifier**: the name other JSON objects use to refer to one, such as a
  preset. It's unique across the whole document.
- **preset**: a reusable, named set of properties that JSON objects in
  `main.json` adopt, through `presetIdentifier`, and inherit. A preset can
  build on a parent preset through `parentIdentifier`.
- **resource**: binary data that a JSON object references, such as the bytes
  of an image, kept as a file in `Data/` or embedded in the JSON.
- **manifest**: the part of a document that declares its `package_version`,
  the version of the format the document uses.
- **version**: a number in major.minor form, such as `1.0`. Each type has one,
  and a JSON object can declare which version of its type it follows.
- **model**: a Dart object that represents a JSON object in the document, an
  instance of a class such as `Slide` or `Text`, whose fields mirror the JSON
  object's properties.
- **union**: a model for a property that holds exactly one of several values,
  called *cases*, such as a `CanvasObject`, which holds a text box, a shape, or
  another object.
- **theme**: the predesigned look a presentation builds on, chosen by name,
  such as `White`. It provides the slide layouts and default styles.
- **slide layout**: one of a theme's predesigned slides, which a slide builds
  on through `Slide.layout`. It provides the slide's placeholders and
  background.
- **placeholder**: an object that marks where content goes on a slide, such as
  the title or body text.

The format itself is documented in
[Keynote Interchange Format](https://developer.apple.com/documentation/keynoteinterchangeformat).

## Examples

[`example/README.md`](example/README.md) indexes a runnable script for each
kind of slide content, such as charts, tables, lists, hyperlinks, and images,
and for working from a theme or on an existing document. Run one with
`dart run example/<name>.dart`.

## Agent skill

[`skills/creator-studio-document/SKILL.md`](skills/creator-studio-document/SKILL.md)
teaches a coding agent to use the library. Any agent that reads `SKILL.md`
folders can use a copy of that folder.

## Regenerating the models

The model classes are generated from upstream's models, not written by hand.
[`tool/README.md`](tool/README.md) describes the pipeline and how to update it
to a new upstream release.

## Differences from upstream

### API

The port keeps upstream's names and behavior, in Dart's shape:

- Classes keep upstream's names. Fields, methods, and function parameters are
  lowerCamelCase: `aspect_ratio_locked` is `aspectRatioLocked`,
  `union_primary()` is `unionPrimary()`, and `slide_from_layout` is
  `slideFromLayout`. Enum members are the lowerCamelCase of their wire value,
  such as `AlignmentType.center` and `LineEnd.filledArrow`, and each has a
  `wireValue`. A model's JSON, and a preset's properties, keep the format's
  `snake_case` keys.
- `model_validate(data)` is `X.fromJson(data)`, and `model_dump(mode="json")`
  is `toJson()`, which takes a `WireContext` with the presets for a model that
  adopts one. A union's `toJson()` returns a `String` for a lone case with no
  payload, as upstream does.
- A required field is a `required` named parameter. An `Override` field takes
  `Override.value(x)`, `Override.cleared()`, or `Override.notSet()`, where
  upstream takes the bare value or `None`. A case with no payload, such as
  `Stroke(empty: true)`, takes `true`.
- `model_copy()` is `deepCopy()`, and `model_copy(update=…)` is a `deepCopy()`
  followed by setters, such as `rgba.deepCopy()..alpha = 0`.
- `Preset(identifier, properties, displayName: …, parentIdentifier: …)` takes
  its identifier and properties as positional parameters.
- `setSlidePlaceholderText` takes a `List<String>?` where upstream also takes
  a bare string.
- Pydantic's `ValidationError` is `ModelValidationError`, and Python's
  `OSError` is `FileSystemException`: `FileNotFoundError` is
  `PathNotFoundException`, and `PermissionError` is `PathAccessException`,
  when opening or saving a package. The library's own error types, such as
  `DocumentError`, `ModelValidationError`, and `DocumentValidationError`,
  implement `Exception`.
- Where upstream raises one of Python's built-in exceptions, the port throws
  one of Dart's `Error`s, with the same message, under the same conditions.
  In the authoring functions, `KeyError` is `ArgumentError`, for a layout or
  placeholder name that matches none, `TypeError` is `UnsupportedError`, for
  a placeholder of the wrong kind, and `ValueError` is `ArgumentError`, for
  bad `listLevels`. Elsewhere, `TypeError`, `AttributeError`, and the
  `ValueError` of a bad argument are `ArgumentError`, such as for a filename
  that isn't flat, or for malformed presets or a `primary_case` that's a list
  that `validateDocument` meets. Catching one means catching an `Error`, so
  check a name that a user supplies against the names that
  `summarizeSlideLayouts` lists before passing it.
- Saving and encoding throw `StateError` where upstream raises `ValueError`
  or `UnicodeEncodeError` for a document it can't write: `save`, `toBytes`,
  `toMainJson`, and `toJson` for a union with no case set, such as one whose
  every case was cleared in place (upstream's `PydanticSerializationError`,
  which words the same message as ``Error calling function `_wire_encode`:
  ValueError: …``), and for a value nested more than 256 levels deep (see
  below); `save` and `toBytes` for indirect resources missing from `Data/`,
  and for a string that holds a lone surrogate, in the JSON or in a `Data/`
  filename, with the message of upstream's `UnicodeEncodeError`.
  `validateDocument` reports a union with no case set, and a value nested
  too deeply, as a `DocumentValueError`, with upstream's message, when it
  encodes the payload itself. `ResourceStore.bytesFor` throws
  `ArgumentError` where upstream's `bytes_for` raises `KeyError`, for a name
  that matches no key or matches ambiguously.
- Saving and encoding a payload that adopts a preset whose
  `parent_identifier` chain has a cycle throw `PresetCycleError`, an
  `Exception`, as `PresetRegistry.resolvedProperties` does. Upstream's
  registry raises a `ValueError` with the same message, ``circular preset
  `parent_identifier` chain at 'title_text'``, which `save` reports as a
  `PydanticSerializationError` prefixed ``Error calling function
  `_wire_after`: ValueError:``. `validateDocument` reports the cycle first,
  as upstream does.
- `del store[name]` on a `ResourceStore` is `store.delete(name)`, which reads
  nothing, so it also drops a resource that a lazily opened archive holds
  corrupt. `store.remove(name)` returns the bytes, so it reads them first, as
  upstream's `store.pop(name)` does.
- `with KeyxDocument.open_lazy(path) as doc:` is `KeyxDocument.openLazy(path)`
  with `close()` in a `finally` block.
- Upstream's `warnings.warn` and `logging` messages are `package:logging`
  records at `Level.WARNING`, from loggers named `creator_studio_document.*`.
  Listen to `Logger.root.onRecord` to see them.

### Behavior

The port follows upstream exactly where Dart allows it. Where it doesn't, or
where upstream's behavior comes from a defect in Pydantic rather than from the
package itself:

- An integer field holds a 64-bit Dart `int`. A package reads an integer
  literal of 2^63 or more as the exact `BigInt`, as Python reads it: an
  unknown key and a preset's properties keep it, and `save` writes it back
  unchanged, and a float field and a `{"major", "minor"}` version map read it
  as upstream does. An integer field can't hold one, though: a document with
  `"outline_level": 9223372036854775808` fails to decode with an `int_type`
  issue, where upstream reads it and writes it back unchanged.
- `dart:convert` decodes an integer literal of 2^63 or more as a `double`,
  and one too large for a `double`, such as `1` followed by 400 zeros, as
  infinity. JSON that `jsonDecode` read and that a model decodes with
  `fromJson` therefore differs from a package's at such a literal: a version
  map part that holds one is unparsable, and a float field that holds one
  too large for a `double` fails with a `finite_number` issue, where upstream
  and a package report `float_type`.
- Upstream's models are built on Pydantic, which runs the wrap validator or the
  wrap serializer of a nested model twice at some places, depending on the
  order in which it built the models' schemas. The port decodes and encodes
  every model once, as upstream does for a model at the top level, so a
  document that adopts presets can come out differently at those places:
  - A `CanvasObject` nested in another model, such as `SlideObject.object`,
    `Group.children`, or an inline object, that adopts a preset. Upstream's
    second pass no longer sees the declared `version` or `primary_case`, so it
    fills cases newer than the declared version from the preset, and then
    encodes the newer version and that case as `primary_case`. The port keeps
    to the declared version, as upstream does for a top-level `CanvasObject`.
  - A `Label` nested as a title or caption, such as `Shape.title` in a `Group`
    or a `Slide`, and a `Table` as `TransformationInfo.base_table`, that adopt
    a preset. Upstream's second pass writes `null` for a field that the first
    factored out against the preset, which reads back as the field's default,
    or fails to decode for a required field, and logs the floor warning of an
    edited model twice. The port leaves the key out, as upstream does for a
    top-level `Label` or `Table`, so the document reads back equal.
- Pydantic guards only some of the references between models against cyclic
  input, so it can report a cycle, such as a preset that adopts itself, at a
  different depth than the port, which guards every model. Both reject the
  input with a `recursion_loop` issue, but its location, the number of issues,
  and the warnings that the preset registry collected on the way can differ.
- Python's `json` module and Pydantic recurse for each level of nested JSON,
  and the port follows their limits. Reading accepts arrays and objects
  nested up to 9,998 deep, the depth at which Python 3.13 raises
  `RecursionError` by default (a little earlier when it's called from deep
  in the call stack). Where upstream lets that `RecursionError` escape, the
  port throws a `DocumentPackageError` of kind `malformed_json`, or
  `malformed_presets` for `presets.json`, with the same message, such as
  ``main.json: maximum recursion depth exceeded while decoding a JSON array
  from a unicode string``. Encoding a payload, as upstream's Pydantic
  serializer does, accepts values nested up to 256 levels, counting the
  payload as 1 and each model, list, map, and value inside it as one level
  deeper, and throws `StateError` with upstream's `Maximum serialization depth
  exceeded` beyond that; the port never adds the ``Error calling function
  `_wire_after`: ValueError:`` prefix that Pydantic adds at some depths. Some
  of upstream's own checks also recurse, so `validate_document` raises
  `RecursionError` for a preset property nested about 1,000 levels deep,
  which `validateDocument` checks without a limit.
- `validateDocument`'s message for a value that skipped validation ends with
  a hint that names the Dart way to skip it: ``An in-place change, such as to
  a list, likely set the value, and it skips validation. Reassign the field to
  revalidate it.`` Upstream's hint names the Python ways, ``In-place
  mutation, `model_construct`, or `model_copy(update=...)` likely set the
  value, and all three skip validation.``, and the rest of the message is the
  same.
- On the web, JavaScript has one number type: `2.0 is int` is true, and
  `jsonEncode` writes the double `1.0` as `1`. A decoded `2.0` therefore passes
  as an integer field's value, where upstream and the Dart VM reject it, and a
  float field holding a whole number encodes without its `.0`. Both read back
  as the same value, but the JSON text differs from upstream's.
- A float field whose upstream default is an int, such as `Line.width`, reads
  as a `double`. Encoding still tells an untouched default from one set in
  place to the same number, as upstream does.
- Reading an archive follows Python's `zipfile` and the decompressors it
  uses, zlib, libbzip2, and liblzma, which the port reimplements: a member
  reads to the same bytes, or fails with the same message, as upstream. Where
  upstream lets an exception of `zipfile` escape for a damaged archive, the
  port throws a `DocumentPackageError` of kind `malformed_archive` with the
  same message, so a caller that skips any `DocumentPackageError` skips every
  damaged archive: the `BadZipFile` of an archive that spans disks, the
  `UnicodeDecodeError` of an entry name that isn't the UTF-8 that its flag
  claims, and the bare `EOFError` of a member that the file ends inside (as
  `Compressed file ended before the end of data`). A central directory that
  puts a local header before the start of the archive is `Truncated file
  header`, where upstream raises `OSError` (`[Errno 22] Invalid argument`)
  for a path and `ValueError` (`negative seek value`) for a stream.
- The messages of a malformed archive differ from upstream's in two places.
  An archive read from bytes is `the bytes` where upstream's, read from a
  stream, is `the stream`. macOS's zlib reports a bad code in its fast loop as
  `invalid literal/length/distance code`; the port, as zlib itself does,
  reports `invalid literal/length code` or `invalid distance code`.
- Python reads at most 1 GiB of a deflate member past its declared size, and
  so does the port; it stops bzip2 and LZMA members at the same point, where
  Python decompresses all of them and reports damage further on, or runs out
  of memory.

### Examples

The JSON entries of the documents that the example scripts write are
upstream's, byte for byte, as `test/examples/examples_test.dart` checks, with
two exceptions. `image_decoration.dart` gives its contact shadow no `angle`,
which isn't a field of `ContactShadow` and which upstream writes as an unknown
key.
`tables.dart` leaves `type_identifier` and `version` out of its stroke presets,
as the comment in both scripts says; upstream's
`model_dump(exclude={"type_identifier", "version"})` writes them anyway,
because its wire serializer adds them back. `inspection.dart` also prints an
outline of the first slide, where upstream points to a third-party
pretty-printer, and the scripts quote strings as JSON does rather than as
Python's `repr` does.

## License

This package is licensed under the [Apache License, Version 2.0](LICENSE).
It's a port of [apple/creator-studio-doc-format](https://github.com/apple/creator-studio-doc-format),
Copyright © 2026 Apple Inc., which is licensed under the same license; see
[NOTICE](NOTICE). It's an unofficial port, not affiliated with or endorsed by
Apple. Keynote is a trademark of Apple Inc.
