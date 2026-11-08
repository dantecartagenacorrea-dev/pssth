import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/platform/nemo_transcriber.dart';
import 'package:lector_pdf/platform/speech_transcriber.dart';
import 'package:lector_pdf/platform/whisper_transcriber.dart';

class _FakeEngine implements SpeechTranscriber {
  _FakeEngine(this.name, {required this.available});
  final String name;
  final bool available;

  @override
  Future<bool> isAvailable({String locale = 'es-ES'}) async => available;
  @override
  Future<String> transcribe(String audioPath, {String locale = 'es-ES'}) async => name;
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('whisper'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('Whisper necesita todos sus archivos', () async {
    final base = WhisperTranscriber(modelDir: dir.path);
    expect(await base.isAvailable(), isFalse);
    for (final name in ['encoder.int8.onnx', 'decoder.int8.onnx']) {
      File('${dir.path}/base-$name').writeAsStringSync('x');
    }
    expect(await base.isAvailable(), isFalse);
    File('${dir.path}/base-tokens.txt').writeAsStringSync('x');
    expect(await base.isAvailable(), isTrue);
  });

  test('El dictado necesita todos sus archivos', () async {
    final parakeet = NemoTranscriber(modelDir: dir.path);
    expect(await parakeet.isAvailable(), isFalse);
    for (final name in ['encoder.int8.onnx', 'decoder.int8.onnx', 'joiner.int8.onnx']) {
      File('${dir.path}/$name').writeAsStringSync('x');
    }
    expect(await parakeet.isAvailable(), isFalse);
    File('${dir.path}/tokens.txt').writeAsStringSync('x');
    expect(await parakeet.isAvailable(), isTrue);
  });

  test('se usa el primer motor disponible: el dictado antes que Base', () async {
    final both = CompositeTranscriber([_FakeEngine('parakeet', available: true), _FakeEngine('base', available: true)]);
    expect(await both.transcribe('a.wav'), 'parakeet');

    final onlyBase = CompositeTranscriber([
      _FakeEngine('parakeet', available: false),
      _FakeEngine('base', available: true),
    ]);
    expect(await onlyBase.transcribe('a.wav'), 'base');
  });
}
