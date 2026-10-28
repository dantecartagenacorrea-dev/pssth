import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/text_chunk.dart';
import 'package:lector_pdf/ui/read_scroll.dart';

TextChunk c(int page, int i, String t) => TextChunk(documentId: 'd', pageIndex: page, chunkIndex: i, text: t);

void main() {
  final chunks = [c(0, 0, 'Uno.'), c(0, 1, ' Dos. '), c(1, 2, 'Tres.'), c(1, 3, 'Cuatro.'), c(2, 4, 'Cinco.')];

  test('junta lo leído hasta la frase actual, por página', () {
    expect(readSoFar(chunks, 2), [(1, 'Uno. Dos.'), (2, 'Tres.')]);
    expect(readSoFar(chunks, 4), [(1, 'Uno. Dos.'), (2, 'Tres. Cuatro.'), (3, 'Cinco.')]);
  });

  test('sin texto no hay nada que mostrar', () {
    expect(readSoFar(const [], 0), isEmpty);
    expect(readSoFar(chunks, -1), isEmpty);
  });

  test('los títulos sin puntuación quedan en su propia línea', () {
    final t = [c(0, 0, 'Campos de aplicación'), c(0, 1, 'editar'), c(0, 2, 'La primera frase.'), c(0, 3, 'La segunda.')];
    expect(readSoFar(t, 3), [(1, 'Campos de aplicación\neditar\nLa primera frase. La segunda.')]);
  });
}
