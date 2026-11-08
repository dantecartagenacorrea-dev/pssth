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

  test('al arrancar no baja nada que no se haya pedido', () async {
    final queue = ModelQueue(ModelStore(tmp), () async {});
    await queue.start();
    expect(queue.busy, isFalse);
  });

  test('lo ya instalado no se vuelve a bajar al pedirlo', () {
    final store = ModelStore(tmp);
    final queue = ModelQueue(store, () async {});
    final d = store.dirFor(supertonicModel)..createSync(recursive: true);
    for (final f in supertonicModel.requiredFiles) {
      File('${d.path}/$f').writeAsStringSync('x');
    }
    queue.prioritize(supertonicModel);
    expect(store.isInstalling(supertonicModel), isFalse);
  });
}
