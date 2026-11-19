// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// Returns the path of the field [key] of the model at [path].
String extendPath(String path, String key) => path.isEmpty ? key : '$path.$key';
