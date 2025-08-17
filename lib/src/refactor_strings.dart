// lib/src/refactor_strings.dart

import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:characters/characters.dart';
import 'package:path/path.dart' as p;
import 'dart:convert';

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
  final safeStrings = <String>[];
  final manualStrings = <_ManualString>[];

  // First pass: extract strings and build const map
  for (final file in files) {
    final sourceCode = await File(file).readAsString();
    final parseResult = parseString(
      content: sourceCode,
      throwIfDiagnostics: false,
    );
    final unit = parseResult.unit;

    final stringLiterals = <String>[];
    unit.visitChildren(
      _StringLiteralCollector(safeStrings, manualStrings, file),
    );

    // Process safe strings
    for (var str in safeStrings.toSet()) {
      if (!stringConsts.containsKey(str)) {
        stringConsts[str] = toConstVarName(str);
      }
    }
  }

  // Write all constants to outputConstFile
  final constFileBuffer = StringBuffer();
  constFileBuffer.writeln('// GENERATED STRING CONSTANTS');
  constFileBuffer.writeln('// ✅ Automatically replaceable');
  for (var entry in stringConsts.entries) {
    final escaped = _escapeForConst(entry.key);
    constFileBuffer.writeln("const String ${entry.value} = '$escaped';");
  }

  // ⚠️ Manual replacements required
  if (manualStrings.isNotEmpty) {
    constFileBuffer.writeln('\n// ⚠️ Manual replacements required');
    for (var m in manualStrings) {
      final variableName = toConstVarName(m.snippet);
      final escaped = _escapeForConst(m.snippet);

      // ✅ Check if variable name already exists
      if (!stringConsts.containsKey(m.snippet)) {
        stringConsts[m.snippet] = variableName;

        constFileBuffer.writeln("// Found in: ${m.filePath}");
        constFileBuffer.writeln("const String $variableName = '$escaped';\n");
      }
    }
  }
  await File(outputConstFile).writeAsString(constFileBuffer.toString());

  // Second pass: rewrite source files replacing raw strings with const vars
  for (final file in files) {
    var sourceCode = await File(file).readAsString();

    for (var entry in stringConsts.entries) {
      // Match both single-quoted and double-quoted strings
      final rawStringPattern =
          '(\'${RegExp.escape(entry.key)}\'|\"${RegExp.escape(entry.key)}\")';

      sourceCode = sourceCode.replaceAllMapped(
        RegExp(rawStringPattern),
        (_) => entry.value,
      );
    }

    // Add import for the constants file (use relative path from source file to const file)
    final relativeImportPath = p.relative(
      outputConstFile,
      from: p.dirname(file),
    );
    sourceCode = addImportIfMissing(sourceCode, relativeImportPath);

    await File(file).writeAsString(sourceCode);
  }

  print('Processed ${files.length} files.');
  print('Const strings written to $outputConstFile');
  print('Modified source files updated.');
}


String _escapeForConst(String input) {
  return input
      .replaceAll("'", "\\'")
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\$', '\\\$');
}

