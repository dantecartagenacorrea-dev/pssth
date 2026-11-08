import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/citations.dart';

void main() {
  test('quita las referencias entre corchetes', () {
    expect(withoutCitations('El poder corrompe [12].'), 'El poder corrompe.');
    expect(withoutCitations('Como se vio [3, 4] antes, el rey cayó.'), 'Como se vio antes, el rey cayó.');
  });

  test('quita los paréntesis con autor y año', () {
    expect(withoutCitations('La amistad limita el poder (Greene, 1998).'), 'La amistad limita el poder.');
    expect(withoutCitations('Según varios autores (ver Smith et al., 2020, p. 4), sí.'), 'Según varios autores, sí.');
  });

  test('no deja un espacio suelto antes de la puntuación', () {
    expect(withoutCitations('Lo dijo Greene [12] , y tenía razón [3] .'), 'Lo dijo Greene, y tenía razón.');
  });

  test('deja los paréntesis y corchetes que son parte del texto', () {
    const text = 'El ministro (o sea, Talleyrand) habló con el rey.';
    expect(withoutCitations(text), text);
    const long = 'Dijo [y esto lo repitió muchas veces delante de toda la corte del rey] que no.';
    expect(withoutCitations(long), long);
  });

  group('enlaces y correos', () {
    test('quita direcciones web y deja el punto de la frase', () {
      expect(withoutLinks('Más información en https://www.ejemplo.com/ruta?x=1.'), 'Más información en.');
      expect(withoutLinks('Visite www.uagrm.edu.bo para inscribirse.'), 'Visite para inscribirse.');
      expect(withoutLinks('Ver ejemplo.com.bo/ayuda, luego sigue.'), 'Ver, luego sigue.');
    });

    test('quita correos y paréntesis que quedan vacíos', () {
      expect(withoutLinks('Escriba a soporte@pssth.app o llame.'), 'Escriba a o llame.');
      expect(withoutLinks('El sitio (www.ejemplo.org) tiene más.'), 'El sitio tiene más.');
    });

    test('no toca texto común, abreviaturas ni números', () {
      const text = 'El Sr. Pérez pagó 3.500 Bs. el 12.05 y dijo: es así. Fin.';
      expect(withoutLinks(text), text);
      expect(withoutLinks('Lo leí, es bueno.'), 'Lo leí, es bueno.');
    });
  });
}
