import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/spanish_phonemizer.dart';
import 'package:lector_pdf/domain/text_normalizer.dart';

String fonemas(String texto) => phonemizeSpanish(TextNormalizer().normalize(texto)).join(' ');

void main() {
  test('las palabras extranjeras comunes se dicen como en español', () {
    expect(fonemas('Google'), 'ɡˈuɣol');
    expect(fonemas('marketing'), 'mˈaɾketin');
  });

  test('la x seguida de c no duplica el sonido', () {
    expect(fonemas('excelente'), 'ekselˈente');
  });

  test('unidades y abreviaturas no se leen letra por letra ni cortan la frase', () {
    expect(TextNormalizer().normalize('20 km y 5 kg'), '20 kilómetros y 5 kilos');
    expect(TextNormalizer().normalize('art. 15'), 'Artículo 15');
    expect(TextNormalizer().normalize('a las 10 a.m. en punto'), 'a las 10 a eme en punto');
  });
}
