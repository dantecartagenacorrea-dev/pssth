import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../domain/spanish_numbers.dart';
import '../../domain/spanish_phonemizer.dart';

/// Sintetiza con una voz Piper o con Supertonic vía sherpa-onnx, en un isolate
/// propio para no bloquear la interfaz. Devuelve audio WAV de 16 bits.
class KokoroWorker {
  KokoroWorker._(this._isolate, this._commands);
  final Isolate _isolate;
  final SendPort _commands;
  var _nextId = 0;

  /// Una voz Piper: [onnx] es el modelo y [tokens] sus fonemas. Carga el
  /// modelo (unos segundos); lanza si falta algún archivo o falla.
  static Future<KokoroWorker> startPiper(String onnx, String tokens, {int threads = 2}) =>
      _start([onnx, threads, tokens, 'piper']);

  /// Supertonic: [dir] es la carpeta con sus archivos.
  static Future<KokoroWorker> startSupertonic(String dir, {int threads = 2}) =>
      _start([dir, threads, '', 'supertonic']);

  static Future<KokoroWorker> _start(List<Object> config) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_entry, [ready.sendPort, ...config]);
    final first = await ready.first;
    ready.close();
    if (first is SendPort) return KokoroWorker._(isolate, first);
    isolate.kill(priority: Isolate.immediate);
    throw StateError('Voz natural: $first');
  }

  Future<Uint8List> synthesize(String text, {required int speaker, required double speed}) async {
    final reply = ReceivePort();
    _commands.send([_nextId++, text, speaker, speed, reply.sendPort]);
    final msg = await reply.first;
    reply.close();
    if (msg is TransferableTypedData) {
      return msg.materialize().asUint8List();
    }
    throw StateError('Voz natural: $msg');
  }

  void dispose() {
    _commands.send(null);
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }
}

void _entry(List<Object> args) {
  final out = args[0] as SendPort;
  final dir = args[1] as String;
  final threads = args[2] as int;
  final tokens = args[3] as String; // en Piper: el archivo de fonemas
  final supertonic = args[4] == 'supertonic';
  sherpa.OfflineTts tts;
  try {
    sherpa.initBindings();
    final config = sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: supertonic ? const sherpa.OfflineTtsVitsModelConfig() : sherpa.OfflineTtsVitsModelConfig(model: dir, tokens: tokens),
        supertonic: supertonic
            ? sherpa.OfflineTtsSupertonicModelConfig(
                durationPredictor: '$dir/duration_predictor.int8.onnx',
                textEncoder: '$dir/text_encoder.int8.onnx',
                vectorEstimator: '$dir/vector_estimator.int8.onnx',
                vocoder: '$dir/vocoder.int8.onnx',
                ttsJson: '$dir/tts.json',
                unicodeIndexer: '$dir/unicode_indexer.bin',
                voiceStyle: '$dir/voice.bin',
              )
            : const sherpa.OfflineTtsSupertonicModelConfig(),
        numThreads: threads,
        debug: false,
        provider: 'cpu',
      ),
      maxNumSentences: 1,
    );
    tts = sherpa.OfflineTts(config);
  } catch (e) {
    out.send('$e');
    return;
  }
  final port = ReceivePort();
  out.send(port.sendPort);
  port.listen((message) {
    if (message == null) {
      tts.free();
      port.close();
      return;
    }
    final m = message as List;
    final reply = m[4] as SendPort;
    try {
      if (supertonic) {
        // Lee el texto directo; las cifras se le pasan ya en palabras.
        final text = numbersToWords(m[1] as String).trim();
        if (text.isEmpty) {
          reply.send(TransferableTypedData.fromList([_wav(Float32List(2400), tts.sampleRate)]));
          return;
        }
        final audio = tts.generateWithConfig(
          text: text,
          config: sherpa.OfflineTtsGenerationConfig(sid: m[2] as int, speed: m[3] as double, extra: const {'lang': 'es'}),
        );
        reply.send(TransferableTypedData.fromList([_wav(audio.samples, audio.sampleRate)]));
        return;
      }
      // Sin espeak-ng (sherpa-onnx 2.0) Piper no sabe leer español: se le
      // pasan los fonemas del conversor propio, una lista por frase.
      final frases = phonemizeSpanish(m[1] as String);
      if (frases.isEmpty) {
        reply.send(TransferableTypedData.fromList([_wav(Float32List(2400), tts.sampleRate)]));
        return;
      }
      final audio = tts.generateWithConfig(
        text: '',
        config: sherpa.OfflineTtsGenerationConfig(
          sid: m[2] as int,
          speed: m[3] as double,
          phonemeCodepoints: [for (final f in frases) f.runes.toList()],
        ),
      );
      reply.send(TransferableTypedData.fromList([_wav(audio.samples, audio.sampleRate)]));
    } catch (e) {
      reply.send('$e');
    }
  });
}

/// WAV PCM de 16 bits, mono, a partir de muestras float [-1, 1].
Uint8List _wav(Float32List samples, int sampleRate) {
  final dataLen = samples.length * 2;
  final b = ByteData(44 + dataLen);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + dataLen, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i] * 32767).round().clamp(-32768, 32767);
    b.setInt16(44 + i * 2, v, Endian.little);
  }
  return b.buffer.asUint8List();
}
