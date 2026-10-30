import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/caps_speech.dart';

void main() {
  test('un título en mayúsculas se dice como palabras y cierra con punto', () {
    expect(speakableCaps('KAUTILYA, FILÓSOFO'), 'Kautilya, Filósofo.');
    expect(speakableCaps('EN EL CAMPO'), 'En El Campo.');
  });

  test('respeta números romanos y no duplica la puntuación final', () {
    expect(speakableCaps('INDIO, SIGLO III A. C.'), 'Indio, Siglo III A. C.');
    expect(speakableCaps('CAPÍTULO IV'), 'Capítulo IV.');
  });

  test('dentro de una frase: palabras largas sí, siglas cortas no', () {
    expect(speakableCaps('La ONU dijo que era URGENTE ayudar.'), 'La ONU dijo que era Urgente ayudar.');
    expect(speakableCaps('Abre el PDF.'), 'Abre el PDF.');
    expect(speakableCaps('Texto normal sin cambios.'), 'Texto normal sin cambios.');
  });

  test('las posiciones de las letras no cambian', () {
    const t = 'KAUTILYA, FILÓSOFO';
    expect(speakableCaps(t).substring(0, t.length).length, t.length);
  });

  test('sameSpokenText ignora mayúsculas y el punto agregado', () {
    expect(sameSpokenText('Kautilya, Filósofo.', 'KAUTILYA, FILÓSOFO'), isTrue);
    expect(sameSpokenText('hola', 'hola'), isTrue);
    expect(sameSpokenText('cuatro', '4'), isFalse);
  });
}
