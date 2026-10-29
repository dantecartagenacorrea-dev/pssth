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

  test('una lista dañada se guarda aparte en vez de perderse', () async {
    final dir = await Directory.systemTemp.createTemp('lector_lib');
    await File('${dir.path}/library.json').writeAsString('{"entries": [{"id": "1", "na'); // cortada
    final store = LibraryStore();
    await store.initAt(dir);
    expect(store.data.entries, isEmpty);
    final kept = dir.listSync().whereType<File>().where((f) => f.path.contains('library.dañada.')).toList();
    expect(kept, hasLength(1));
    expect(await kept.single.readAsString(), contains('"na'));
    // Guardar después no pisa la copia y deja una lista válida.
    await store.importFile(originalName: 'nuevo.txt', bytes: [1]);
    expect(File('${dir.path}/library.json').existsSync(), isTrue);
    expect(File('${dir.path}/library.json.tmp').existsSync(), isFalse);
    await dir.delete(recursive: true);
  });

  test('importar varios archivos en el mismo milisegundo no repite el identificador', () async {
    final dir = await Directory.systemTemp.createTemp('lector_lib');
    final fixed = DateTime(2026, 10, 26, 12);
    final store = LibraryStore(clock: () => fixed);
    await store.initAt(dir);
    final ids = <String>{};
    for (var i = 0; i < 20; i++) {
      final e = await store.importFile(originalName: 'doc$i.txt', bytes: [i]);
      ids.add(e.id);
    }
    expect(ids.length, 20);
    expect(store.data.entries.length, 20);
    for (final e in store.data.entries) {
      expect(await File(e.storedPath).exists(), isTrue);
    }
    await dir.delete(recursive: true);
  });
}
