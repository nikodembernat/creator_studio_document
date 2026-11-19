// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0

/// Turns `tool/schema.json` into the Dart source of the generated models.
///
/// Naming rules, applied deterministically:
///
/// - Classes and enums keep their upstream names.
/// - Fields, union cases, and enum members use the lowerCamelCase of their
///   wire key or wire value (`aspect_ratio_locked` → `aspectRatioLocked`).
/// - A name that is a Dart reserved word, or that collides with a member the
///   runtime base classes declare, gets a trailing underscore (`default` →
///   `default_`).
/// - The typed case of a union `U` with case `c` is `U<Pascal(c)>Case`, under
///   the sealed class `UCase`.
///
/// The output is unformatted; `tool/generate.dart` runs `dart format` on it.
library;

import 'dart:convert';

/// The files [generate] writes, relative to the package root.
const modelsPath = 'lib/src/core/models.g.dart';

/// The table of code points that Python's `repr` escapes.
const pyReprPath = 'lib/src/core/py_repr.g.dart';

/// The tables that NFC normalization reads.
const nfcPath = 'lib/src/core/resources_nfc.g.dart';

/// The tables that the slide layout name key reads, beyond NFC's.
const layoutNameKeyPath = 'lib/src/authoring/layout_name_key.g.dart';

/// Thrown when the schema contains something the generator can't express.
class GeneratorError(final String message) implements Exception {
  /// Creates the error.
  this;

  @override
  String toString() => 'GeneratorError: $message';
}

const _reserved = {
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', //
  'default', 'do', 'else', 'enum', 'extends', 'false', 'final', 'finally',
  'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super',
  'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with',
};

const _modelMembers = {
  'deepCopy', 'designate', 'extras', 'fieldsSet', 'fromJson', //
  'hashCode', 'noSuchMethod', 'presetIdentifier', 'runtimeType', 'schema',
  'toJson', 'toString', 'unionCaseEntries', 'unionCases', 'unionOf',
  'unionPrimary', 'unionPrimaryName', 'wireCase', 'wireGet', 'wireSchema',
  'wireSet',
};

const _enumMembers = {
  'hashCode', 'index', 'name', 'noSuchMethod', 'runtimeType', 'toString', //
  'values', 'wireValue',
};

String _camel(String wire) {
  final parts = wire.split('_').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) {
    throw GeneratorError('empty name ${jsonEncode(wire)}');
  }
  final head = parts.first;
  final first = head[0].toLowerCase() + head.substring(1);
  final name = first + parts.skip(1).map(_capitalize).join();
  if (!RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(name)) {
    throw GeneratorError('no Dart name for ${jsonEncode(wire)}');
  }
  return name;
}

String _capitalize(String s) => s[0].toUpperCase() + s.substring(1);

String _memberName(String wire) {
  final name = _camel(wire);
  return _reserved.contains(name) || _modelMembers.contains(name)
      ? '${name}_'
      : name;
}

String _enumMemberName(String wire) {
  final name = _camel(wire);
  return _reserved.contains(name) || _enumMembers.contains(name)
      ? '${name}_'
      : name;
}

String _str(String s) {
  final escaped = s
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}

Map<String, Object?> _map(Object? v) => (v! as Map).cast<String, Object?>();

List<Map<String, Object?>> _maps(Object? v) => [
  for (final e in v! as List) _map(e),
];

String _version(Object? v) {
  final parts = (v! as List).cast<int>();
  return parts[1] == 0
      ? 'const Version(${parts[0]})'
      : 'const Version(${parts[0]}, ${parts[1]})';
}

String _versionString(String v) {
  final parts = v.split('.');
  return _version([int.parse(parts[0]), int.parse(parts[1])]);
}

// ---------------------------------------------------------------------------
// Doc comments
// ---------------------------------------------------------------------------

final _codeSpan = RegExp('`[^`]*`');
final _bareBrackets = RegExp(r'\[([^\]]*)\](?!\()');

