// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// Creates slides from a theme's layouts, and fills in their text and image
/// placeholders.
///
/// Each placeholder has a name that identifies it within a slide layout. A
/// text placeholder takes text, an image placeholder takes an image, and a
/// movie or audio placeholder has no setter.
library;

export 'src/authoring/slide_layout_refs.dart'
    show layoutNameKey, resolveSlideLayout;
export 'src/authoring/slide_layouts.dart'
    show
        LayoutPlaceholderSummary,
        setSlidePlaceholderImage,
        setSlidePlaceholderText,
        slideFromLayout,
        summarizeSlideLayouts;
