// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

/// Runs the example scripts and the guide's snippets as a user does, and
/// checks the documents they write.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:creator_studio_document/validation.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The package root, which `dart test` runs in.
final String packageRoot = Directory.current.path;

/// Runs the Dart script at [script], relative to the package root, with
/// [args] in [workingDirectory].
Future<ProcessResult> runScript(
  String script,
  List<String> args, {
  required String workingDirectory,
}) => Process.run(
  Platform.resolvedExecutable,
  [p.join(packageRoot, script), ...args],
  workingDirectory: workingDirectory,
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

/// Matches a [ProcessResult] that exited with code 0.
final Matcher succeeded = isA<ProcessResult>().having(
  (r) => r.exitCode,
  'exitCode',
  0,
);

/// The lines that a process wrote to standard output.
List<String> outputLines(ProcessResult result) =>
    const LineSplitter().convert(result.stdout as String);

/// The entries of the ZIP archive [bytes], by name.
Map<String, Uint8List> zipEntries(List<int> bytes) => {
  for (final file in ZipDecoder().decodeBytes(bytes).files)
    if (file.isFile) file.name: file.content,
};

/// Checks that the document at [path] passes `validateDocument` and comes
/// back unchanged from being encoded and decoded again, and returns it.
///
/// The JSON entries that the document encodes to must be the bytes the file
/// holds, and decoding them again must give the same document.
KeyxDocument expectValidRoundTrip(String path) {
  final doc = KeyxDocument.open(path);
  expect(() => validateDocument(doc), returnsNormally);

  final written = zipEntries(File(path).readAsBytesSync());
  final bytes = doc.toBytes();
  final encoded = zipEntries(bytes);
  expect(encoded.keys.toSet(), written.keys.toSet());
  for (final MapEntry(key: name, value: data) in written.entries) {
    expect(encoded[name], data, reason: '$name of $path');
  }

  final again = KeyxDocument.fromBytes(bytes);
  expect(again.presentation, doc.presentation);
  expect(sameJson(again.toMainJson(), doc.toMainJson()), isTrue);
  expect(
    [for (final preset in again.presets) preset.toJson()],
    [for (final preset in doc.presets) preset.toJson()],
  );
  expect(again.resources.keys.toSet(), doc.resources.keys.toSet());
  return doc;
}

/// Creates a temporary directory that is deleted after the current test.
String tempDir() {
  final dir = Directory.systemTemp.createTempSync('csd_examples_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir.path;
}

/// Copies the example fixture [name] to [dir] as [as].
void copyFixture(String name, String dir, {String? as}) =>
    File(p.join(packageRoot, 'example', 'fixtures', name))
        .copySync(p.join(dir, as ?? name));