// Escapes text that dartdoc would read as a reference or HTML.
String _escapeDocLine(String line) {
  final out = StringBuffer();
  var last = 0;
  for (final m in _codeSpan.allMatches(line)) {
    out
      ..write(_escapeProse(line.substring(last, m.start)))
      ..write(m.group(0));
    last = m.end;
  }
  out.write(_escapeProse(line.substring(last)));
  return out.toString();
}

String _escapeProse(String text) => text
    .replaceAllMapped(_bareBrackets, (m) => '\\[${m.group(1)}\\]')
    .replaceAll('<', r'\<')
    .replaceAll('>', r'\>');

List<String> _wrap(String line, int width) {
  final indent = RegExp(r'^(\s*(?:[-*] )?)').firstMatch(line)!.group(1)!;
  final hanging = ' ' * indent.length;
  final words = line.substring(indent.length).split(' ');
  final lines = <String>[];
  var current = indent;
  var empty = true;
  for (final word in words) {
    if (!empty && current.length + 1 + word.length > width) {
      lines.add(current);
      current = hanging + word;
    } else {
      current = empty ? current + word : '$current $word';
    }
    empty = false;
  }
  lines.add(current);
  return lines;
}

String _doc(String text, {String indent = '', String? fallback}) {
  final source = text.trim().isEmpty ? (fallback ?? '') : text.trim();
  if (source.isEmpty) {
    return '';
  }
  final width = 80 - indent.length - 4;
  final out = StringBuffer();
  for (final line in source.split('\n')) {
    if (line.trim().isEmpty) {
      out.write('$indent///\n');
      continue;
    }
    for (final wrapped in _wrap(_escapeDocLine(line.trimRight()), width)) {
      out.write('$indent/// $wrapped\n');
    }
  }
  return out.toString();
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

final class _Types(
  final Map<String, Map<String, Object?>> models,
  final Map<String, Map<String, Object?>> enums,
) {
  /// The Dart type of a type tree.
  String dart(Map<String, Object?> t) => switch (t['kind']) {
    'bool' || 'literal_true' => 'bool',
    'int' => 'int',
    'float' => 'double',
    'str' => 'String',
    'enum' => _named(t, enums),
    'model' => _named(t, models),
    'list' => 'List<${dart(_map(t['of']))}>',
    'nullable' => '${dart(_map(t['of']))}?',
    'override' => 'Override<${dart(_map(t['of']))}>',
    final kind => throw GeneratorError('unknown type kind $kind'),
  };

  String _named(Map<String, Object?> t, Map<String, Object?> known) {
    final name = t['name']! as String;
    if (!known.containsKey(name)) {
      throw GeneratorError('unknown ${t['kind']} $name');
    }
    return name;
  }

  /// Whether the `WireType` expression of a type tree can be `const`.
  bool isConst(Map<String, Object?> t) => switch (t['kind']) {
    'model' => false,
    'list' || 'nullable' || 'override' => isConst(_map(t['of'])),
    _ => true,
  };

  /// The `WireType` expression of a type tree, without a `const` keyword.
  String wire(Map<String, Object?> t) => switch (t['kind']) {
    'bool' => 'BoolType()',
    'int' => 'IntType()',
    'float' => 'FloatType()',
    'str' => 'StringType()',
    'literal_true' => 'LiteralTrueType()',
    'enum' =>
      "EnumType('${_named(t, enums)}', ${t['name']}.values"
          "${t['strict'] == false ? ', strict: false' : ''})",
    'model' => 'ModelType(() => ${_named(t, models)}.schema)',
    'list' => 'ListType<${dart(_map(t['of']))}>(${wire(_map(t['of']))})',
    'nullable' => 'NullableType(${wire(_map(t['of']))})',
    'override' =>
      'OverrideType<${dart(_map(t['of']))}>(${wire(_map(t['of']))})',
    final kind => throw GeneratorError('unknown type kind $kind'),
  };

  String wireExpr(Map<String, Object?> t) =>
      isConst(t) ? 'const ${wire(t)}' : wire(t);

  /// A Dart expression for the JSON value [json] decoded as [t].
  ///
  /// An int where [t] is a float is only allowed where [intDefault] can mark
  /// it, so [allowInt] is true only for a field's own default.
  String value(Map<String, Object?> t, Object? json, {bool allowInt = false}) {
    switch (t['kind']) {
      case 'bool' when json is bool:
        return '$json';
      case 'int' when json is int:
        return '$json';
      case 'float' when json is int && !allowInt:
        throw GeneratorError(
          'int default ${jsonEncode(json)} inside a float $t, which the '
          'runtime only tracks for a field default',
        );
      case 'float' when json is num:
        final d = json.toDouble();
        return d == d.truncateToDouble() && d.abs() < 1e15
            ? '${d.toInt()}.0'
            : '$d';
      case 'str' when json is String:
        return _str(json);
      case 'enum' when json is String:
        final members = _maps(enums[t['name']]!['members']);
        if (!members.any((m) => m['value'] == json)) {
          throw GeneratorError('no member $json in ${t['name']}');
        }
        return '${t['name']}.${_enumMemberName(json)}';
      case 'model':
        return '${t['name']}.fromJson(${_jsonLiteral(json)})';
      case 'list' when json is List:
        final of = _map(t['of']);
        return '<${dart(of)}>[${json.map((e) => value(of, e)).join(', ')}]';
      case 'nullable':
        return json == null ? 'null' : value(_map(t['of']), json);
      case 'override':
        if (json case {'override': 'value', 'value': final v}) {
          final of = _map(t['of']);
          return 'Override<${dart(of)}>.value('
              '${value(of, v, allowInt: allowInt)})';
        }
        return 'Override<${dart(_map(t['of']))}>.notSet()';
    }
    throw GeneratorError("default ${jsonEncode(json)} doesn't fit $t");
  }
}

/// Whether a field's default is an int where its type is a float.
///
/// Pydantic doesn't validate defaults, so the field holds that int until it's
/// set, and `_same_value` tells it from the float a setter stores.
bool intDefault(Map<String, Object?> t, Object? json) => switch (t['kind']) {
  'float' => json is int,
  'override' => switch (json) {
    {'override': 'value', 'value': final v} => intDefault(_map(t['of']), v),
    _ => false,
  },
  _ => false,
};

String _jsonLiteral(Object? json) => switch (json) {
  null => 'null',
  final bool b => '$b',
  final num n => '$n',
  final String s => _str(s),
  final List<Object?> l => '<Object?>[${l.map(_jsonLiteral).join(', ')}]',
  final Map<Object?, Object?> m =>
    '<String, Object?>{${m.entries.map((e) => '${_str('${e.key}')}: '
        '${_jsonLiteral(e.value)}').join(', ')}}',
  _ => throw GeneratorError('not JSON: $json'),
};

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