String addImportIfMissing(String source, String importPath) {
  final parseResult = parseString(content: source, throwIfDiagnostics: false);
  final unit = parseResult.unit;

  bool hasImport = false;

  for (final directive in unit.directives) {
    if (directive is ImportDirective) {
      final uri = directive.uri.stringValue;
      if (uri == importPath) {
        hasImport = true;
        break;
      }
    }
  }

  if (hasImport) {
    return source; // Already imported, no changes
  }

  // Add import after library/directives and before code
  // Typically after any existing imports, or at top if none
  // Find insertion offset - after last import or after library directive

  int insertOffset = 0;

  // Find last import directive offset
  int lastImportEnd = 0;
  for (final directive in unit.directives) {
    if (directive is ImportDirective) {
      if (directive.end > lastImportEnd) lastImportEnd = directive.end;
    }
  }

  // If imports exist, insert after last import + newline
  if (lastImportEnd > 0) {
    insertOffset = lastImportEnd;
  } else {
    // If no imports, try after library directive if present
    for (final directive in unit.directives) {
      if (directive is LibraryDirective) {
        insertOffset = directive.end;
        break;
      }
    }
  }

  final importStatement = "\nimport '$importPath';\n";

  final newSource =
      source.substring(0, insertOffset) +
      importStatement +
      source.substring(insertOffset);

  return newSource;
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

final Set<String> _generatedVarNames = {};

String toConstVarName(String str, {int maxLength = 40}) {
  // str = str.trim();

  // Step 1: Encode all symbols anywhere and capitalize alphanumerics
  final buffer = StringBuffer();
  for (var char in str.characters) {
    if (_symbolNameMap.containsKey(char)) {
      buffer.write(_symbolNameMap[char]);
    } else if (RegExp(r'[a-zA-Z0-9]').hasMatch(char)) {
      buffer.write(char);
    }
  }
  String baseName = 'k${buffer.toString()}';

  // Step 2: Prefix with underscore if starts with digit
  if (RegExp(r'^[0-9]').hasMatch(baseName)) {
    baseName = '_$baseName';
  }

  // Step 3: If string was exactly a symbol, use mapped name directly (original logic)
  if (_symbolNameMap.containsKey(str)) {
    baseName = 'k${_symbolNameMap[str]}';
  } else if (buffer.isEmpty) {
    // fallback for empty or symbol-only strings not caught above
    baseName = 'kSymbol${_symbolCounter++}';
  }

  // Step 4: Max length check and truncate + append _EXCEEDS if needed
  if (baseName.length > maxLength) {
    final trimmed = baseName.substring(
      0,
      maxLength - 8,
    ); // reserve space for '_EXCEEDS'
    baseName = '${trimmed}_EXCEEDS';
  }

  // Step 5: Collision detection - add suffix _1, _2, etc. if duplicate
  if (!_generatedVarNames.contains(baseName)) {
    _generatedVarNames.add(baseName);
    return baseName;
  } else {
    int suffix = 1;
    String newName;
    do {
      newName = '${baseName}_$suffix';
      suffix++;
    } while (_generatedVarNames.contains(newName));
    _generatedVarNames.add(newName);
    return newName;
  }
}

/// AST visitor that collects all string literals except import directives
class _StringLiteralCollector extends RecursiveAstVisitor<void> {
  final List<String> safeStrings;
  final List<_ManualString> manualStrings;
  final String filePath;
  final Set<String> ignoredFunctions;
  final Set<String> ignoredConstructors;

  _StringLiteralCollector(
    this.safeStrings,
    this.manualStrings,
    this.filePath, {
    this.ignoredFunctions = const {'print', 'debugPrint', 'log'},
    this.ignoredConstructors = const {
      'Exception',
      'FormatException',
      'ArgumentError',
    },
  });

  @override
  void visitMapLiteralEntry(MapLiteralEntry node) {
    if (node.key is SimpleStringLiteral) {
      // ✅ ignore map keys in map literals
      return;
    }
    super.visitMapLiteralEntry(node);
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    final index = node.index;
    if (index is SimpleStringLiteral) {
      // ✅ ignore map keys
      return;
    }
    super.visitIndexExpression(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructorName = node.constructorName.type.name.toString();

    if (ignoredConstructors.contains(constructorName)) {
      return; // skip exceptions
    }

    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // If the method is in ignored list, skip this node
    if (ignoredFunctions.contains(node.methodName.name)) {
      return;
    }

    super.visitMethodInvocation(node);
  }

  @override
  void visitImportDirective(node) {
    // Skip URI strings in imports
  }

  @override
  void visitSimpleStringLiteral(node) {
    safeStrings.add(node.value);
  }

  @override
  void visitAdjacentStrings(node) {
    final combined = node.strings
        .map((s) {
          if (s is SimpleStringLiteral) return s.value;
          return '';
        })
        .join('');
    if (combined.isNotEmpty) safeStrings.add(combined);
  }

  @override
  void visitStringInterpolation(node) {
    for (final element in node.elements) {
      if (element is InterpolationString) {
        manualStrings.add(_ManualString(filePath, node.offset, element.value));
      }
    }
  }
}

/// Helper class for manual strings
class _ManualString {
  final String filePath;
  final int offset;
  final String snippet;

  _ManualString(this.filePath, this.offset, this.snippet);
}
