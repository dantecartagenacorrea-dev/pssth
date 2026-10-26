import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/language_segmenter.dart';
import 'package:lector_pdf/domain/library_entry.dart';

void main() {
  group('idioma del documento', () {
    test('usa el detectado si hay voz para él', () {
      expect(chooseDocumentLanguage('en', available: {'es', 'en'}), 'en');
    });

    test('un idioma raro sin voz instalada cae en español', () {
      expect(chooseDocumentLanguage('ca', available: {'es', 'en'}), 'es');
      expect(chooseDocumentLanguage(null, available: {'es', 'en'}), 'es');
    });

    test('sin español instalado, el primero disponible', () {
      expect(chooseDocumentLanguage('ca', available: {'pt'}), 'pt');
    });

    test('sin lista de voces todavía, se confía en el detector', () {
      expect(chooseDocumentLanguage('en', available: const {}), 'en');
    });
  });

  group('cambio de voz a mitad del documento', () {
    const largoPt =
        'O livro conta a história de uma família que vive no campo com os seus animais e a sua terra há muitos anos.';

    test('no cambia a un idioma sin voz instalada', () {
      final langs = segmentLanguages(
        ['Texto en español para empezar.', largoPt],
        documentLanguage: 'es',
        detect: (t) => t.startsWith('O livro') ? 'pt' : 'es',
        allowed: {'es', 'en'},
      );
      expect(langs, ['es', 'es']);
    });

    test('un fragmento corto en otro idioma no cambia la voz', () {
      final langs = segmentLanguages(
        ['Hello my friend, how are you doing today at home?'],
        documentLanguage: 'es',
        detect: (_) => 'en',
        allowed: {'es', 'en'},
      );
      expect(langs, ['es']);
    });
  });

  test('el idioma elegido a mano se guarda con el documento', () {
    final e = LibraryEntry(id: '1', name: 'a.pdf', storedPath: '/a', pageCount: 1, totalChunks: 1, language: 'en');
    expect(LibraryEntry.fromJson(e.toJson()).language, 'en');
    final sin = LibraryEntry(id: '2', name: 'b.pdf', storedPath: '/b', pageCount: 1, totalChunks: 1);
    expect(LibraryEntry.fromJson(sin.toJson()).language, isNull);
  });
}