/// Returns the unformatted source of every generated file, by path.
Map<String, String> generate(Map<String, Object?> schema) {
  final models = {
    for (final m in _maps(schema['models'])) m['name']! as String: m,
  };
  final enums = {
    for (final e in _maps(schema['enums'])) e['name']! as String: e,
  };
  _checkCounts(schema, models, enums);
  final types = _Types(models, enums);
  final source = _map(schema['source']);
  final out = StringBuffer()
    ..write(_header(source))
    ..write("import 'package:creator_studio_document/src/core/errors.dart';\n")
    ..write(
      "import 'package:creator_studio_document/src/core/override.dart';\n",
    )
    ..write("import 'package:creator_studio_document/src/core/version.dart';\n")
    ..write("import 'package:creator_studio_document/src/core/wire.dart';\n\n");
  for (final name in models.keys.toList()..sort()) {
    final model = models[name]!;
    if (model['kind'] == 'object') {
      out.write(_object(model, types));
    } else if (model['kind'] == 'union') {
      out.write(_union(model, types));
    } else {
      throw GeneratorError('unknown model kind ${model['kind']}');
    }
  }
  for (final name in enums.keys.toList()..sort()) {
    out.write(_enum(enums[name]!));
  }
  out.write(_registry(models));
  return {
    modelsPath: out.toString(),
    pyReprPath: _pyRepr(source, _map(schema['python_repr'])),
    nfcPath: _nfc(source, _map(schema['python_nfc'])),
    layoutNameKeyPath: _layoutNameKey(
      source,
      _map(schema['python_layout_name_key']),
    ),
  };
}

