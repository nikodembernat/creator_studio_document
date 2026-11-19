# Code generation

The model classes in `lib/src/core/models.g.dart` are generated, not written by
hand. Their source of truth is the upstream Python package
([apple/creator-studio-doc-format](https://github.com/apple/creator-studio-doc-format)),
and the pipeline has two steps:

1. `extract_schema.py` imports the upstream package, walks every model in
   `core._MODEL_FOR` and every enum reachable from their field annotations, and
   writes `schema.json`: names, type identifiers, versions, field kinds, types,
   defaults, constraints, union cases, enum members, and docs. It fails on
   anything it can't classify and checks the model and enum counts, so a new
   upstream construct stops the pipeline instead of being skipped.
2. `generate.dart` reads `schema.json` and writes `models.g.dart`: one class per
   model and union, one Dart enum per enum, and the `modelSchemas` registry. The
   generator itself is in `src/generator.dart`.

`schema.json` also holds `python_repr`: the code points that Python's
`str.isprintable` rejects, as the extracting Python's Unicode data classifies
them. Upstream quotes values in its messages and preset warnings with `repr`,
which escapes those code points, and Dart has no Unicode category data of its
own. The generator writes the table to `lib/src/core/py_repr.g.dart`, which
`lib/src/core/py_repr.dart` reads.

`schema.json` also holds `python_layout_name_key`: the one-level compatibility
decompositions and the `str.casefold` mappings of the extracting Python.
Upstream matches slide layout names with NFKD, `casefold`, and NFKC, and the
extractor checks that the Dart algorithm, with the NFC tables, reproduces
Python's NFKD and `casefold` for every code point. The generator writes the
tables to `lib/src/authoring/layout_name_key.g.dart`, which
`lib/src/authoring/layout_name_key.dart` reads.

The hand-written runtime (`lib/src/core/wire*.dart`, `preset.dart`,
`override.dart`, `version.dart`) ports upstream's `core/_wire.py` and
`core/_preset.py`. The generator doesn't touch it.

## Updating to a new upstream release

From the package root, with a Python environment where the new release of
`creator_studio_doc_format` is installed:

```sh
python -I tool/extract_schema.py           # writes tool/schema.json
dart run tool/generate.dart                # writes the *.g.dart files in lib/
python -I tool/make_expected.py            # writes test/fixtures/expected/*.roundtrip*.json
                                           # and test/fixtures/expected/wire_cases.json
python -I tool/make_navigation_expected.py # writes test/fixtures/expected/*.navigation.json
python -I tool/make_package_cases.py       # writes test/fixtures/package/*
python -I tool/make_example_expected.py    # writes test/examples/expected/*.zip
dart analyze && dart test
```

Each `make_*.py` script runs the upstream package and writes reference data
that the Dart tests compare against, so re-run all of them whenever upstream
changes:

- `make_expected.py` runs the upstream package on the fixtures in
  `test/fixtures/` and on the differential cases in `wire_cases.py`, for
  `test/core/`.
- `make_navigation_expected.py` records the order in which upstream's
  `iterate_models` visits each fixture, for `test/navigation/`.
- `make_package_cases.py` builds well-formed, unusual, and malformed archives
  and records how upstream opens and saves each, for `test/package/`. It also
  builds compressed members and streams, intact and damaged, and records what
  `zipfile` and its decompressors make of each.
- `make_example_expected.py` runs upstream's example scripts and README quick
  start, for `test/examples/`. Port a change to an example script to its Dart
  counterpart in `example/` first. Every entry has a fixed timestamp, so a
  document comes out byte for byte the same until upstream changes it, except
  for documents with random identifiers, such as `authoring.zip`, which change
  on every run; the test normalizes them.

When a step fails or a test differs:

- If the extractor fails, upstream added something it can't classify yet (a new
  annotation, constraint, or field kind). Teach the extractor, and the generator
  if needed, rather than loosening the checks.
- If upstream changed `_wire.py` or `_preset.py`, port the change to the
  runtime by hand. The differential tests in `test/core/wire_cases_test.dart`
  show where behavior differs; add cases to `wire_cases.py` for new behavior.
- `test/core/generated_up_to_date_test.dart` fails when `models.g.dart` doesn't
  match what the generator produces from `schema.json`.
