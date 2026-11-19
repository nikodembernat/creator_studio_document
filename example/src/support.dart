// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

/// The command-line plumbing that the example scripts share: where their
/// sample files are, which arguments they take, and where they write.
library;

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// The path of the sample file [name] in `example/fixtures/`.
///
/// The directory is found next to the running script, as it is for
/// `dart run example/basics.dart`, and otherwise in `example/fixtures`
/// relative to the current directory, as it is for `dart test`.
String fixture(String name) => p.join(_fixturesDir, name);

final String _fixturesDir = () {
  final script = Platform.script;
  if (script.isScheme('file')) {
    final besideScript = p.join(p.dirname(script.toFilePath()), 'fixtures');
    if (Directory(besideScript).existsSync()) {
      return besideScript;
    }
  }
  return p.join('example', 'fixtures');
}();

/// The path an example writes [name] to when no output path is given: a
/// `creator_studio_document_examples` directory in the system's temporary
/// directory.
String defaultOutput(String name) =>
    p.join(Directory.systemTemp.path, 'creator_studio_document_examples', name);

/// Returns the positional [args] of an example that takes the arguments
/// [names], filling each one that's missing from [defaults].
///
/// Returns `null` after printing a usage line built from [description] when
/// [args] asks for help with `-h`, `--help`, or a shorter prefix of `--help`
/// such as `--he`, which upstream's `argparse` accepts too. Also returns
/// `null`, printing the usage to standard error and setting `exitCode` to 64,
/// when [args] holds any other option, or more arguments than [names]. As
/// with upstream's `argparse`, an argument after `--` is positional even if
/// it starts with `-`, and `-` alone is positional.
List<String>? parseArguments(
  List<String> args, {
  required String script,
  required String description,
  required List<String> names,
  required List<String> defaults,
}) {
  final usage = [
    'Usage: dart run example/$script.dart ${[for (final n in names) '[$n]'].join(' ')}',
    '',
    description,
    '',
    for (final (i, n) in names.indexed) '  $n  defaults to ${defaults[i]}',
  ].join('\n');
  final separator = args.indexOf('--');
  final options = separator < 0 ? args : args.sublist(0, separator);
  final positional = [
    for (final a in options)
      if (a == '-' || !a.startsWith('-')) a,
    if (separator >= 0) ...args.sublist(separator + 1),
  ];
  if (options.any(_asksForHelp)) {
    stdout.writeln(usage);
    return null;
  }
  final unknown = [
    for (final a in options)
      if (a != '-' && a.startsWith('-')) a,
  ];
  if (unknown.isNotEmpty || positional.length > names.length) {
    stderr.writeln(usage);
    if (unknown.isNotEmpty) {
      stderr.writeln('\nUnrecognized arguments: ${unknown.join(' ')}');
    }
    exitCode = 64;
    return null;
  }
  return [...positional, ...defaults.skip(positional.length)];
}

// `-h`, or `--help` or a prefix of it, which `argparse` reads as `--help`
// because it accepts an unambiguous abbreviation of a long option.
bool _asksForHelp(String arg) =>
    arg == '-h' || (arg.length > 2 && '--help'.startsWith(arg));

/// Creates the directory that [path] goes in, if it doesn't exist yet.
void ensureParent(String path) =>
    Directory(p.dirname(path)).createSync(recursive: true);

/// Prints the path and size of the document saved at [path].
void reportSaved(String path) =>
    stdout.writeln('wrote $path (${File(path).lengthSync()} bytes)');

var _printingLogRecords = false;

/// Prints the message of every log record at [Level.INFO] or above, the
/// example's own and the library's warnings alike, to standard output.
///
/// Calling it again does nothing.
void printLogRecords() {
  if (_printingLogRecords) {
    return;
  }
  _printingLogRecords = true;
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) => stdout.writeln(record.message));
}
