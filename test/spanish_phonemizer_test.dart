import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/spanish_phonemizer.dart';

String f(String t, {bool seseo = true}) => phonemizeSpanish(t, seseo: seseo).join(' ');

/// Símbolos que conoce el modelo Kokoro (tokens.txt), más el espacio.
const kokoroSymbols = ';:,.!?—…"()“” ̃ʣʥʦʨᵝꭧAIOQSTWYᵊabcdefhijklmnopqrstuvwxyzɑɐɒæβɔɕçɖðʤəɚɛɜɟɡɥɨɪʝɯɰŋɳɲɴøɸθœɹɾɻʁɽʂʃʈʧʊʋʌɣɤχʎʒʔˈˌːʰʲ↓→↗↘ᵻ';

void main() {
  group('frases ya escuchadas y aprobadas', () {
    test('saludo con tildes y signos', () {
      expect(f('Hola, ¿cómo estás?'), 'ˈola, kˈomo estˈas?');
    });
    test('fricativas entre vocales y ñ', () {
      expect(f('El niño bebe agua del río.'), 'el nˈiɲo βˈeβe ˈaɣwa ðel rˈio.');
    });
    test('diptongos y erre', () {
      expect(f('La guerra terminó cuando llegó la paz al pueblo.'),
          'la ɣˈera teɾminˈo kwando ʝeɣˈo la pˈas al pwˈeβlo.');
    });
  });

  group('seseo o distinción', () {
    test('latino por defecto: z y ce, ci como s', () {
      expect(f('la paz, la cena'), 'la pˈas, la sˈena');
    });
    test('España: θ', () {
      expect(f('la paz, la cena', seseo: false), 'la pˈaθ, la θˈena');
    });
  });

  group('consonantes tras nasal', () {
    test('d y b fuertes después de n', () {
      expect(f('un documento'), 'un dokumˈento');
      expect(f('un barco'), 'um bˈaɾko');
    });
    test('n se asimila antes de b, v, p y g', () {
      expect(f('enviarme'), 'embjˈaɾme');
      expect(f('tengo'), 'tˈeŋɡo');
    });
    test('d fuerte después de l', () {
      expect(f('el dedo'), 'el dˈeðo');
    });
  });

  group('acento', () {
    test('esdrújula, aguda y llana', () {
      expect(f('artículo'), 'aɾtˈikulo');
      expect(f('jardín'), 'xaɾðˈin');
      expect(f('casa'), 'kˈasa');
      expect(f('ciudad'), 'sjuðˈað');
    });
    test('palabras átonas sin marca', () {
      expect(f('de la casa'), 'de la kˈasa');
    });
    test('hiato con tilde', () {
      expect(f('día'), 'dˈia');
    });
    test('y final como vocal', () {
      expect(f('estoy muy bien'), 'estˈoi mwˈi βjˈen');
    });
  });

  group('letras especiales', () {
    test('qu, gu, gü, ch, ll, j, h y x', () {
      expect(f('queso'), 'kˈeso');
      expect(f('guitarra'), 'ɡitˈara');
      expect(f('pingüino'), 'piŋɡwˈino');
      expect(f('chico'), 'tʃˈiko');
      expect(f('lluvia'), 'ʝˈuβja');
      expect(f('hijo'), 'ˈixo');
      expect(f('taxi'), 'tˈaksi');
      expect(f('México'), 'mˈexiko');
    });
  });

  test('números en cifras se leen en palabras', () {
    expect(f('Artículo 5'), f('Artículo cinco'));
    expect(f('1.234,50 bolivianos'), f('mil doscientos treinta y cuatro coma cincuenta bolivianos'));
  });

  test('siglas sin vocales se deletrean', () {
    expect(f('SRL'), f('ese erre ele'));
  });

  test('separa en frases para no superar el límite del modelo', () {
    expect(phonemizeSpanish('Uno. Dos! ¿Tres?'), ['ˈuno.', 'dˈos!', 'tɾˈes?']);
  });

  test('solo produce símbolos que el modelo conoce', () {
    const texto = 'Señor Müller: el Ñandú comió 3,5 kg de ¡queso! (sí) "Wi-Fi" 50% & más… São Paulo, Zoë, 2024.';
    for (final s in phonemizeSpanish(texto)) {
      for (final ch in s.runes) {
        expect(kokoroSymbols.runes.contains(ch) || ch == 0x20, isTrue, reason: 'símbolo ${String.fromCharCode(ch)} en "$s"');
      }
    }
  });

  test('nunca devuelve frases vacías', () {
    expect(phonemizeSpanish('  ... ¿? '), isEmpty);
  });
}
