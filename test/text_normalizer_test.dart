import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/text_normalizer.dart';

void main() {
  _puntuacionTests();
  final n = TextNormalizer();

  test('Art. y Arts.', () {
    expect(n.normalize('Art. 5 y Arts. 6'), 'Artículo 5 y Artículos 6');
  });

  test('importes en bolivianos', () {
    expect(n.normalize('Pagó Bs 1.234,50 hoy'), 'Pagó 1.234,50 bolivianos hoy');
    expect(n.normalize('Bs. 100'), '100 bolivianos');
  });

  test('porcentajes', () {
    expect(n.normalize('IVA 13%'), 'IVA 13 por ciento');
    expect(n.normalize('IVA 13 %'), 'IVA 13 por ciento');
  });

  test('no toca palabras que contienen la abreviatura', () {
    expect(n.normalize('Carta y Bsx'), 'Carta y Bsx');
  });

  test('diccionario del usuario tiene prioridad', () {
    final d = TextNormalizer(dictionary: {'SIN': 'Servicio de Impuestos Nacionales'});
    expect(d.normalize('El SIN emitió'), 'El Servicio de Impuestos Nacionales emitió');
    expect(d.normalize('sin duda'), 'sin duda');
  });

  test('modo no jurídico no expande abreviaturas', () {
    final s = TextNormalizer(legalMode: false);
    expect(s.normalize('Art. 5'), 'Art. 5');
  });

  test('limpia puntos guía y viñetas', () {
    expect(n.normalize('Capítulo 1 ........ 5'), 'Capítulo 1 5');
    expect(n.normalize('• uno'), 'uno');
  });
}

void _puntuacionTests() {
  test('quita espacios antes de la puntuación y tras signos de apertura', () {
    final n = TextNormalizer();
    expect(n.normalize('¡ Qué noche ! cruje al soplo que lo abate ; y muda ,'),
        '¡Qué noche! cruje al soplo que lo abate; y muda,');
  });
}
