# Example scripts

The package has four libraries. A name that isn't in the main library is
probably in one of the others:

- `package:creator_studio_document/creator_studio_document.dart`: the models,
  which mirror the types in `main.json` one to one, and `KeyxDocument`, which
  represents a document. The root is `doc.presentation`, which holds `slides`,
  `slideSize`, and `theme`.
- `package:creator_studio_document/navigation.dart`: `iterateModels`, which
  walks a model tree.
- `package:creator_studio_document/authoring.dart`: `slideFromLayout` and its
  helpers, which build slides from a theme's layouts by placeholder name.
- `package:creator_studio_document/validation.dart`: `validateDocument`, which
  checks a document against the format's rules.

Models such as `Fill`, `Color`, and `Chart` are each a `TaggedUnionModel`,
which holds one of several variants, called cases. Such a class has one
optional constructor parameter per case, and a value sets the parameter for
the case it holds: `Fill(color: …)`, or `Stroke(empty: true)` for a case with
no payload. Read the `TaggedUnionModel` documentation before reading or
editing one, because a value can hold more than one case.

**Set a style property through `Override`.** A property that a preset can
supply, such as `CharacterProperties.fontSize`, is an `Override`: pass
`Override.value(96)` to set it, `Override.cleared()` to write an explicit
`null`, and nothing to leave it to the preset.

**Remove a default border with `Stroke(empty: true)`.** `Shape.stroke` and
`Textbox.stroke` default to a visible line, so a shape or text box you want
borderless has to set it.

**Tracking is a fraction of the font's em, not points.** For `tracking`, `0.0`
is the default spacing, `0.05`–`0.2` gives subtle emphasis, and `1` or more
adds a full em or more between letters. Validation doesn't flag a value in
points.

**Read a document in bounded pieces.** A real document can hold thousands of
models, and every model's JSON holds its `type_identifier` and `version`,
which buries the fields you want. Filter `iterateModels(root)` for what you
need and print only those fields, or print the top levels with truncated
output (`inspection.dart` shows how). Don't print a whole subtree's `toJson()`.

**Import with a prefix where names clash.** The library exports names like
`Image`, `Text`, `Path`, and `Duration` that clash with Flutter's or
`dart:core`'s. Import it `as` a prefix, or `hide` what you don't use, where
that matters.

## Examples

The examples fall into three groups: content elements that you place on a
slide, the slide and document structure that holds them, and work on a
document that already exists. Each entry below describes one example, and
each example runs standalone. Start with `basics.dart`, which touches the most
common pieces of a slide. Then read the file that matches the task, not the
whole directory.

### Quick start

- `main.dart`: Builds the presentation of one slide with one text box from the
  package's README, `hello.keyx`.

### Content elements

- `charts.dart`: Builds a mixed chart, a pie chart, and a scatter chart, one
  for each axis arrangement of `Chart`, and styles their title, caption, axis,
  and legend text.
- `hyperlinks.dart`: Builds a `Hyperlink` to a URL, to another slide, to a
  file, and to a program action, and links to a slide by position with
  `SlideTarget`.
- `lists.dart`: Builds bullet, numbered, and image lists through
  `ListProperties` and `ListLevelType`, nests list levels, and draws a
  paragraph border rule.
- `image_decoration.dart`: Applies each `Image` decoration (`Mask`, frame
  `Stroke`, `Shadow`, opacity, and `Reflection`) and fills a `Shape` with an
  `ImageFill`.
- `shapes_and_lines.dart`: Draws a rectangle, a rounded rectangle, an oval, a
  polygon, and a star as `Shape` paths, attaches a `ConnectionLine` to two of
  them, and sets `shadow` and `reflection`.
- `spreadsheets.dart`: Builds a `Table` of financial data with a `CellFormat`
  for each column, a `SUM` formula that refers to cells by identifier, and a
  `CellRange` banner row.
- `tables.dart`: Builds a `Table` of cells with header rows and alternating
  rows, and overrides the fill and text of single cells.

### Slide and document structure

- `basics.dart`: Builds a typical content slide with presets, text, a shape,
  an image, a gradient overlay, a `Group` with a title and caption, and a
  presenter note.
- `authoring.dart`: Makes slides from a themed document's layouts with
  placeholders set by name, and builds a slide by hand that takes its styles
  from the theme's stylesheet and `PresetRegistry.resolvedProperties`.

### Existing documents

- `inspection.dart`: Prints an outline of a slide's JSON, finds the text on
  each slide of a `.keyx` with `iterateModels`, prints it, and replaces the
  text of unlocked objects with lorem ipsum of the same length.

Run any script from the package root with no arguments, for example
`dart run example/basics.dart`. The script writes a `.keyx` to a
`creator_studio_document_examples` directory in the system's temporary
directory, or to the path you pass as its last argument; `--help` lists its
arguments, and an unknown option or an extra argument fails with the usage.
Put `--` before a path that starts with `-`. `authoring.dart` and
`inspection.dart` also take an input `.keyx` as their first argument.

Sample files live in `fixtures/`. The files include `.png` images and `.keyx`
documents, such as `sample.keyx`, the default input of `inspection.dart`, and
`Tidal_en.keyx`, a themed document and the default input of
`authoring.dart`. `src/support.dart` holds the command-line plumbing that the
scripts share.

Each script other than `main.dart` is a port of the upstream script of the
same name in
[apple/creator-studio-doc-format](https://github.com/apple/creator-studio-doc-format/tree/main/src/creator_studio_doc_format/examples),
and `main.dart` is a port of the quick start in upstream's
[README](https://github.com/apple/creator-studio-doc-format/blob/main/README.md).
`test/examples/examples_test.dart` checks that the documents they write match
upstream's.
