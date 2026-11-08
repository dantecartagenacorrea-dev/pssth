import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/model_queue.dart';
import 'package:lector_pdf/data/model_store.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('models'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('instalado solo cuando están todos los archivos requeridos', () async {
    final store = ModelStore(tmp);
    expect(store.isInstalled(dictationModel), isFalse);
    final d = store.dirFor(dictationModel)..createSync(recursive: true);
    for (final f in dictationModel.requiredFiles.take(3)) {
      File('${d.path}/$f').writeAsStringSync('x');
    }
    expect(store.isInstalled(dictationModel), isFalse);
    File('${d.path}/${dictationModel.requiredFiles[3]}').writeAsStringSync('x');
    expect(store.isInstalled(dictationModel), isTrue);
    expect(await store.installedBytes(dictationModel), 4);
    await store.remove(dictationModel);
    expect(store.isInstalled(dictationModel), isFalse);
  });

  test('las fichas de modelos apuntan al repositorio oficial y declaran tamaño y hash', () {
    expect(dictationModel.url, startsWith('https://github.com/k2-fsa/sherpa-onnx/releases/download/'));
    expect(dictationModel.sha256, hasLength(64));
    for (final m in [dictationModel, whisperBaseModel, supertonicModel]) {
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

  test('al iniciar quita lo retirado y lo que la voz instalada no usa', () async {
    final store = ModelStore(tmp);
    final d = store.dirFor(dictationModel)..createSync(recursive: true);
    for (final f in dictationModel.requiredFiles) {
      File('${d.path}/$f').writeAsStringSync('x');
    }
    Directory('${tmp.path}/kokoro').createSync();
    Directory('${tmp.path}/parakeet').createSync();
    Directory('${tmp.path}/qwen3').createSync();
    Directory('${tmp.path}/piper-ald').createSync();
    Directory('${tmp.path}/whisper-small').createSync();
    await store.removeRetired();
    final left = d.listSync().map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty)).toSet();
    expect(left, {...dictationModel.requiredFiles});
    expect(store.isInstalled(dictationModel), isTrue);
    expect(Directory('${tmp.path}/kokoro').existsSync(), isFalse);
    expect(Directory('${tmp.path}/parakeet').existsSync(), isFalse);
    expect(Directory('${tmp.path}/qwen3').existsSync(), isFalse);
    expect(Directory('${tmp.path}/piper-ald').existsSync(), isFalse);
    expect(Directory('${tmp.path}/whisper-small').existsSync(), isFalse);
  });

  test('solo los modelos de voz obligan a releer las voces', () {
    expect(piperVoiceModels.every(isVoiceModel), isTrue);
    expect(isVoiceModel(whisperBaseModel), isFalse);
    expect(isVoiceModel(dictationModel), isFalse);
  });

  test('la voz Luna (Supertonic) es la que se baja primero y todos sus archivos están verificados', () {
    expect(ModelQueue.all.first, supertonicModel);
    expect(isVoiceModel(supertonicModel), isTrue);
    expect(supertonicModel.files.map((f) => f.name), supertonicModel.requiredFiles);
    expect(supertonicModel.files.every((f) => f.sha256.length == 64), isTrue);
    expect(supertonicModel.files.fold<int>(0, (n, f) => n + f.sizeBytes), supertonicModel.sizeBytes);
  });

  test('El dictado en español se baja solo en Android y su paquete está verificado', () {
    expect(ModelQueue.all, Platform.isAndroid ? contains(dictationModel) : isNot(contains(dictationModel)));
    expect(dictationModel.requiredFiles, ['encoder.int8.onnx', 'decoder.int8.onnx', 'joiner.int8.onnx', 'tokens.txt']);
    // Un solo paquete verificado por su huella; Parakeet se borra al iniciar.
    expect(dictationModel.sha256.length, 64);
    expect(dictationModel.prune, ['test_wavs']);
  });

  test('cancelar a mitad de la descarga no deja nada instalado ni archivos sueltos', () async {
    // Servidor local que manda el archivo de a poco, sin terminar nunca.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      req.response.contentLength = 1000000;
      for (var i = 0; i < 1000; i++) {
        req.response.add(List.filled(100, 1));
        await req.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await req.response.close();
    });
    final store = ModelStore(tmp);
    final spec = ModelSpec(
      id: 'lento',
      title: 'Lento',
      url: 'http://127.0.0.1:${server.port}',
      sizeBytes: 1000000,
      sha256: '',
      extractedDir: '',
      requiredFiles: const ['a.bin'],
      files: [ModelFile('a.bin', 'http://127.0.0.1:${server.port}/a.bin', 1000000, 'x' * 64)],
    );
    final install = store.install(spec);
    while (store.progressOf(spec)?.fraction == null || store.progressOf(spec)!.fraction! <= 0) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    store.cancel(spec);
    await expectLater(install, throwsA(isA<ModelInstallCancelled>()));
    expect(store.isInstalled(spec), isFalse);
    expect(store.isInstalling(spec), isFalse);
    expect(tmp.listSync().where((e) => e.path.contains('.tmp_')), isEmpty);
  });
}
