import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/pronunciation_store.dart';
import 'package:lector_pdf/domain/text_normalizer.dart';

void main() {
  test('diccionario persiste y se aplica al normalizador', () async {
    final dir = await Directory.systemTemp.createTemp('pron');
    final f = File('${dir.path}/p.json');
    final s1 = PronunciationStore(f);
    await s1.set('SIN', 'Servicio de Impuestos Nacionales');
    await s1.set('  ', 'ignorada');
    final s2 = PronunciationStore(f);
    final entries = await s2.load();
    expect(entries.length, 1);
    final n = TextNormalizer(dictionary: entries);
    expect(n.normalize('El SIN notifica'), 'El Servicio de Impuestos Nacionales notifica');
    await s2.remove('SIN');
    expect(await PronunciationStore(f).load(), isEmpty);
    await dir.delete(recursive: true);
  });
}