final _hexRange = RegExp(r'^([0-9a-f]+)(?:-([0-9a-f]+))?$');

// The code points that Python's `str.isprintable` rejects, as one string of
// space-separated hex ranges, which keeps the table short.
String _pyRepr(Map<String, Object?> source, Map<String, Object?> table) {
  final ranges = (table['unprintable']! as List).cast<String>();
  var previous = -2;
  for (final r in ranges) {
    final m = _hexRange.firstMatch(r);
    final first = m == null ? null : int.parse(m[1]!, radix: 16);
    final last = m == null ? null : int.parse(m[2] ?? m[1]!, radix: 16);
    if (first == null ||
        last == null ||
        first <= previous + 1 ||
        last < first) {
      throw GeneratorError('python_repr: bad or unordered range $r');
    }
    previous = last;
  }
  if (previous > 0x10ffff) {
    throw GeneratorError('python_repr: a range ends past U+10FFFF');
  }
  final lines = <String>[];
  var line = StringBuffer();
  for (final r in ranges) {
    if (line.isNotEmpty && line.length + 1 + r.length > 70) {
      lines.add(line.toString());
      line = StringBuffer();
    }
    line.write(line.isEmpty ? r : ' $r');
  }
  lines.add(line.toString());
  final b = StringBuffer()
    ..write(_header(source))
    ..write('/// The code points that `repr` escapes in Python ')
    ..write("${table['python']}\n/// (Unicode ${table['unicode']}), ")
    ..write("because they aren't printable: inclusive\n")
    ..write('/// ranges in hex, `first-last` or a lone code point, separated ')
    ..write('by spaces.\n')
    ..write('const unprintableCodePoints =\n');
  for (var i = 0; i < lines.length; i++) {
    // Separate the adjacent literals with a space, except after the last.
    final text = i == lines.length - 1 ? lines[i] : '${lines[i]} ';
    b.write("    '$text'${i == lines.length - 1 ? ';' : ''}\n");
  }
  return b.toString();
}

final _nfcToken = RegExp(
  r'^(?:[0-9a-f]+(?:-[0-9a-f]+)?:[0-9a-f]+|[0-9a-f]+:[0-9a-f]+(?:\.[0-9a-f]+)?|[0-9a-f]+)$',
);

// The Unicode data that NFC normalization needs, as space-separated tokens:
// combining classes, one-level canonical decompositions, and the explicit
// composition exclusions.
String _nfc(Map<String, Object?> source, Map<String, Object?> table) {
  final b = StringBuffer()
    ..write(_header(source))
    ..write('// The Unicode data of Python ${table['python']} ')
    ..write("(Unicode ${table['unicode']}), which\n")
    ..write('// `resources_nfc.dart` reads. Every token is in hex.\n\n');
  for (final (key, name, doc) in const [
    (
      'combining',
      'canonicalCombiningClasses',
      'The nonzero canonical combining classes: `first-last:class` or '
          '`cp:class`.',
    ),
    (
      'decompositions',
      'canonicalDecompositions',
      'The canonical decompositions, one level deep: `cp:part` or '
          '`cp:first.second`.',
    ),
    (
      'exclusions',
      'compositionExclusions',
      'The code points whose two-part decomposition never composes, beyond '
          'those with a nonstarter in it.',
    ),
  ]) {
    final tokens = (table[key]! as List).cast<String>();
    for (final t in tokens) {
      if (!_nfcToken.hasMatch(t)) {
        throw GeneratorError('python_nfc: bad $key token $t');
      }
    }
    b
      ..write('/// $doc\n')
      ..write('const $name =\n');
    final lines = <String>[];
    var line = StringBuffer();
    for (final t in tokens) {
      if (line.isNotEmpty && line.length + 1 + t.length > 70) {
        lines.add(line.toString());
        line = StringBuffer();
      }
      line.write(line.isEmpty ? t : ' $t');
    }
    lines.add(line.toString());
    for (var i = 0; i < lines.length; i++) {
      final last = i == lines.length - 1;
      b.write("    '${last ? lines[i] : '${lines[i]} '}'${last ? ';' : ''}\n");
    }
    b.write('\n');
  }
  return '${b.toString().trimRight()}\n';
}

