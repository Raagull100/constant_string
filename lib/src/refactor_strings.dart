// lib/src/refactor_strings.dart

import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

/// Main reusable function to refactor raw strings into constants.
Future<void> refactorStrings({
  required String inputPath,
  required String outputConstFile,
  required String outputSourceFile,
}) async {
  final files = await collectDartFiles(inputPath);

  if (files.isEmpty) {
    print('No Dart files found in $inputPath');
    return;
  }

  final Map<String, String> stringConsts = {};

  // First pass: extract strings and build const map
  for (final file in files) {
    final sourceCode = await File(file).readAsString();
    final parseResult = parseString(content: sourceCode, throwIfDiagnostics: false);
    final unit = parseResult.unit;

    final stringLiterals = <String>[];
    unit.visitChildren(_StringLiteralCollector(stringLiterals));

    for (var str in stringLiterals.toSet()) {
      if (!stringConsts.containsKey(str)) {
        stringConsts[str] = toConstVarName(str);
      }
    }
  }

  // Write all constants to outputConstFile
  final constFileBuffer = StringBuffer();
  constFileBuffer.writeln('// GENERATED STRING CONSTANTS');
  for (var entry in stringConsts.entries) {
    final escaped = entry.key.replaceAll(r'$', r'\$').replaceAll("'", r"\'");
    constFileBuffer.writeln("const String ${entry.value} = '$escaped';");
  }
  await File(outputConstFile).writeAsString(constFileBuffer.toString());

  // Second pass: rewrite source files replacing raw strings with const vars
  for (final file in files) {
    var sourceCode = await File(file).readAsString();

    for (var entry in stringConsts.entries) {
      final rawStringPattern = "'${RegExp.escape(entry.key)}'";
      sourceCode = sourceCode.replaceAll(RegExp(rawStringPattern), entry.value);
    }

    await File(file).writeAsString(sourceCode);
  }

  print('Processed ${files.length} files.');
  print('Const strings written to $outputConstFile');
  print('Modified source files updated.');
}

/// Helper to collect Dart files from a path (file or directory)
Future<List<String>> collectDartFiles(String path) async {
  final file = File(path);
  if (await file.exists()) {
    if (p.extension(path) == '.dart') return [path];
    return [];
  }

  final dir = Directory(path);
  if (!await dir.exists()) return [];

  final dartFiles = <String>[];
  await for (var entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File && p.extension(entity.path) == '.dart') {
      dartFiles.add(entity.path);
    }
  }
  return dartFiles;
}

int _symbolCounter = 1;

/// Map for symbol strings to constant names
final Map<String, String> _symbolNameMap = {
  '₹': 'kRupees',
  '/': 'kSlash',
  '%': 'kPercent',
  ' ': 'kSpace',
  '-': 'kDash',
  '+': 'kPlus',
  '@': 'kAt',
  '#': 'kHash',
  '&': 'kAmpersand',
  '*': 'kAsterisk',
  ',': 'kComma',
  '.': 'kDot',
  ':': 'kColon',
  ';': 'kSemicolon',
  '?': 'kQuestionMark',
  '!': 'kExclamation',
  '~': 'kTilde',
  '^': 'kCaret',
  '\$': 'kDollar',
  '=': 'kEquals',
  '<': 'kLessThan',
  '>': 'kGreaterThan',
  '|': 'kPipe',
  '\\': 'kBackslash',
  '"': 'kQuote',
  "'": 'kApostrophe',
  '(': 'kOpenParen',
  ')': 'kCloseParen',
  '[': 'kOpenBracket',
  ']': 'kCloseBracket',
  '{': 'kOpenBrace',
  '}': 'kCloseBrace',
  '': 'kEmptyString',
};

/// Converts a raw string to a valid constant variable name
String toConstVarName(String str) {
  str = str.trim();

  if (_symbolNameMap.containsKey(str)) {
    return _symbolNameMap[str]!;
  }

  final words = RegExp(r'[a-zA-Z0-9]+').allMatches(str).map((m) => m.group(0)!).toList();

  if (words.isEmpty) {
    return 'kSymbol${_symbolCounter++}';
  }

  final capitalized = words.map((w) => w[0].toUpperCase() + w.substring(1)).join();
  var varName = 'k$capitalized';

  if (RegExp(r'^[0-9]').hasMatch(varName)) {
    varName = '_$varName';
  }

  return varName;
}

/// AST visitor that collects all string literals except import directives
class _StringLiteralCollector extends RecursiveAstVisitor<void> {
  final List<String> strings;

  _StringLiteralCollector(this.strings);

  @override
  void visitImportDirective(node) {
    // Skip URI strings in imports
  }

  @override
  void visitSimpleStringLiteral(node) {
    strings.add(node.value);
  }

  @override
  void visitAdjacentStrings(node) {
    final combined = node.strings.map((s) {
      if (s is SimpleStringLiteral) return s.value;
      return '';
    }).join('');
    if (combined.isNotEmpty) strings.add(combined);
  }

  @override
  void visitStringInterpolation(node) {
    for (final element in node.elements) {
      if (element is InterpolationString) {
        strings.add(element.value);
      }
    }
    super.visitStringInterpolation(node);
  }
}
