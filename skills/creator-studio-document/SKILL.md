---
name: creator-studio-document
description: Read, create, and edit Keynote presentations in Keynote Interchange Format (.keyx) as files from Dart, with no app running. Use when the user asks to create, make, generate, or build slides, a slideshow, a deck, a presentation, or a Keynote file, or to change, restyle, summarize, or extract text from an existing .keyx, in a Dart or Flutter project.
---

# Keynote presentations in Dart

You read, create, and edit Keynote presentations (Keynote Interchange Format
`.keyx` files) by writing a small Dart program with the
`creator_studio_document` package.

## Workflow

### 0. Check the setup

Neither placeholder in this skill is a shell environment variable. Substitute
the actual value for each one everywhere it appears:

- `<PROJECT>` is the Dart package that depends on `creator_studio_document`:
  the directory of its `pubspec.yaml`. Run every command in it.
- `<PKG>` is the installed package's root directory. Read and search it by
  absolute path.

If your context already gives a value for each, use those. Otherwise use the
package in the current directory. Run `dart pub get` there, then read the
`rootUri` of the entry named `creator_studio_document` in
`<PROJECT>/.dart_tool/package_config.json`; it's a `file://` URI of `<PKG>`,
or a path relative to `.dart_tool/`.

If there's no such entry, `creator_studio_document` isn't a dependency. Tell
the user to run `dart pub add creator_studio_document` in that package, and
stop. Don't add it yourself.

### 1. Look up the API in the installed package

Start from the examples, then look up exact fields:

- Start at `<PKG>/example/README.md`. It indexes every sample script and says
  what each covers. Then read the sample scripts it points to, which are
  working patterns to copy. Take filenames from that index, not from memory.
- Search for exact class, field, and enum names when the examples don't cover
  something. Search `<PKG>/lib/src/core/models.g.dart` for a pattern such as
  `class Shape `. The file is large, so search it rather than reading it
  whole. Enum members are the lowerCamelCase of exact wire strings, such as
  `VerticalAlignmentType.center`, so look them up rather than guessing a
  synonym.
- `<PKG>/README.md` holds the guide: unions, `Override` fields, presets,
  layouts, navigation, and validation.

What the program does depends on the request:

- To create a presentation, build the top-level document and save it.
- To edit a presentation, open the user's file with `KeyxDocument.open`,
  change the models, and save. Save to a new filename unless the user asks to
  overwrite the original.
- To analyze a presentation, open the file and read it. No save is needed.

A real document can hold thousands of models, so print only a depth-limited
view of one and filter `iterateModels` (from
`package:creator_studio_document/navigation.dart`) to find a model, instead of
printing a whole subtree's `toJson()`. `<PKG>/example/inspection.dart` shows
both.

Dart specifics that the examples follow:

- A style property that a preset can supply is an `Override`: pass
  `Override.value(x)` (or `const Override.value(x)`), not the bare value.
- A union takes one case: `Fill(color: …)`, `Stroke(empty: true)`.
- Model names such as `Image`, `Text`, `Path`, and `Duration` clash with
  Flutter or `dart:core`. In a Flutter project, import the library with a
  prefix.

### 2. Run and deliver

Write the program inside `<PROJECT>`, such as `tool/make_deck.dart`, so it
resolves the package, and run it from `<PROJECT>`:

    dart run tool/make_deck.dart

Pass `validateDocument`, from `package:creator_studio_document/validation.dart`,
to `save` in `preSaveHooks`, as the examples do:

    doc.save(output, preSaveHooks: [validateDocument]);

`validateDocument` throws before anything is written if the document breaks
the format's rules. If the program throws, read the error, fix the program,
and rerun it. Keep `validateDocument` in `preSaveHooks` on every run,
including the rerun after a failed save, because removing it to force a save
isn't a fix. Hand over only a document that has passed it. Run
`dart analyze` on the program if it doesn't compile.

After a save, tell the user the output path. After an analysis, report what
you found.

## Design defaults

These apply when you create or restyle slides. Commit to a clear aesthetic
direction, such as bold minimalism, editorial density, warm organic, or sharp
corporate. Intentionality matters more than intensity. Give each presentation
a look of its own, rather than the same generic one.

The following are soft priors, so deviate when the content justifies it:

- Hold colors, typography, and spatial logic consistent throughout.
- Limit icons and emoji to an intentional, consistent visual language.
- Prefer negative space over filling the canvas, and fragments over full
  sentences.
- Scale the following point sizes proportionally if you change the canvas
  from its default of 1920 x 1080 pt.
- Set titles at about 90–150 pt, and body text at about 40–60 pt and at least
  32 pt. Body text is anything the audience reads as content, including
  descriptions, bullets, and captions under icons or images. Only footers,
  slide numbers, and source notes go smaller.
- Give one section of a multisection grid more weight than the rest, so the
  slide keeps its hierarchy.
