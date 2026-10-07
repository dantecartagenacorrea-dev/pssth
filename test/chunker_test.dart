import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/chunker.dart';

void main() {
  _capituloTests();
  _poemaTests();
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

void _poemaTests() {
  test('un título en mayúsculas se lee como bloque aparte', () {
    final c = splitPageText('EN EL CAMPO\n¡ Qué noche ! El techo que escuda\nmi solitario aposento.');
    expect(c.first, 'EN EL CAMPO');
    expect(c[1], startsWith('¡ Qué noche !'));
  });
}

void _capituloTests() {
  test('un encabezado "CAPITULO n. ..." se lee como bloque aparte', () {
    final c = splitPageText('CAPITULO 1. Sobre la sociedad\nEste es el párrafo 1 de la página 1. Sigue el texto.');
    expect(c.first, 'CAPITULO 1. Sobre la sociedad');
    expect(c[1], startsWith('Este es el párrafo'));
  });
  test('no corta la frase tras abreviaturas masónicas', () {
    final f = splitSentences('La Mas.·. atraviesa un período difícil. Siguiente frase.');
    expect(f.length, 2);
    expect(f.first, startsWith('La Mas.·. atraviesa'));
  });
}
