// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python): the behavior that
// the docstrings of `Manifest` in core/package.py describe, with the
// outcomes checked against upstream.

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:test/test.dart';

void main() {
  test('the supported major is 1', () {
    expect(supportedPackageMajor, 1);
  });

  test('parse reads the version that a manifest spells', () {
    for (final (input, version) in <(Object?, String?)>[
      (null, null),
      ([1], null),
      (<String, Object?>{}, null),
      ({'package_version': null}, null),
      ({'package_version': 1.5}, '1.5'),
      ({'package_version': 1}, '1'),
      (
        {
          'package_version': {'major': 1, 'minor': 2},
        },
        '1.2',
      ),
      (
        {
          'package_version': {'major': 1.5},
        },
        null,
      ),
      ({'package_version': true}, null),
      ({'package_version': 'banana'}, 'banana'),
      ({'package_version': 1e16}, '1e+16'),
      ({'package_version': '01.5'}, '01.5'),
      ({'package_version': BigInt.parse('-1${'0' * 20}')}, '-1${'0' * 20}'),
    ]) {
      expect(Manifest.parse(input).packageVersion, version, reason: '$input');
    }
  });

  test('parse rejects a newer major as a version error', () {
    for (final (input, spelled) in [
      ({'package_version': '2.0'}, "'2.0' (major 2)"),
      ({'package_version': '2'}, "'2' (major 2)"),
      ({'package_version': 2}, "'2' (major 2)"),
      ({'package_version': 2.5}, "'2.5' (major 2)"),
      (
        {
          'package_version': {'major': 3, 'minor': null},
        },
        "'3.0' (major 3)",
      ),
      (
        {'package_version': BigInt.parse('1${'0' * 20}')},
        "'1${'0' * 20}' (major 1${'0' * 20})",
      ),
      (
        {'package_version': '1${'0' * 20}.5'},
        "'1${'0' * 20}.5' (major 1${'0' * 20})",
      ),
    ]) {
      expect(
        () => Manifest.parse(input),
        throwsA(
          isA<DocumentVersionError>().having(
            (e) => e.message,
            'message',
            '`package_version` $spelled exceeds supported major 1. Update '
                'this library to a newer version to read it.',
          ),
        ),
      );
    }
  });

  test('the constructor rejects a newer major', () {
    expect(
      () => Manifest(packageVersion: '2.0'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          "`package_version` '2.0' (major 2) exceeds supported major 1",
        ),
      ),
    );
    expect(Manifest(packageVersion: 'banana').packageVersion, 'banana');
    expect(Manifest().packageVersion, isNull);
  });

  test('toJson always writes the supported version', () {
    expect(Manifest(packageVersion: '1.9').toJson(), {
      'package_version': '1.0',
    });
    expect(Manifest().toJson(), {'package_version': '1.0'});
  });

  test('the version stays assignable, as upstream', () {
    final manifest = Manifest()..packageVersion = '7.0';
    expect(manifest.packageVersion, '7.0');
    expect(manifest.toJson(), {'package_version': '1.0'});
  });
}
