import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/chapter_detector.dart';

void main() {
  test('títulos numerados: número abajo, faltante, mal leído y con comillas', () {
    final pages = [
      'ÍNDICE\nLEY Nº 1  página 3\nLEY Nº 2  página 4',
      'LEY Nº\n1\nNUNCA SE APURE\nCRITERIO\nTexto de la primera.',
      'LEY Nº\nNO HABLE DE MÁS\nCRITERIO\nTexto de la segunda.', // sin número
      'LEY Nº\ns3\nESCUCHE PRIMERO\nCRITERIO\nTexto.', // "33" mal leído
      'LEY N"\nELIJA BIEN\nA SUS ALIADOS\nCRITE RI O\nTexto.', // º leído como comillas
    ];
    final ch = detectChapters(pages);
    expect(ch.map((c) => c.title), [
      'Ley 1 · Nunca se apure',
      'Ley 2 · No hable de más',
      'Ley 3 · Escuche primero',
      'Ley 4 · Elija bien a sus aliados',
    ]);
    expect(ch.first.pageIndex, 1); // no toma el índice del principio
  });

  test('otras palabras numeradas y capítulos de siempre', () {
    expect(detectChapters(['Regla 1\nUNO\nTexto.', 'Regla 2\nDOS\nTexto.']).map((c) => c.title), ['Regla 1 · Uno', 'Regla 2 · Dos']);
    expect(detectChapters(['Capítulo 1\nTexto', 'Capítulo 2\nTexto']), hasLength(2));
    expect(detectChapters(['Texto sin títulos.']), isEmpty);
  });

  test('la primera de la serie sin número visible es la 1 (el número quedó al pie)', () {
    final pages = [
      'LEY N°\nNUNCA LE HAGA\nSOMBRA A SU AMO\nCRITERIO\nTexto.',
      'Historia de la primera ley.',
      'LEY N°\nNUNCA CONFÍE DEMASIADO\nEN SUS AMIGOS\nCRITERIO\nTexto.',
      'LEY N°\nPELIGRO DE CONTAGIO\nCRITERIO\nTexto.',
    ];
    expect(detectChapters(pages).map((c) => c.title), [
      'Ley 1 · Nunca le haga sombra a su amo',
      'Ley 2 · Nunca confíe demasiado en sus amigos',
      'Ley 3 · Peligro de contagio',
    ]);
    // Una palabra suelta sin "N°" ni título no abre una serie.
    expect(detectChapters(['Tema\nTexto.', 'Tema\nOtro texto.']), isEmpty);
  });
}
