import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/highlight_store.dart';
import 'package:lector_pdf/domain/highlight.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('subrayados'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('subraya, anota, ordena por página y sobrevive al reabrir', () async {
    final file = File('${dir.path}/highlights.json');
    final store = HighlightStore(file);
    final b = await store.add(documentId: 'd', pageIndex: 5, chunkIndex: 0, text: 'Segunda frase.');
    final a = await store.add(documentId: 'd', pageIndex: 2, chunkIndex: 3, text: 'Primera frase.');
    await store.add(documentId: 'otro', pageIndex: 0, chunkIndex: 0, text: 'De otro libro.');
    // La misma frase dos veces no se duplica.
    expect((await store.add(documentId: 'd', pageIndex: 2, chunkIndex: 3, text: 'x')).id, a.id);
    await store.setNote(b.id, '  importante  ');

    final again = HighlightStore(file);
    final list = await again.forDocument('d');
    expect(list.map((h) => h.text), ['Primera frase.', 'Segunda frase.']);
    expect(list[1].note, 'importante');
    expect(again.isMarked('d', 5, 0), isTrue);
    expect(again.isMarked('d', 5, 1), isFalse);
  });

  test('quitar uno o todos los de un documento avisa a la lectura', () async {
    final store = HighlightStore(File('${dir.path}/h.json'));
    final h = await store.add(documentId: 'd', pageIndex: 0, chunkIndex: 0, text: 'Uno.');
    await store.add(documentId: 'd', pageIndex: 1, chunkIndex: 0, text: 'Dos.');
    final before = store.changes.value;
    await store.remove(h.id);
    expect(store.changes.value, greaterThan(before));
    expect((await store.forDocument('d')).single.text, 'Dos.');
    await store.removeAllFor('d');
    expect(await store.forDocument('d'), isEmpty);
  });

  test('archivo dañado: empieza vacío y lo aparta', () async {
    final file = File('${dir.path}/h.json')..writeAsStringSync('{roto');
    final store = HighlightStore(file);
    expect(await store.forDocument('d'), isEmpty);
    expect(dir.listSync().any((f) => f.path.contains('dañado')), isTrue);
  });

  test('las notas como texto para exportar', () {
    const list = [
      Highlight(id: '1', documentId: 'd', pageIndex: 0, chunkIndex: 0, text: 'Frase uno.', note: '', createdIso: ''),
      Highlight(id: '2', documentId: 'd', pageIndex: 9, chunkIndex: 1, text: 'Frase dos.', note: 'Repasar', createdIso: ''),
    ];
    final text = highlightsAsText('Libro', list);
    expect(text, startsWith('Notas de "Libro"'));
    expect(text, contains('— Página 1\nFrase uno.\n'));
    expect(text, contains('— Página 10\nFrase dos.\nNota: Repasar\n'));
    expect('Nota:'.allMatches(text).length, 1);
  });
}
