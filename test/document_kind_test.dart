import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/library_store.dart';

void main() {
  test('reconoce el tipo de documento por su extensión', () {
    expect(LibraryStore.kindFor('Defensa_Tesis.html'), 'html');
    expect(LibraryStore.kindFor('pagina.HTM'), 'html');
    expect(LibraryStore.kindFor('libro.epub'), 'epub');
    expect(LibraryStore.kindFor('notas.txt'), 'txt');
    expect(LibraryStore.kindFor('foto.jpg'), 'image');
    expect(LibraryStore.kindFor('informe.pdf'), 'pdf');
  });
}
