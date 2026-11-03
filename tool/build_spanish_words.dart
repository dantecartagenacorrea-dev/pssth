// Arma assets/words/spanish_words.bin desde la lista an-array-of-spanish-words 2.0.0
// (licencia MIT, ver assets/words/LICENSE.txt): dart run tool/build_spanish_words.dart index.json
import 'dart:convert';
import 'dart:io';

import 'package:lector_pdf/domain/spanish_words.dart';

void main(List<String> args) {
  final list = (jsonDecode(File(args.single).readAsStringSync()) as List).cast<String>();
  final words = SpanishWords.build(list.map(plainWord));
  File('assets/words/spanish_words.bin').writeAsBytesSync(words.bytes);
  stdout.writeln('${list.length} palabras, ${words.bytes.length} bytes');
}
