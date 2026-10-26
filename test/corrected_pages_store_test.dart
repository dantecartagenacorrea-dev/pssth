import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/corrected_pages_store.dart';

void main() {
  late Directory dir;
  late CorrectedPagesStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lector_ia');
    store = CorrectedPagesStore(dir);
  });

  tearDown(() => dir.delete(recursive: true));

  test('guarda y recupera las páginas corregidas de un documento', () async {
    await store.save('d1', model: 'qwen', pages: {3: 'Tres.', 0: 'Cero.'});
    expect(await store.load('d1', model: 'qwen'), {3: 'Tres.', 0: 'Cero.'});
    expect(await File('${dir.path}/d1.ia.json').exists(), isTrue);
  });

  test('con otro modelo no se reutiliza lo corregido', () async {
    await store.save('d1', model: 'qwen', pages: {1: 'Uno.'});
    expect(await store.load('d1', model: 'llama'), isEmpty);
  });

  test('sin archivo o con archivo dañado devuelve vacío', () async {
    expect(await store.load('nada', model: 'qwen'), isEmpty);
    await File('${dir.path}/roto.ia.json').writeAsString('{no es json');
    expect(await store.load('roto', model: 'qwen'), isEmpty);
  });
}
