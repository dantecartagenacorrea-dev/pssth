import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/model_queue.dart';
import 'package:lector_pdf/data/model_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('queue');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('sin preguntar no baja nada, ni siquiera lo que se consulta', () async {
    final queue = ModelQueue(ModelStore(tmp), () async {});
    await queue.load();
    expect(queue.consent, isNull);
    queue.prioritize(whisperBaseModel);
    expect(queue.busy, isFalse);
  });

  test('la respuesta se recuerda', () async {
    final queue = ModelQueue(ModelStore(tmp), () async {});
    await queue.setConsent(false);
    final again = ModelQueue(ModelStore(tmp), () async {});
    await again.load();
    expect(again.consent, isFalse);
  });

  test('la voz baja primero y lo instalado no cuenta como faltante', () async {
    final store = ModelStore(tmp);
    final queue = ModelQueue(store, () async {});
    expect(ModelQueue.all.first, kokoroEsModel);
    final before = queue.missingBytes;
    final d = store.dirFor(kokoroEsModel)..createSync(recursive: true);
    for (final f in kokoroEsModel.requiredFiles) {
      File('${d.path}/$f').writeAsStringSync('x');
    }
    expect(queue.missing, isNot(contains(kokoroEsModel)));
    expect(queue.missingBytes, before - kokoroEsModel.sizeBytes);
  });
}
