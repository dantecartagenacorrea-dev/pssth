import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/chunk_builder.dart';
import 'package:lector_pdf/domain/page_cleaner.dart';
import 'package:lector_pdf/domain/text_normalizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // buildChunks pasa por TranscriptCleaner, que lee SharedPreferences.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('quita encabezado repetido y número de página', () {
    const words = ['alfa', 'beta', 'gamma', 'delta', 'epsilon', 'zeta'];
    final pages = List.generate(
      6,
      (i) =>
          'Informe Anual\nContenido ${words[i]} de la página.\nPágina ${i + 1}',
    );
    final out = PageCleaner.clean(pages);
    expect(out.every((p) => !p.contains('Informe Anual')), isTrue);
    expect(out.every((p) => !p.contains('Página')), isTrue);
    expect(out[2], contains('gamma'));
  });

  test('conserva texto si no hay repetición', () {
    final out = PageCleaner.clean(['Hola mundo uno', 'Otra cosa distinta']);
    expect(out, ['Hola mundo uno', 'Otra cosa distinta']);
  });

  test('une palabras partidas por guion de fin de línea', () {
    final out = PageCleaner.clean(['La informa-\nción es clave']);
    expect(out.single, 'La información es clave');
  });

  test('no une si la siguiente línea empieza con mayúscula', () {
    final out = PageCleaner.clean(['Norte-\nSur']);
    expect(out.single, 'Norte-\nSur');
  });

  test('detecta páginas sin texto', () {
    expect(pageNeedsOcr('   \n '), isTrue);
    expect(pageNeedsOcr('Texto suficientemente largo para leer.'), isFalse);
  });

  test('buildChunks separa original y voz', () {
    final c = buildChunks(
      documentId: 'd',
      pages: ['Art. 5 cuesta Bs 10.'],
      normalizer: TextNormalizer(),
    );
    expect(c.single.text, 'Art. 5 cuesta Bs 10.');
    expect(c.single.speech, contains('Artículo'));
    expect(c.single.speech, contains('10 bolivianos'));
  });

  test('quita el pie con número de página aunque el escaneo lo escriba distinto', () {
    // Pies reales de un libro escaneado: número de página, separador ("I",
    // "1", nada) y la ley en curso.
    const feet = ['32 1 LEY N° 1', 'LEY N° 1 I 31', '34ILEY N° 1', 'LEY N° 2 I 39', '40 I LEY N° 2', 'LEY N° 29 I3 0.5'];
    const words = ['alfa', 'beta', 'gamma', 'delta', 'epsilon', 'zeta'];
    final pages = [for (var i = 0; i < feet.length; i++) 'Cuerpo ${words[i]}.\nSigue ${words[i]}.\n${feet[i]}'];
    final out = PageCleaner.clean(pages);
    for (var i = 0; i < feet.length; i++) {
      expect(out[i], 'Cuerpo ${words[i]}.\nSigue ${words[i]}.');
    }
  });

  test('une las palabras cortadas por el guion invisible del PDF y quita el pie pegado', () {
    const words = ['alfa', 'beta', 'gamma', 'delta'];
    final pages = [for (final w in words) 'Cuerpo $w.\nSigue $w.\n40 I LEY N° 2'];
    pages[0] = 'Mantenga la eficien\u0002cia y la igno\u0002rancia.\nOtra alfa.\n40 I LEY N° 2';
    pages[1] = 'Cuerpo beta.\nUna especie de resigna\u0002LEY N° 19 I 191';
    final out = PageCleaner.clean(pages);
    expect(out[0], startsWith('Mantenga la eficiencia y la ignorancia.'));
    expect(out[1], 'Cuerpo beta.\nUna especie de resigna-');
  });

  test('quita encabezados con número y números sueltos, conserva títulos y fechas', () {
    final out = PageCleaner.clean([
      'Cuerpo uno.\nMás uno.\nCONTENIDO I 9',
      'LEY N°\n1 0\nPELIGRO DE CONTAGIO\nCuerpo dos.\n10 I CONTENIDO',
      'LEY N° 22\nCuerpo tres.\nMás tres.\n12 I CONTENIDO',
      'Cuerpo cuatro.\nMás cuatro.\nVoltaire, 1694-1778\n1 29',
    ]);
    expect(out[0], 'Cuerpo uno.\nMás uno.');
    expect(out[1], 'LEY N°\nPELIGRO DE CONTAGIO\nCuerpo dos.');
    expect(out[2], 'LEY N° 22\nCuerpo tres.\nMás tres.'); // título de capítulo: se queda
    expect(out[3], 'Cuerpo cuatro.\nMás cuatro.\nVoltaire, 1694-1778');
  });
}
