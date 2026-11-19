// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:creator_studio_document/src/authoring/slide_layout_refs.dart';
import 'package:creator_studio_document/src/core/models.g.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/navigation/navigation.dart';
import 'package:creator_studio_document/src/validation/errors.dart';
import 'package:creator_studio_document/src/validation/identifiers.dart';
import 'package:creator_studio_document/src/validation/model_tree.dart';
import 'package:creator_studio_document/src/validation/py_text.dart';

/// Checks slide and slide layout identifiers, placeholder kinds, slide
/// targets, and the layout that each slide names.
final class SlideValidator() implements ModelTreeValidator {
  /// Creates the validator.
  this;

  @override
  void visit(IterationState state, IteratedModel iterated) {
    final path = iterated.path;
    switch (iterated.model) {
      case final Slide slide:
        _registerSlide(state, slide, path);
        _deferLayoutRef(state, slide, path);
        _validatePlaceholderKinds(slide.contents, path);
      case final SlideLayout layout:
        _registerSlideLayout(state, layout, path);
        _validatePlaceholderKinds(layout.contents, path);
      case final SlideTarget target:
        _deferSlideTarget(state, target, path);
    }
  }

  @override
  void finalize(IterationState state) {
    _resolveSlideTargets(state);
    _resolveLayoutRefs(state);
  }
}

void _registerSlide(IterationState state, Slide slide, String path) {
  if (slide.identifier case final identifier?) {
    claimUnique(state.slideIds, identifier, path, 'Slide.identifier');
  }
}

void _registerSlideLayout(
  IterationState state,
  SlideLayout layout,
  String path,
) {
  state.slideLayoutNames.putIfAbsent(
    layoutNameKey(layout.name),
    () => layout.name,
  );
  if (layout.identifier case final identifier?) {
    claimUnique(
      state.slideLayoutIds,
      identifier,
      path,
      'SlideLayout.identifier',
    );
  }
}

void _validatePlaceholderKinds(List<SlideObject>? contents, String path) {
  if (contents == null) {
    return;
  }
  final seenKinds = <String, String>{};
  for (var index = 0; index < contents.length; index++) {
    final defined = contents[index].placeholderInfo?.defined;
    if (defined == null) {
      continue;
    }
    claimUnique(
      seenKinds,
      defined.kind.wireValue,
      '$path.contents[$index].placeholder_info.defined.kind',
      'PlaceholderDefinition.kind',
    );
  }
}

void _deferSlideTarget(IterationState state, SlideTarget target, String path) {
  if (target.byIdentifier case final slideId?) {
    state.pendingSlideTargets.add(PendingSlideTarget(path, slideId));
  }
}

void _deferLayoutRef(IterationState state, Slide slide, String path) {
  if (slide.layout case final layout?) {
    state.pendingLayoutRefs.add(PendingLayoutRef(path, layout));
  }
}

void _resolveSlideTargets(IterationState state) {
  for (final pending in state.pendingSlideTargets) {
    if (!state.slideIds.containsKey(pending.slideId)) {
      throw DocumentReferenceError(
        '`SlideTarget.by_identifier` ${pyStringRepr(pending.slideId)} '
        'matches no `Slide.identifier` (at ${pending.path}.by_identifier)',
      );
    }
  }
}

String _asciiSkeleton(String key) =>
    String.fromCharCodes(key.codeUnits.where((c) => c < 0x80));

void _resolveLayoutRefs(IterationState state) {
  if (state.slideLayoutNames.isEmpty) {
    return;
  }
  final nonAsciiSkeletons = {
    for (final key in state.slideLayoutNames.keys)
      if (!pyIsAscii(key)) _asciiSkeleton(key),
  };
  for (final pending in state.pendingLayoutRefs) {
    final layout = pending.layout;
    if (state.slideLayoutIds.containsKey(layout)) {
      continue;
    }
    final key = layoutNameKey(layout);
    if (state.slideLayoutNames.containsKey(key) ||
        (!pyIsAscii(layout) &&
            nonAsciiSkeletons.contains(_asciiSkeleton(key)))) {
      continue;
    }
    throw DocumentReferenceError(
      '`Slide.layout` ${pyStringRepr(layout)} matches no `SlideLayout` (at '
      "${pending.path}.layout). The theme's slide layout names are "
      '${pySortedRepr(state.slideLayoutNames.values)}.',
    );
  }
}
