// bin/constant_string.dart

import 'dart:io';
import 'package:constant_string/constant_string.dart';

void main(List<String> args) async {
  if (args.length != 3) {
    print('Usage: constant_string <input_path> <output_const_file> <output_source_file>');
    exit(1);
  }

  await refactorStrings(
    inputPath: args[0],
    outputConstFile: args[1],
    outputSourceFile: args[2],
  );
}
