import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../domain/wav_audio.dart';
import 'speech_transcriber.dart';

/// Transcripción offline con Whisper (sherpa-onnx) para cualquier plataforma.
/// Trabaja por segmentos (Whisper admite ~30 s por pasada) en un isolate.
class WhisperTranscriber implements SpeechTranscriber {
  WhisperTranscriber({required this.modelDir, this.onProgress});

  final String modelDir;

  /// (segmentos listos, total)
  final void Function(int done, int total)? onProgress;

  bool get _installed =>
      File('$modelDir/base-encoder.int8.onnx').existsSync() &&
      File('$modelDir/base-decoder.int8.onnx').existsSync() &&
      File('$modelDir/base-tokens.txt').existsSync();

  @override
  Future<bool> isAvailable({String locale = 'es-ES'}) async => _installed;

  @override
  Future<String> transcribe(String audioPath, {String locale = 'es-ES'}) async {
    if (!_installed) throw TranscriptionUnavailable();
    final WavAudio wav;
    try {
      wav = WavAudio.parse(await File(audioPath).readAsBytes());
    } catch (_) {
      throw TranscriptionUnavailable('La grabación no está en un formato transcribible.');
    }
    if (!wav.hasSound) return '';
    final parts = wav.splitBySilence();
    final lang = locale.split(RegExp('[-_]')).first.toLowerCase();

    final reply = ReceivePort();
    // onExit manda null si el isolate termina sin avisar: así no se espera para siempre.
    final isolate = await Isolate.spawn(
      _entry,
      [reply.sendPort, modelDir, lang, wav.sampleRate, parts],
      onExit: reply.sendPort,
    );
    final out = <String>[];
    String? error;
    try {
      // Se espera a que el isolate libere el modelo (cientos de MB fuera de Dart)
      // antes de cerrarlo: si se mata antes, esa memoria queda ocupada.
      await for (final msg in reply) {
        if (msg == null || (msg is List && msg.isNotEmpty && msg[0] == _freed[0])) break;
        if (msg is String) {
          out.add(msg);
          onProgress?.call(out.length, parts.length);
        } else if (msg is List && msg.isNotEmpty && msg[0] == 'error') {
          error = '${msg[1]}';
        }
      }
    } finally {
      reply.close();
      isolate.kill(priority: Isolate.immediate);
    }
    if (error != null) throw TranscriptionUnavailable(error);
    return out.map((s) => s.trim()).where((s) => s.isNotEmpty).join(' ');
  }
}

/// Aviso del isolate: ya liberó el modelo. Es una lista para no confundirlo
/// con el texto de un tramo.
const _freed = ['freed'];

void _entry(List<Object> args) {
  final out = args[0] as SendPort;
  final dir = args[1] as String;
  final lang = args[2] as String;
  final rate = args[3] as int;
  final parts = args[4] as List<Float32List>;
  sherpa.OfflineRecognizer rec;
  try {
    sherpa.initBindings();
    rec = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: '$dir/base-encoder.int8.onnx',
            decoder: '$dir/base-decoder.int8.onnx',
            language: lang,
            task: 'transcribe',
          ),
          tokens: '$dir/base-tokens.txt',
          numThreads: 4,
          debug: false,
        ),
      ),
    );
  } catch (e) {
    out.send(['error', 'No se pudo cargar el modelo de transcripción: $e']);
    return;
  }
  try {
    for (final p in parts) {
      final stream = rec.createStream();
      stream.acceptWaveform(samples: p, sampleRate: rate);
      rec.decode(stream);
      final text = rec.getResult(stream).text;
      stream.free();
      out.send(text);
    }
  } catch (e) {
    out.send(['error', '$e']);
  } finally {
    rec.free();
    out.send(_freed);
  }
}