final _layoutNameKeyToken = RegExp(r'^[0-9a-f]+:[0-9a-f]+(?:\.[0-9a-f]+)*$');

// The Unicode data that the slide layout name key needs beyond NFC's, as
// space-separated tokens: one-level compatibility decompositions and full case
// foldings.
String _layoutNameKey(Map<String, Object?> source, Map<String, Object?> table) {
  final b = StringBuffer()
    ..write(_header(source))
    ..write('// The Unicode data of Python ${table['python']} ')
    ..write("(Unicode ${table['unicode']}), which\n")
    ..write('// `layout_name_key.dart` reads together with the NFC tables.\n')
    ..write('// Every token is in hex.\n\n');
  for (final (key, name, doc) in const [
    (
      'compatibility',
      'compatibilityDecompositions',
      'The compatibility decompositions, one level deep and without their\n'
          '/// tag: `cp:first.second...`.',
    ),
    (
      'casefold',
      'caseFoldings',
      'What `str.casefold` maps a code point to, for every code point it\n'
          '/// changes: `cp:first.second...`.',
    ),
  ]) {
    final tokens = (table[key]! as List).cast<String>();
    for (final t in tokens) {
      if (!_layoutNameKeyToken.hasMatch(t)) {
        throw GeneratorError('python_layout_name_key: bad $key token $t');
      }
    }
    b
      ..write('/// $doc\n')
      ..write('const $name =\n');
    final lines = <String>[];
    var line = StringBuffer();
    for (final t in tokens) {
      if (line.isNotEmpty && line.length + 1 + t.length > 70) {
        lines.add(line.toString());
        line = StringBuffer();
      }
      line.write(line.isEmpty ? t : ' $t');
    }
    lines.add(line.toString());
    for (var i = 0; i < lines.length; i++) {
      final last = i == lines.length - 1;
      b.write("    '${last ? lines[i] : '${lines[i]} '}'${last ? ';' : ''}\n");
    }
    b.write('\n');
  }
  return '${b.toString().trimRight()}\n';
}

void _checkCounts(
  Map<String, Object?> schema,
  Map<String, Map<String, Object?>> models,
  Map<String, Map<String, Object?>> enums,
) {
  final counts = _map(schema['counts']);
  final objects = models.values.where((m) => m['kind'] == 'object').length;
  final unions = models.values.where((m) => m['kind'] == 'union').length;
  if (counts['models'] != models.length ||
      counts['objects'] != objects ||
      counts['unions'] != unions ||
      counts['enums'] != enums.length) {
    throw GeneratorError(
      "counts ${jsonEncode(counts)} don't match the schema "
      '(${models.length} models, $objects objects, $unions unions, '
      '${enums.length} enums)',
    );
  }
  final clash = models.keys.toSet().intersection(enums.keys.toSet());
  if (clash.isNotEmpty) {
    throw GeneratorError('names used by both a model and an enum: $clash');
  }
}

String _header(Map<String, Object?> source) =>
    '''
// GENERATED CODE - DO NOT EDIT BY HAND.
//
// Generated by tool/generate.dart from tool/schema.json, which
// tool/extract_schema.py extracted from ${source['distribution']} ${source['version']}.
//
// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

''';

void _checkUnique(String owner, Iterable<String> names) {
  final seen = <String>{};
  for (final n in names) {
    if (!seen.add(n)) {
      throw GeneratorError('$owner: two members are both named $n');
    }
  }
}

