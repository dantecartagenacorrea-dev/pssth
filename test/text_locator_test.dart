import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/text_locator.dart';

void main() {
  const page =
      'LEY N° 45\nPREDIQUE LA NECESIDAD\nEn teoría, todo el mundo comprende la nece-\nsidad del cambio, pero en el '
      'nivel cotidiano,\n474 I LEY N° 45\nel ser humano es hijo de la costumbre.';

  test('encuentra la frase aunque cambien espacios, guiones y mayúsculas', () {
    const frase = 'En teoría, todo el mundo comprende la necesidad del cambio';
    final r = locateSnippet(page, frase)!;
    expect(page.substring(r.start, r.end), 'En teoría, todo el mundo comprende la nece-\nsidad del cambio');
  });

  test('salta un pie de página que quedó en medio de la frase', () {
    const frase = 'pero en el nivel cotidiano, el ser humano es hijo de la costumbre.';
    final r = locateSnippet(page, frase)!;
    expect(page.substring(r.start), startsWith('pero en el nivel'));
    expect(page.substring(0, r.end), endsWith('costumbre'));
  });

  test('si la frase no está en la página, nada', () {
    expect(locateSnippet(page, 'Esta frase no aparece en ningún lado de la página.'), isNull);
    expect(locateSnippet(page, '...'), isNull);
  });

  test('junta las letras de cada renglón en un recuadro', () {
    final lines = mergeLines([
      (left: 10, top: 100, right: 18, bottom: 112),
      (left: 18, top: 101, right: 26, bottom: 112),
      (left: 26, top: 100, right: 26, bottom: 112), // espacio sin ancho
      (left: 30, top: 100, right: 40, bottom: 113),
      (left: 10, top: 120, right: 18, bottom: 132), // renglón siguiente
    ]);
    expect(lines, [
      (left: 10.0, top: 100.0, right: 40.0, bottom: 113.0),
      (left: 10.0, top: 120.0, right: 18.0, bottom: 132.0),
    ]);
  });
}
