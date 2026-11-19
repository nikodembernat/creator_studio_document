// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// How a slide's `layout` reference finds its slide layout.
library;

import 'package:creator_studio_document/src/authoring/layout_name_key.dart';
import 'package:creator_studio_document/src/core/models.g.dart';
import 'package:creator_studio_document/src/core/resources_nfc.dart';

/// Returns the layout that [ref] names, as Keynote resolves a slide's
/// `layout`, or `null` if none matches.
///
/// A layout whose identifier is [ref] wins. Otherwise the first layout whose
/// name matches [ref] by [layoutNameKey] does.
SlideLayout? resolveSlideLayout(Iterable<SlideLayout> layouts, String ref) {
  final all = layouts.toList();
  for (final layout in all) {
    if (layout.identifier == ref) {
      return layout;
    }
  }
  final key = layoutNameKey(ref);
  for (final layout in all) {
    if (layoutNameKey(layout.name) == key) {
      return layout;
    }
  }
  return null;
}

/// Returns the key under which Keynote matches the layout name [name].
///
/// Two names match when their keys are equal. The key ignores case and
/// compatibility differences, such as a ligature against its letters, and
/// treats `ı` and `i`, and `å` and `aa`, as the same.
String layoutNameKey(String name) {
  final folded = nfkd(casefold(nfkd(name))).replaceAll('ı', 'i');
  final chars = <int>[];
  var base = -1;
  for (final c in folded.runes) {
    if (combiningClass(c) == 0) {
      base = c;
    } else if (c == 0x307 && base == 0x69) {
      // The dot above that decomposing `İ` leaves on an `i`.
      continue;
    }
    chars.add(c);
  }
  return nfkc(String.fromCharCodes(chars)).replaceAll('å', 'aa');
}
