import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/document_loader.dart';
import 'package:lector_pdf/data/ocr_cache.dart';
import 'package:lector_pdf/domain/language_detector.dart';
import 'package:lector_pdf/domain/library_entry.dart';
import 'package:lector_pdf/domain/text_paginator.dart';
import 'package:lector_pdf/ocr/ocr_engine.dart';

class FakeOcr implements OcrEngine {
  FakeOcr({this.available = true});
  final bool available;
  int calls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<String> recognize(String imagePath, {List<String> languages = const []}) async {
    calls++;
    return 'Texto reconocido de prueba número $calls.';
  }
}

void main() {
  test('detecta español e inglés', () {
    expect(
      detectLanguageHeuristic('El contrato de la empresa se firmó en el mes de enero con los socios y para el cliente.'),
      'es',
    );
    expect(
      detectLanguageHeuristic('The company signed the contract in January with the partners and it was for the client.'),
      'en',
    );
    expect(detectLanguageHeuristic('hola'), isNull);
  });

  test('paginateText agrupa párrafos y maneja vacío', () {
    expect(paginateText('   '), ['']);
    final pages = paginateText('${'a' * 50}\n\n${'b' * 50}\n\n${'c' * 50}', pageChars: 120);
    expect(pages.length, 2);
  });

  test('decodeText cae a Latin-1', () {
    expect(decodeText([0x63, 0x61, 0x66, 0xE9]), 'café');
  });

  test('OcrCache persiste y no repite páginas', () async {
    final dir = await Directory.systemTemp.createTemp('ocrc');
    final f = File('${dir.path}/c.json');
    final c1 = await OcrCache.open(f);
    expect(c1.has(2), isFalse);
    await c1.put(2, 'hola');
    final c2 = await OcrCache.open(f);
    expect(c2.get(2), 'hola');
    await dir.delete(recursive: true);
  });

  test('imagen: OCR una sola vez y luego sale de la caché', () async {
    final dir = await Directory.systemTemp.createTemp('docl');
    final img = File('${dir.path}/foto.png')..writeAsBytesSync([1, 2, 3]);
    final entry = LibraryEntry(
      id: 'x1',
      name: 'foto.png',
      storedPath: img.path,
      pageCount: 0,
      totalChunks: 0,
      kind: 'image',
    );
    final engine = FakeOcr();
    final loader = DocumentLoader(cacheDir: dir, ocr: engine);

    final doc = await loader.load(entry);
    expect(doc.pendingOcr, [0]);
    final results = await loader.runOcr(entry, doc).toList();
    expect(results.single.page, 0);
    expect(engine.calls, 1);

    final doc2 = await loader.load(entry);
    expect(doc2.pendingOcr, isEmpty);
    expect(doc2.pages.single, contains('Texto reconocido'));
    expect(engine.calls, 1);
    await dir.delete(recursive: true);
  });

  test('sin OCR disponible lanza OcrUnavailable', () async {
    final dir = await Directory.systemTemp.createTemp('docl2');
    final img = File('${dir.path}/f.png')..writeAsBytesSync([1]);
    final entry = LibraryEntry(
      id: 'x2', name: 'f.png', storedPath: img.path,
      pageCount: 0, totalChunks: 0, kind: 'image',
    );
    final loader = DocumentLoader(cacheDir: dir, ocr: FakeOcr(available: false));
    final doc = await loader.load(entry);
    expect(loader.runOcr(entry, doc).toList(), throwsA(isA<OcrUnavailable>()));
    await dir.delete(recursive: true);
  });

  test('TXT se pagina y no requiere OCR', () async {
    final dir = await Directory.systemTemp.createTemp('docl3');
    final f = File('${dir.path}/n.txt')..writeAsStringSync('Primer párrafo con texto suficiente.\n\nSegundo párrafo.');
    final entry = LibraryEntry(
      id: 'x3', name: 'n.txt', storedPath: f.path,
      pageCount: 0, totalChunks: 0, kind: 'txt',
    );
    final doc = await DocumentLoader(cacheDir: dir, ocr: FakeOcr()).load(entry);
    expect(doc.pendingOcr, isEmpty);
    expect(doc.pages.first, contains('Primer'));
    await dir.delete(recursive: true);
  });
}