String _object(Map<String, Object?> model, _Types types) {
  final name = model['name']! as String;
  final fields = _maps(model['fields']);
  _checkUnique(name, fields.map((f) => _memberName(f['name']! as String)));
  final b = StringBuffer()
    ..write(_doc(model['doc']! as String, fallback: 'The `$name` object.'))
    ..write('class $name extends ObjectModel {\n')
    ..write('  /// Creates ${_article(name)}.\n')
    ..write('  new({\n');
  for (final f in fields) {
    final member = _memberName(f['name']! as String);
    final type = types.dart(_map(f['type']));
    b.write(
      f['kind'] == 'req'
          ? '    required $type $member,\n'
          : '    ${type.endsWith('?') ? type : '$type?'} $member,\n',
    );
  }
  b
    ..write('    super.presetIdentifier,\n')
    ..write('  }) : super.construct(schema, {\n');
  for (final f in fields) {
    b.write("    '${f['name']}': ${_memberName(f['name']! as String)},\n");
  }
  b
    ..write('  });\n\n')
    ..write('  new _() : super.blank(schema);\n\n')
    ..write(_fromJsonDoc(name))
    ..write('  /// The metadata that the codec reads.\n')
    ..write('  static final ObjectSchema<$name> schema = ObjectSchema(\n')
    ..write("    name: '$name',\n")
    ..write("    typeId: ${_str(model['type_id']! as String)},\n")
    ..write('    version: ${_versionString(model['version']! as String)},\n')
    ..write('    create: $name._,\n')
    ..write('    fields: [\n');
  for (final f in fields) {
    b.write('      ${_fieldSpec(f, types)},\n');
  }
  b.write('    ],\n  );\n\n');
  for (final f in fields) {
    b.write(_accessors(f, types));
  }
  b
    ..write('  @override\n')
    ..write('  $name deepCopy() => super.deepCopy() as $name;\n')
    ..write('}\n\n');
  return b.toString();
}

String _article(String name) =>
    'AEIOU'.contains(name[0]) ? 'an [$name]' : 'a [$name]';

String _fromJsonDoc(String name) =>
    '  /// Decodes ${_article(name)} from its JSON, resolving presets through\n'
    '  /// [context].\n'
    '  ///\n'
    "  /// Throws [ModelValidationError] if the JSON doesn't match the model,\n"
    '  /// and [DocumentVersionError] if it declares a newer major version.\n'
    '  factory fromJson(Object? json, [WireContext? context]) =>\n'
    '      schema.fromJson(json, context);\n\n';

String _fieldSpec(Map<String, Object?> f, _Types types) {
  final type = _map(f['type']);
  final kind = f['kind']! as String;
  final args = <String>[
    _str(f['name']! as String),
    _version(f['version_added']),
    '.$kind',
    types.wireExpr(type),
  ];
  if (kind == 'def' || kind == 'ovrdef') {
    final json = f['default'];
    args.add('defaultValue: () => ${types.value(type, json, allowInt: true)}');
    if (intDefault(type, json)) {
      args.add('intDefault: true');
    }
  }
  if (f['preset_gate_lax'] == true) {
    args.add('presetGateLax: true');
  }
  final constraints = f['constraints'] == null ? null : _map(f['constraints']);
  for (final (key, param) in const [
    ('ge', 'ge'),
    ('le', 'le'),
    ('gt', 'gt'),
    ('lt', 'lt'),
    ('min_length', 'minLength'),
    ('max_length', 'maxLength'),
  ]) {
    if (constraints?[key] case final num v) {
      args.add('$param: $v');
    }
  }
  return 'FieldSpec(${args.join(', ')})';
}

String _accessors(Map<String, Object?> f, _Types types) {
  final wireKey = f['name']! as String;
  final member = _memberName(wireKey);
  final type = types.dart(_map(f['type']));
  final read = type.endsWith('?')
      ? "wireGet('$wireKey') as $type"
      : "wireGet('$wireKey')! as $type";
  return '${_doc(f['description']! as String, indent: '  ', fallback: 'The `$wireKey` property.')}'
      '  $type get $member => $read;\n'
      "  set $member($type value) => wireSet('$wireKey', value);\n\n";
}

