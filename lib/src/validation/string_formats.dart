// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

import 'package:creator_studio_document/src/core/models.g.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/navigation/navigation.dart';
import 'package:creator_studio_document/src/validation/errors.dart';
import 'package:creator_studio_document/src/validation/model_tree.dart';
import 'package:creator_studio_document/src/validation/paths.dart';
import 'package:creator_studio_document/src/validation/py_text.dart';
import 'package:creator_studio_document/src/validation/url_parse.dart';

const _base64PreviewLen = 40;

/// The string fields whose format the validator checks, by model.
const stringFormatFields = <String, List<String>>{
  'BezierPath': ['path'],
  'InstantAlphaPath': ['path'],
  'CurrencyFormat': ['currency_code'],
  'NumberFormatData': ['currency_code'],
  'KeynoteTheme': ['locale'],
  'Hyperlink': ['url', 'file'],
  'Base64EncodedResource': ['string', 'filename'],
};

/// Checks the strings that hold a format of their own: SVG path data,
/// currency codes, locales, URLs, file names, and Base64.
final class StringFormatValidator() implements ModelTreeValidator {
  /// Creates the validator.
  this;

  @override
  void visit(IterationState state, IteratedModel iterated) {
    final path = iterated.path;
    switch (iterated.model) {
      case final BezierPath m:
        _rejectBadSvgPath(m.path, path, 'BezierPath');
      case final InstantAlphaPath m:
        _rejectBadSvgPath(m.path, path, 'InstantAlphaPath');
      case final CurrencyFormat m:
        _rejectBadIso4217(m.currencyCode, path, 'CurrencyFormat');
      case NumberFormatData(:final currencyCode?):
        _rejectBadIso4217(currencyCode, path, 'NumberFormatData');
      case KeynoteTheme(:final locale?):
        _rejectBadBcp47(locale, path);
      case final Hyperlink m:
        if (m.url case final url?) {
          _rejectBadUrl(url, path);
        }
        if (m.file case final file?) {
          rejectEmpty(file, path, 'file', cls: 'Hyperlink');
        }
      case final Base64EncodedResource m:
        _rejectBadBase64(m.string, path);
        rejectEmpty(m.filename, path, 'filename', cls: 'Base64EncodedResource');
    }
  }

  @override
  void finalize(IterationState state) {}
}

const _svgCommands = 'MmLlHhVvCcSsQqTtAaZz';
const _svgOther = '0123456789.,-+eE';

// `^(?=.*[MmLl…Zz])[\sMmLl…Zz0-9.,\-+eE]+$`, matched in full: every
// character is whitespace, a command letter, or part of a number, and a
// command letter comes before the first newline, which `.` doesn't cross.
bool _isSvgPathData(String value) {
  var sawCommand = false;
  var beforeNewline = true;
  for (final c in value.runes) {
    final isCommand = _svgCommands.codeUnits.contains(c);
    if (!isCommand && !_svgOther.codeUnits.contains(c) && !pyIsSpace(c)) {
      return false;
    }
    if (c == 0x0a) {
      beforeNewline = false;
    }
    if (isCommand && beforeNewline) {
      sawCommand = true;
    }
  }
  return sawCommand;
}

void _rejectBadSvgPath(String value, String modelPath, String cls) {
  final where = extendPath(modelPath, 'path');
  if (pyIsBlank(value)) {
    throw DocumentValueError(
      '`$cls.path` ${pyStringRepr(value)} is empty or blank (at $where)',
    );
  }
  if (!_isSvgPathData(value)) {
    throw DocumentValueError(
      "`$cls.path` ${pyStringRepr(value)} isn't SVG path data (at $where). "
      "Use the syntax of an SVG `<path>` element's `d` attribute.",
    );
  }
}

bool _isUpper(int c) => c >= 0x41 && c <= 0x5a;

void _rejectBadIso4217(String value, String modelPath, String cls) {
  if (value.length != 3 || !value.codeUnits.every(_isUpper)) {
    throw DocumentValueError(
      "`$cls.currency_code` ${pyStringRepr(value)} isn't three uppercase "
      "letters (at ${extendPath(modelPath, 'currency_code')}). Use a code "
      "such as 'USD' or 'EUR'.",
    );
  }
}

bool _isAsciiAlpha(int c) =>
    (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);

bool _isAsciiAlnum(int c) => _isAsciiAlpha(c) || (c >= 0x30 && c <= 0x39);

// `^[A-Za-z][A-Za-z0-9_\-@=.;]*$`, matched in full.
bool _isLocale(String value) =>
    value.isNotEmpty &&
    _isAsciiAlpha(value.codeUnitAt(0)) &&
    value.codeUnits.every(
      (c) => _isAsciiAlnum(c) || '_-@=.;'.codeUnits.contains(c),
    );

void _rejectBadBcp47(String value, String modelPath) {
  if (!_isLocale(value)) {
    throw DocumentValueError(
      "`KeynoteTheme.locale` ${pyStringRepr(value)} isn't a locale identifier "
      "(at ${extendPath(modelPath, 'locale')}). Use a value such as 'en_US'.",
    );
  }
}

void _rejectBadUrl(String value, String modelPath) {
  final where = extendPath(modelPath, 'url');
  if (pyIsBlank(value)) {
    throw DocumentValueError(
      '`Hyperlink.url` ${pyStringRepr(value)} is empty or blank (at $where)',
    );
  }
  final String scheme;
  try {
    scheme = pyUrlScheme(value);
  } on PyUrlError catch (e) {
    throw DocumentValueError(
      "`Hyperlink.url` ${pyStringRepr(value)} isn't a URL (at $where). "
      '${e.message}.',
      cause: e,
    );
  }
  if (scheme == 'file') {
    throw DocumentValueError(
      "`Hyperlink.url` ${pyStringRepr(value)} has a 'file:' scheme (at "
      '$where). Use `Hyperlink.file` instead.',
    );
  }
}

/// Throws [DocumentValueError] if [value], the field [field] of the model
/// [cls] at [modelPath], is empty or only whitespace.
void rejectEmpty(
  String value,
  String modelPath,
  String field, {
  required String cls,
}) {
  if (pyIsBlank(value)) {
    throw DocumentValueError(
      '`$cls.$field` ${pyStringRepr(value)} is empty or blank '
      '(at ${extendPath(modelPath, field)})',
    );
  }
}

bool _isBase64Char(int c) =>
    _isAsciiAlnum(c) || c == 0x2b /* + */ || c == 0x2f /* / */;

// `^[A-Za-z0-9+/]+={0,2}$`, matched in full.
bool _isBase64(String s) {
  var end = s.length;
  while (end > 0 && s.length - end < 2 && s.codeUnitAt(end - 1) == 0x3d) {
    end--;
  }
  return end > 0 && s.codeUnits.take(end).every(_isBase64Char);
}

void _rejectBadBase64(String value, String modelPath) {
  final where = extendPath(modelPath, 'string');
  final stripped = pyRemoveSpace(value);
  if (stripped.isEmpty) {
    throw DocumentValueError(
      '`Base64EncodedResource.string` ${pyStringRepr(value)} is empty or '
      'blank (at $where)',
    );
  }
  if (pyLength(stripped) % 4 != 0 || !_isBase64(stripped)) {
    final preview = pyShorten(value, _base64PreviewLen);
    throw DocumentValueError(
      "`Base64EncodedResource.string` ${pyStringRepr(preview)} isn't valid "
      "Base64 (at $where). Use letters, digits, '+' and '/', padded with '=' "
      'to a multiple of 4 characters.',
    );
  }
}
