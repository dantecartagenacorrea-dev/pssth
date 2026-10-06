import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/chunk_builder.dart';
import 'package:lector_pdf/domain/page_cleaner.dart';
import 'package:lector_pdf/domain/text_normalizer.dart';

void main() {
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
}