String _union(Map<String, Object?> model, _Types types) {
  final name = model['name']! as String;
  final cases = _maps(model['cases']);
  _checkUnique(name, cases.map((c) => _memberName(c['name']! as String)));
  final caseBase = '${name}Case';
  String caseClass(Map<String, Object?> c) =>
      '$name${_capitalize(_camel(c['name']! as String))}Case';
  _checkUnique('$name cases', cases.map(caseClass));
  String paramType(Map<String, Object?> c) =>
      c['valueless'] == true ? 'bool' : types.dart(_map(c['type']));
  final params = StringBuffer();
  final args = StringBuffer();
  final names = StringBuffer();
  for (final c in cases) {
    final key = c['name']! as String;
    final member = _memberName(key);
    params.write('    ${paramType(c)}? $member,\n');
    names.write('      $member: $member,\n');
    args.write(
      c['valueless'] == true
          ? "    if ($member ?? false) '$key': true,\n"
          : "    '$key': $member,\n",
    );
  }
  final b = StringBuffer()
    ..write(_doc(model['doc']! as String, fallback: 'The `$name` union.'))
    ..write('class $name extends TaggedUnionModel {\n')
    ..write('  /// Creates ${_article(name)} from its cases.\n')
    ..write('  new({\n$params    super.presetIdentifier,\n')
    ..write('  }) : super.construct(schema, {\n$args')
    ..write('  });\n\n')
    ..write('  new _() : super.blank(schema);\n\n')
    ..write(
      '  /// Creates ${_article(name)} from its cases, with [primary] designated\n'
      '  /// as the case a reader acts on. A non-null [presetIdentifier] adopts\n'
      '  /// that preset, as it does in the unnamed constructor.\n'
      '  ///\n'
      '  /// Throws [ArgumentError] if [primary] names no case of the class.\n'
      '  factory unionOf(String primary, {\n$params'
      '    String? presetIdentifier,\n  }) =>\n'
      '      TaggedUnionModel.designate(schema, primary, () => $name(\n'
      '$names      presetIdentifier: presetIdentifier,\n      ));\n\n',
    )
    ..write(_fromJsonDoc(name))
    ..write('  /// The metadata that the codec reads.\n')
    ..write('  static final UnionSchema<$name> schema = UnionSchema(\n')
    ..write("    name: '$name',\n")
    ..write("    typeId: ${_str(model['type_id']! as String)},\n")
    ..write('    version: ${_versionString(model['version']! as String)},\n')
    ..write('    create: $name._,\n')
    ..write('    cases: [\n');
  for (final c in cases) {
    final type = c['valueless'] == true
        ? ''
        : ', type: ${types.wireExpr(_map(c['type']))}';
    b.write(
      '      CaseSpec(${_str(c['name']! as String)}, '
      '${_version(c['version_added'])}$type),\n',
    );
  }
  b.write('    ],\n  );\n\n');
  for (final c in cases) {
    b.write(_caseAccessors(c, types));
  }
  b
    ..write('  @override\n')
    ..write(
      '  $caseBase wireCase(String name, Object payload) => switch (name) {\n',
    );
  for (final c in cases) {
    final key = c['name']! as String;
    b.write(
      c['valueless'] == true
          ? "    '$key' => const ${caseClass(c)}(),\n"
          : "    '$key' => ${caseClass(c)}(payload as ${paramType(c)}),\n",
    );
  }
  b
    ..write(
      "    _ => throw ArgumentError.value(name, 'name', 'no case of $name'),\n",
    )
    ..write('  };\n\n')
    ..write('  @override\n')
    ..write('  List<$caseBase> unionCases() => super.unionCases().cast();\n\n')
    ..write('  @override\n')
    ..write(
      '  $caseBase? unionPrimary() => super.unionPrimary() as $caseBase?;\n\n',
    )
    ..write('  @override\n')
    ..write('  $name deepCopy() => super.deepCopy() as $name;\n')
    ..write('}\n\n')
    ..write(
      '/// A case of [$name], as `unionPrimary()` and `unionCases()` return it.\n',
    )
    ..write('sealed class const $caseBase() extends UnionCase {\n')
    ..write('  /// Creates the case.\n')
    ..write('  this;\n')
    ..write('}\n\n');
  for (final c in cases) {
    b.write(_caseClass(name, caseBase, caseClass(c), c, types));
  }
  return b.toString();
}

