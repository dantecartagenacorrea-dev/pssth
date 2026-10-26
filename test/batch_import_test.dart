import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/batch_import.dart';
import 'package:lector_pdf/data/library_store.dart';
import 'package:lector_pdf/domain/library_entry.dart';

void main() {
  late Directory dir;
  late Directory src;
  late LibraryStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lector_lote');
    src = await Directory.systemTemp.createTemp('lector_origen');
    store = LibraryStore();
    await store.initAt(dir);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
    await src.delete(recursive: true);
  });

  Future<BatchFile> archivo(String name, String content) async {
    final f = File('${src.path}/$name');
    await f.writeAsString(content);
    return BatchFile(name: name, path: f.path);
  }

  Future<LibraryEntry> sinAudio(String path, String title) =>
      throw StateError('no debería transcribir');

  test('importa todos los documentos del lote sin abrirlos', () async {
    final files = [
      await archivo('a.txt', 'uno'),
      await archivo('b.pdf', 'dos'),
      await archivo('c.jpg', 'tres'),
    ];
    final r = await importBatch(files: files, store: store, importAudio: sinAudio);
    expect(r.imported, 3);
    expect(r.failed, isEmpty);
    expect(store.data.entries.map((e) => e.name), containsAll(['a.txt', 'b.pdf', 'c.jpg']));
  });

  test('un archivo ilegible no detiene el lote y se informa', () async {
    final files = [
      await archivo('a.txt', 'uno'),
      const BatchFile(name: 'roto.pdf', path: null),
      BatchFile(name: 'borrado.pdf', path: '${src.path}/no_existe.pdf'),
      await archivo('vacio.txt', ''),
      await archivo('b.txt', 'dos'),
    ];
    final r = await importBatch(files: files, store: store, importAudio: sinAudio);
    expect(r.imported, 2);
    expect(r.failed, ['roto.pdf', 'borrado.pdf', 'vacio.txt']);
    expect(r.summary, contains('No se pudieron importar 3'));
  });

  test('los que ya estaban en la biblioteca se cuentan aparte', () async {
    final a = await archivo('a.txt', 'uno');
    await store.importFile(originalName: 'a.txt', bytes: utf8.encode('uno'));
    final r = await importBatch(
      files: [a, await archivo('b.txt', 'dos')],
      store: store,
      importAudio: sinAudio,
    );
    expect(r.imported, 1);
    expect(r.alreadyThere, 1);
    expect(store.data.entries.length, 2);
  });

  test('con más de 50 archivos importa los primeros 50 y avisa', () async {
    final files = [for (var i = 0; i < 53; i++) await archivo('d$i.txt', 'texto $i')];
    final r = await importBatch(files: files, store: store, importAudio: sinAudio);
    expect(r.imported, maxBatchFiles);
    expect(r.leftOut, 3);
    expect(store.data.entries.any((e) => e.name == 'd50.txt'), isFalse);
    expect(r.summary, contains('quedaron fuera 3'));
  });

  test('los audios se transcriben uno tras otro, después de los documentos', () async {
    final orden = <String>[];
    Future<LibraryEntry> transcribir(String path, String title) async {
      orden.add(title);
      return store.importFile(originalName: '$title.txt', bytes: utf8.encode('transcripción'));
    }

    final files = [
      await archivo('clase1.m4a', 'audio'),
      await archivo('apunte.pdf', 'pdf'),
      await archivo('clase2.mp3', 'audio'),
    ];
    final avance = <String>[];
    final r = await importBatch(
      files: files,
      store: store,
      importAudio: transcribir,
      onProgress: (i, total, f) => avance.add('$i/$total ${f.name}'),
    );
    expect(orden, ['clase1', 'clase2']);
    expect(avance, ['1/3 apunte.pdf', '2/3 clase1.m4a', '3/3 clase2.mp3']);
    expect(r.imported, 3);
  });

  test('si falla la transcripción de un audio, sigue con el resto', () async {
    Future<LibraryEntry> transcribir(String path, String title) async {
      if (title == 'malo') throw const FileSystemException('sin acceso');
      return store.importFile(originalName: '$title.txt', bytes: utf8.encode('ok'));
    }

    final r = await importBatch(
      files: [await archivo('malo.wav', 'x'), await archivo('bueno.wav', 'y')],
      store: store,
      importAudio: transcribir,
    );
    expect(r.imported, 1);
    expect(r.failed, ['malo.wav']);
  });
}
