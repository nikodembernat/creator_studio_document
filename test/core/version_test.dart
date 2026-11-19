// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python): tests/test_version.py,
// plus the `Version` behavior of core/_wire.py.

import 'dart:io';

import 'package:creator_studio_document/creator_studio_document.dart';
import 'package:test/test.dart';

void main() {
  test('packageVersion matches pubspec.yaml', () {
    final declared = RegExp(
      r'^version: (\S+)$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(declared, isNotNull);
    expect(packageVersion, declared!.group(1));
  });

  group('Version.parse', () {
    // Each expectation was checked against the upstream `Version.parse`.
    const cases = <(Object?, String?)>[
      ('1', '1.0'),
      ('1.2', '1.2'),
      ('01.002', '1.2'),
      (' 1.0', null),
      ('1.0 ', null),
      ('1.2.3', null),
      ('-1', null),
      ('', null),
      ('1.', null),
      ('.1', null),
      ('١', null),
      ({'major': 1}, '1.0'),
      ({'major': 1, 'minor': null}, '1.0'),
      ({'major': true}, null),
      ({'major': -1}, null),
      ({'major': 1.0}, null),
      ({'major': 2, 'minor': 3}, '2.3'),
      ({'minor': 1}, null),
      ({'major': 1, 'minor': -1}, null),
      ({'major': 1, 'minor': false}, null),
      (true, null),
      (1, null),
      (null, null),
      (1.5, null),
      ([1, 0], null),
    ];
    for (final (input, expected) in cases) {
      test('$input', () {
        expect(Version.parse(input)?.toString(), expected);
      });
    }

    test('returns a Version unchanged', () {
      const v = Version(4, 2);
      expect(identical(Version.parse(v), v), isTrue);
    });
  });

  test('orders, compares, and prints versions', () {
    expect(const Version(1, 2) < const Version(1, 10), isTrue);
    expect(const Version(2) > const Version(1, 99), isTrue);
    expect(const Version(1) <= const Version(1), isTrue);
    expect(const Version(1, 1) >= const Version(1, 2), isFalse);
    expect('${const Version(3)}', '3.0');
    expect(const Version(1), Version.parse('1.0'));
    expect(const Version(1).hashCode, Version.parse('1.0').hashCode);
    expect([const Version(2), const Version(1, 5), const Version(1)]..sort(), [
      const Version(1),
      const Version(1, 5),
      const Version(2),
    ]);
  });

  group('version gating', () {
    test('a newer major version throws DocumentVersionError', () {
      expect(
        () => Size.fromJson({'width': 1, 'height': 2, 'version': '2.0'}),
        throwsA(
          isA<DocumentVersionError>().having(
            (e) => e.message,
            'message',
            'Size: input declares version 2.0 but this library implements '
                '1.x. Update this library to a newer version to read it.',
          ),
        ),
      );
    });

    test('keys newer than the declared version decode as absent', () {
      final resource = IndirectResource.fromJson({
        'filename': 'a.png',
        'version': '1.0',
        'premium_resource_info': {
          'asset_uuid': 'u',
          'is_derived_asset': false,
          'may_need_watermark': true,
        },
      });
      expect(resource.premiumResourceInfo, isNull);
      expect(resource.toJson()['version'], '1.0');
    });

    test('an optional field raises the written version', () {
      final resource = IndirectResource(
        filename: 'a.png',
        premiumResourceInfo: PremiumResourceInfo(
          assetUuid: 'u',
          isDerivedAsset: false,
          mayNeedWatermark: false,
        ),
      );
      expect(resource.toJson()['version'], '2.0');
      resource.premiumResourceInfo = null;
      expect(resource.toJson()['version'], '1.0');
    });

    test('a defaulted field newer than 1.0 sets the base version', () {
      expect(RGBA().toJson()['version'], '1.1');
    });

    test('a decoded newer minor version with unknown keys is a floor', () {
      final size = Size.fromJson({
        'width': 1,
        'height': 2,
        'version': '1.7',
        'depth': 3,
      });
      expect(size.toJson()['version'], '1.7');
      final copy = size.deepCopy();
      expect(copy.toJson()['version'], '1.7');
      copy.width = 5;
      expect(copy.toJson()['version'], '1.0');
      expect(size.toJson()['version'], '1.7');
    });
  });
}