String _caseAccessors(Map<String, Object?> c, _Types types) {
  final key = c['name']! as String;
  final member = _memberName(key);
  final doc = _doc(
    c['description']! as String,
    indent: '  ',
    fallback: 'The `$key` case.',
  );
  if (c['valueless'] == true) {
    return '$doc'
        "  bool get $member => wireGet('$key') != null;\n"
        "  set $member(bool value) => wireSet('$key', value ? true : null);\n\n";
  }
  final type = types.dart(_map(c['type']));
  return '$doc'
      "  $type? get $member => wireGet('$key') as $type?;\n"
      "  set $member($type? value) => wireSet('$key', value);\n\n";
}

String _caseClass(
  String union,
  String base,
  String cls,
  Map<String, Object?> c,
  _Types types,
) {
  final key = c['name']! as String;
  if (c['valueless'] == true) {
    return '/// The valueless `$key` case of [$union].\n'
        'final class const $cls() extends $base {\n'
        '  /// Creates the case.\n'
        '  this;\n\n'
        '  @override\n'
        "  String get name => '$key';\n\n"
        '  @override\n'
        '  bool get payload => true;\n'
        '}\n\n';
  }
  final type = types.dart(_map(c['type']));
  return '/// The `$key` case of [$union], with its payload.\n'
      'final class $cls(@override final $type payload) extends $base {\n'
      '  /// Creates the case.\n'
      '  this;\n\n'
      '  @override\n'
      "  String get name => '$key';\n"
      '}\n\n';
}

String _enum(Map<String, Object?> e) {
  final name = e['name']! as String;
  final members = _maps(e['members']);
  _checkUnique(
    name,
    members.map((m) => _enumMemberName(m['value']! as String)),
  );
  final b = StringBuffer()
    ..write(_doc(e['doc']! as String, fallback: 'The `$name` enum.'))
    ..write(
      'enum $name(@override final String wireValue) implements WireEnum {\n',
    );
  for (final m in members) {
    final value = m['value']! as String;
    b
      ..write(
        _doc(
          m['doc']! as String,
          indent: '  ',
          fallback: 'The `$value` member.',
        ),
      )
      ..write('  ${_enumMemberName(value)}(${_str(value)}),\n');
  }
  b.write(';\n}\n\n');
  return b.toString();
}

String _registry(Map<String, Map<String, Object?>> models) {
  final b = StringBuffer()
    ..write(
      '/// The schema of the model for each `type_identifier`, the counterpart\n'
      "/// of upstream's `_MODEL_FOR`.\n"
      'final Map<String, ModelSchema<WireModel>> modelSchemas =\n'
      '    Map.unmodifiable(<String, ModelSchema<WireModel>>{\n',
    );
  final byId = {
    for (final m in models.values)
      m['type_id']! as String: m['name']! as String,
  };
  if (byId.length != models.length) {
    throw GeneratorError('two models share a type_identifier');
  }
  for (final id in byId.keys.toList()..sort()) {
    b.write('  ${_str(id)}: ${byId[id]}.schema,\n');
  }
  b
    ..write('});\n\n')
    ..write(
      '/// Returns the schema of the model for [typeId], or `null` if no model\n'
      '/// has that `type_identifier`.\n'
      'ModelSchema<WireModel>? modelFor(String typeId) => modelSchemas[typeId];\n',
    );
  return b.toString();
}
