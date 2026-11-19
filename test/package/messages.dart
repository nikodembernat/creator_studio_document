// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

/// Whether [actual] is upstream's [expected] message.
///
/// macOS's zlib reports a bad code in its fast decoding loop as `invalid
/// literal/length/distance code`, where zlib itself, and the port, says
/// `invalid literal/length code` or `invalid distance code`.
bool sameMessage(String actual, String expected) {
  const merged = 'invalid literal/length/distance code';
  if (!expected.contains(merged)) {
    return actual == expected;
  }
  return actual ==
          expected.replaceFirst(merged, 'invalid literal/length code') ||
      actual == expected.replaceFirst(merged, 'invalid distance code');
}
