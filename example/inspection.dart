// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python):
// src/creator_studio_doc_format/examples/inspection.py.

/// Prints a presentation's text, then replaces it with lorem ipsum of the
/// same length.
///
/// ```sh
/// dart run example/inspection.dart [input] [output]
/// ```
///
/// A real document can hold thousands of models, so printing a whole subtree
/// floods the output, and every model's JSON includes its `type_identifier`
/// and `version`, which buries the fields you want. [outline] prints the top
/// levels of a model's JSON with long lists and strings cut short, which
/// shows more than text, such as geometry and presets.
///
/// `iterateModels` descends through lists, groups, and unions on its own, so
/// the code names only the leaf model types. Both passes iterate over each
/// slide rather than `doc.presentation`, which also reaches the theme's
/// layouts and their placeholder text.
library;

import 'dart:convert';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/navigation.dart';
import 'package:logging/logging.dart';

import 'src/support.dart';

final _log = Logger('inspection');

const lorem =
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam '
    'fermentum vestibulum est. Cras rhoncus. Pellentesque habitant morbi '
    'tristique senectus et netus et malesuada fames ac turpis egestas. Sed '
    'quis tortor. Donec non ipsum. Mauris condimentum, odio nec porta '
    'tristique, ante neque malesuada massa, in dignissim eros velit at '
    'tellus. Donec et risus in ligula eleifend consectetur. Donec volutpat '
    'eleifend augue. Integer gravida sodales leo. Nunc vehicula neque ac '
    'erat. Vivamus non nisl. Fusce ac magna. Suspendisse euismod libero eget '
    'mauris.';

/// Returns lorem ipsum text, repeated and cut to exactly [n] characters.
String loremOfLength(int n) {
  if (n <= 0) {
    return '';
  }
  final repeats = n ~/ lorem.length + 1;
  return (lorem * repeats).substring(0, n);
}

/// Returns the JSON of [model] as indented lines, cut short so that it fits
/// on a screen.
///
/// A model that adopts a preset encodes against the document's presets, so
/// pass them as [presets].
///
/// It leaves out every `type_identifier` and `version`, shows a map or list
/// deeper than [maxDepth] as `{…}` or `[…]`, shows the first [maxLength]
/// entries of a list, and cuts a string after [maxString] characters. Lower
/// the limits until the output fits, then descend into the branch you want
/// and raise them again.
String outline(
  WireModel model,
  List<Preset> presets, {
  int maxDepth = 3,
  int maxLength = 8,
  int maxString = 80,
}) {
  final out = StringBuffer();
  void write(Object? value, int depth, String indent) {
    switch (value) {
      case final Map<String, Object?> map:
        final entries = [
          for (final e in map.entries)
            if (e.key != 'type_identifier' && e.key != 'version') e,
        ];
        if (entries.isEmpty) {
          out.write(' {}');
        } else if (depth >= maxDepth) {
          out.write(' {…}');
        } else {
          for (final MapEntry(:key, :value) in entries) {
            out.write('\n$indent  $key:');
            write(value, depth + 1, '$indent  ');
          }
        }
      case final List<Object?> list:
        if (list.isEmpty) {
          out.write(' []');
        } else if (depth >= maxDepth) {
          out.write(' […] (${list.length} items)');
        } else {
          for (final (i, item) in list.take(maxLength).indexed) {
            out.write('\n$indent  [$i]');
            write(item, depth + 1, '$indent  ');
          }
          if (list.length > maxLength) {
            out.write('\n$indent  … (${list.length - maxLength} more)');
          }
        }
      case final String string when string.length > maxString:
        out.write(' ${jsonEncode(string.substring(0, maxString))}…');
      default:
        out.write(' ${jsonEncode(value)}');
    }
  }

  write(model.toJson(WireContext(presets: PresetRegistry(presets))), 0, '');
  return '${model.runtimeType}:$out';
}

/// Returns whether [item] is inside a locked slide object or a title
/// placeholder.
bool _inProtectedSubtree(IteratedModel item) {
  for (final a in item.ancestors) {
    if (a is! SlideObject) {
      continue;
    }
    if (a.isLocked) {
      return true;
    }
    if (a.placeholderInfo?.defined?.kind ==
        SlideObjectPlaceholderInfoPlaceholderDefinitionKind.title) {
      return true;
    }
  }
  return false;
}

/// Logs every primary text string without changing the document.
///
/// Skips the display text of hyperlinks.
void printTexts(KeyxDocument doc) {
  for (final slide in doc.presentation.slides) {
    for (final item in iterateModels(slide)) {
      final string = switch (item.model) {
        TextRun() when item.ancestors.any((a) => a is HyperlinkField) => null,
        TextRun(:final string) => string,
        Text(:final string) => string,
        _ => null,
      };
      if (string != null && string.isNotEmpty) {
        _log.info('  ${jsonEncode(string)}');
      }
    }
  }
}

/// Replaces each slide's text with lorem ipsum, in place.
///
/// Locked objects and title placeholders keep their text.
void replaceTexts(KeyxDocument doc) {
  for (final slide in doc.presentation.slides) {
    for (final item in iterateModels(slide)) {
      if (_inProtectedSubtree(item)) {
        continue;
      }
      // The lorem ipsum has as many characters (Unicode code points) as the
      // text it replaces.
      switch (item.model) {
        case final TextRun run:
          run.string = loremOfLength(run.string.runes.length);
        case Text(string: final string?) && final text:
          text.string = loremOfLength(string.runes.length);
      }
    }
  }
}

void main(List<String> args) {
  printLogRecords();
  final parsed = parseArguments(
    args,
    script: 'inspection',
    description:
        "Prints a presentation's text, then replaces it with lorem ipsum of "
        'the same length.',
    names: ['input', 'output'],
    defaults: [fixture('sample.keyx'), defaultOutput('replaced.keyx')],
  );
  if (parsed == null) {
    return;
  }
  final [input, output] = parsed;

  final doc = KeyxDocument.open(input);
  _log
    ..info('The first slide, two levels deep:')
    ..info(outline(doc.presentation.slides.first, doc.presets, maxDepth: 2))
    ..info('Before:');
  printTexts(doc);
  replaceTexts(doc);
  _log.info('After:');
  printTexts(doc);
  ensureParent(output);
  doc.save(output);
  _log.info('Wrote $output');
}
