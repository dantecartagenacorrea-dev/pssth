import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/bookmark_store.dart';
import 'package:lector_pdf/domain/chapter_detector.dart';
import 'package:lector_pdf/domain/library_entry.dart';
import 'package:lector_pdf/domain/search.dart';
import 'package:lector_pdf/domain/text_chunk.dart';

void main() {
  test('detecta capítulos claros y evita el índice', () {
    final pages = [
      'Índice\nCapítulo 1 ........ 3\nCapítulo 2 ........ 9',
      'Capítulo 1 Inicio\nTexto del primero.',
      'Más texto sin título.',
      'CAPÍTULO 2 El final\nTexto del segundo.',
    ];
    final c = detectChapters(pages);
    expect(c.map((x) => x.pageIndex), [1, 3]);
  });

  test('con menos de dos capítulos no inventa índice', () {
    expect(detectChapters(['Capítulo 1\nUnico', 'texto']), isEmpty);
  });

  test('un encabezado repetido no es capítulo', () {
    final pages = List.generate(5, (i) => 'Parte 1 del informe\ntexto $i');
    expect(detectChapters(pages), isEmpty);
  });

  test('búsqueda ignora acentos y mayúsculas', () {
    final chunks = [
      TextChunk(documentId: 'd', pageIndex: 0, chunkIndex: 0, text: 'La Ley de Impuestos'),
      TextChunk(documentId: 'd', pageIndex: 1, chunkIndex: 0, text: 'Otra cosa'),
      TextChunk(documentId: 'd', pageIndex: 2, chunkIndex: 0, text: 'declaración jurada'),
    ];
    expect(searchChunks(chunks, 'DECLARACION'), [2]);
    expect(searchChunks(chunks, 'ley'), [0]);
    expect(searchChunks(chunks, '  '), isEmpty);
  });

  test('marcadores: añadir, no duplicar, persistir y eliminar', () async {
    final dir = await Directory.systemTemp.createTemp('bm');
    final f = File('${dir.path}/b.json');
    final s1 = BookmarkStore(f);
    final a = await s1.add(documentId: 'd', pageIndex: 2, chunkIndex: 1, label: 'x');
    final dup = await s1.add(documentId: 'd', pageIndex: 2, chunkIndex: 1, label: 'x');
    expect(dup.id, a.id);
    final s2 = BookmarkStore(f);
    expect((await s2.forDocument('d')).length, 1);
    await s2.remove(a.id);
    expect(await BookmarkStore(f).forDocument('d'), isEmpty);
    await dir.delete(recursive: true);
  });

  test('LibraryEntry conserva favorito/terminado y es compatible hacia atrás', () {
    final e = LibraryEntry(
      id: '1', name: 'a.pdf', storedPath: 'p', pageCount: 3, totalChunks: 0,
      favorite: true, finished: true,
    );
    final back = LibraryEntry.fromJson(e.toJson());
    expect(back.favorite, isTrue);
    expect(back.finished, isTrue);
    final old = LibraryEntry.fromJson({'id': '2', 'name': 'b.pdf', 'storedPath': 'q'});
    expect(old.favorite, isFalse);
    expect(old.kind, 'pdf');
  });
}
