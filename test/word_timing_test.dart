import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/word_timing.dart';

void main() {
  const text = 'Hola, mundo grande';

  test('separa las palabras con su posición en el texto', () {
    expect(wordSpans(text), [(0, 5), (6, 11), (12, 18)]);
    expect(wordSpans('   '), isEmpty);
  });

  test('avanza de palabra en palabra a lo largo del audio', () {
    expect(wordAtFraction(text, 0), (0, 5));
    expect(wordAtFraction(text, 0.5), (6, 11));
    expect(wordAtFraction(text, 0.99), (12, 18));
    expect(wordAtFraction(text, 1.5), (12, 18));
    expect(wordAtFraction('', 0.5), isNull);
  });

  test('la pausa tras la coma alarga la palabra anterior', () {
    // "Hola," pesa 5+1+4 = 10 de 23: al 40 % todavía suena.
    expect(wordAtFraction(text, 0.4), (0, 5));
  });

  test('ignora el silencio del principio y del final', () {
    expect(voicedRange([0, 0.01, 0.5, 1, 0.3, 0.02]), (2, 4));
    expect(voicedRange([0, 0, 0]), isNull);
  });
}
