import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/model_store.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('models'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('instalado solo cuando están todos los archivos requeridos', () async {
    final store = ModelStore(tmp);
    expect(store.isInstalled(kokoroEsModel), isFalse);
    final d = store.dirFor(kokoroEsModel)..createSync(recursive: true);
    for (final f in kokoroEsModel.requiredFiles.take(2)) {
      File('${d.path}/$f').writeAsStringSync('x');
    }
    expect(store.isInstalled(kokoroEsModel), isFalse);
    // Desde sherpa-onnx 2.0 no hace falta espeak-ng-data.
    File('${d.path}/${kokoroEsModel.requiredFiles[2]}').writeAsStringSync('x');
    expect(store.isInstalled(kokoroEsModel), isTrue);
    expect(await store.installedBytes(kokoroEsModel), 3);
    await store.remove(kokoroEsModel);
    expect(store.isInstalled(kokoroEsModel), isFalse);
  });

  test('las fichas de modelos apuntan al repositorio oficial y declaran tamaño y hash', () {
    expect(kokoroEsModel.url, startsWith('https://github.com/k2-fsa/sherpa-onnx/releases/download/'));
    expect(kokoroEsModel.sha256, hasLength(64));
    for (final m in [kokoroEsModel, whisperBaseModel]) {
      expect(m.sizeBytes, greaterThan(50 * 1024 * 1024));
      expect(m.sizeLabel, endsWith(' MB'));
    }
  });

  test('los modelos por archivos traen solo lo requerido, con huella y tamaño que suman', () {
    for (final m in [whisperBaseModel]) {
      expect(m.files.map((f) => f.name), m.requiredFiles);
      expect(m.files.fold<int>(0, (a, f) => a + f.sizeBytes), m.sizeBytes);
      for (final f in m.files) {
        expect(f.url, startsWith('https://huggingface.co/'));
        expect(f.sha256, hasLength(64));
      }
    }
  });

  test('una URL inválida produce un error legible y no deja basura', () async {
    final store = ModelStore(tmp);
    const bad = ModelSpec(
      id: 'bad',
      title: 'x',
      url: 'https://127.0.0.1:9/nada.tar.bz2',
      sizeBytes: 100,
      sha256: '0',
      extractedDir: 'x',
      requiredFiles: ['a'],
    );
    await expectLater(store.install(bad), throwsA(isA<ModelInstallException>()));
    expect(tmp.listSync().where((e) => e.path.contains('.tmp_')), isEmpty);
  });
}
