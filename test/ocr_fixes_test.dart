import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/ocr_fixes.dart';

void main() {
  test('en un teléfono las o son ceros', () {
    expect(fixDigitLookalikes('+591 7oooO00'), '+591 7000000');
  });

  test('en una fecha las letras parecidas son dígitos', () {
    expect(fixDigitLookalikes('Date of Issue 1s/o3/2024'), 'Date of Issue 15/03/2024');
  });

  test('las palabras no se tocan', () {
    for (final text in ['Solo lo esencial', 'los 50 sobres', 'ISO 9001', 'correo@ejemplo.com', 'Art. 284']) {
      expect(fixDigitLookalikes(text), text);
    }
  });

  test('un número con otras letras no se toca: no se sabe qué era', () {
    expect(fixDigitLookalikes('1s/03laos4'), '1s/03laos4');
  });
}
