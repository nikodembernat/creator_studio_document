// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

// Generates lib/src/core/models.g.dart, lib/src/core/py_repr.g.dart,
// lib/src/core/resources_nfc.g.dart, and
// lib/src/authoring/layout_name_key.g.dart from tool/schema.json.
//
// Run from the package root: `dart run tool/generate.dart`.

import 'dart:convert';
import 'dart:io';

import 'src/generator.dart';

Future<void> main() async {
  final schema = jsonDecode(File('tool/schema.json').readAsStringSync());
  final files = generate((schema as Map).cast<String, Object?>());
  for (final MapEntry(:key, :value) in files.entries) {
    File(key)
      ..createSync(recursive: true)
      ..writeAsStringSync(value);
  }
  final result = await Process.run('dart', ['format', ...files.keys]);
  if (result.exitCode != 0) {
    stderr
      ..write(result.stdout)
      ..write(result.stderr);
    exitCode = result.exitCode;
    return;
  }
  stdout.writeln('Generated ${files.keys.join(', ')}.');
}
