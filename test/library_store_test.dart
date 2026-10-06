import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/library_store.dart';

void main() {
  test('reimportar el mismo archivo reutiliza la entrada y su progreso', () async {
    final dir = await Directory.systemTemp.createTemp('lector_lib');
    final store = LibraryStore();
    await store.initAt(dir);
    final bytes = List<int>.generate(500, (i) => i % 251);
    final a = await store.importFile(originalName: 'doc.pdf', bytes: bytes);
    await store.updatePosition(id: a.id, pageIndex: 3, chunkIndex: 1);
    final b = await store.importFile(originalName: 'doc.pdf', bytes: bytes);
    expect(b.id, a.id);
    expect(store.byId(a.id)!.pageIndex, 3);
    expect(store.data.entries.length, 1);
    // Mismo nombre, contenido distinto: entrada nueva.
    final c = await store.importFile(originalName: 'doc.pdf', bytes: [...bytes, 1]);
    expect(c.id, isNot(a.id));
    expect(store.data.entries.length, 2);
    await dir.delete(recursive: true);
  });
}
