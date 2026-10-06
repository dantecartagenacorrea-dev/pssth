import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/chunker.dart';

void main() {
  _abrevTests();
  test('página vacía no genera chunks', () {
    expect(splitPageText('   \n\n  '), isEmpty);
  });

  test('prioriza párrafos', () {
    final chunks = splitPageText('Uno.\n\nDos.');
    expect(chunks, ['Uno.', 'Dos.']);
  });

  test('divide frases largas', () {
    final longSentence =
        '${'palabra ' * 80}final.';
    final chunks = splitPageText(longSentence, maxLength: 40);
    expect(chunks.length, greaterThan(1));
    expect(chunks.every((c) => c.length <= 40), isTrue);
  });

  test('no envía un bloque enorme', () {
    final page = List.generate(20, (i) => 'Frase número $i del documento de prueba.').join(' ');
    final chunks = splitPageText(page, maxLength: 80);
    expect(chunks, isNotEmpty);
    expect(chunks.every((c) => c.length <= 80), isTrue);
  });
}

void _abrevTests() {
  test('no corta frases tras abreviaturas ni numerales', () {
    final s = splitSentences(
        'Art. 2. Las personas presentarán su declaración. Inc. a) El contribuyente debe. Fin.');
    expect(s, [
      'Art. 2. Las personas presentarán su declaración.',
      'Inc. a) El contribuyente debe.',
      'Fin.',
    ]);
  });
}
