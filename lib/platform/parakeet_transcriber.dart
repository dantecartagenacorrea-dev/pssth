import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../domain/live_audio.dart';
import '../domain/wav_audio.dart';
import '../domain/window_merge.dart';
import 'speech_transcriber.dart';

/// Parakeet necesita contexto: en trozos cortos se salta frases enteras.
const _windowSeconds = 40;
const _overlapSeconds = 10;

/// Silencio alrededor de cada ventana, para que no pierda la primera palabra.
const _marginSeconds = 0.5;

/// Avisos del isolate: ya liberó el modelo, o debe cerrar.
const _freed = 'freed';
const _close = 'close';

/// Transcripción offline con Parakeet TDT v3 (sherpa-onnx) en un isolate.
class ParakeetTranscriber implements SpeechTranscriber {
  ParakeetTranscriber({required this.modelDir, this.onProgress});

  final String modelDir;

  /// (ventanas listas, total)
  final void Function(int done, int total)? onProgress;

  bool get _installed =>
      File('$modelDir/encoder.int8.onnx').existsSync() &&
      File('$modelDir/decoder.int8.onnx').existsSync() &&
      File('$modelDir/joiner.int8.onnx').existsSync() &&
      File('$modelDir/tokens.txt').existsSync();

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
    final rate = wav.sampleRate;
    final spans = audioWindows(wav.samples.length, window: _windowSeconds * rate, overlap: _overlapSeconds * rate);

    final reply = ReceivePort();
    final isolate = await Isolate.spawn(_entry, [reply.sendPort, modelDir, rate, wav.samples, spans]);
    final windows = <TimedWindow>[];
    try {
      await for (final msg in reply) {
        if (msg is List && msg.isNotEmpty && msg[0] == 'error') {
          throw TranscriptionUnavailable('${msg[1]}');
        }
        if (msg == _freed) break;
        if (msg is! List) continue;
        final (start, end) = spans[windows.length];
        windows.add(
          TimedWindow(
            start: start / rate,
            end: end / rate,
            tokens: (msg[0] as List).cast<String>(),
            times: [for (final t in msg[1] as List) (t as double) - _marginSeconds],
          ),
        );
        onProgress?.call(windows.length, spans.length);
      }
    } finally {
      reply.close();
      isolate.kill(priority: Isolate.immediate);
    }
    return mergeWindows(windows);
  }
}

void _entry(List<Object> args) {
  final out = args[0] as SendPort;
  final dir = args[1] as String;
  final rate = args[2] as int;
  final samples = args[3] as Float32List;
  final spans = args[4] as List<(int, int)>;
  sherpa.OfflineRecognizer rec;
  try {
    rec = _newRecognizer(dir);
  } catch (e) {
    out.send(['error', 'No se pudo cargar el modelo de transcripción: $e']);
    return;
  }
  try {
    for (final (start, end) in spans) {
      out.send(_recognize(rec, Float32List.sublistView(samples, start, end), rate));
    }
  } catch (e) {
    out.send(['error', '$e']);
  } finally {
    rec.free();
    out.send(_freed);
  }
}

sherpa.OfflineRecognizer _newRecognizer(String dir) {
  sherpa.initBindings();
  return sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        transducer: sherpa.OfflineTransducerModelConfig(
          encoder: '$dir/encoder.int8.onnx',
          decoder: '$dir/decoder.int8.onnx',
          joiner: '$dir/joiner.int8.onnx',
        ),
        modelType: 'nemo_transducer',
        tokens: '$dir/tokens.txt',
        numThreads: 4,
        debug: false,
      ),
    ),
  );
}

/// Reconoce una ventana con silencio alrededor. Devuelve `[piezas, tiempos]`.
List<Object> _recognize(sherpa.OfflineRecognizer rec, Float32List samples, int rate) {
  final margin = (_marginSeconds * rate).round();
  final padded = Float32List(samples.length + 2 * margin)..setAll(margin, samples);
  final stream = rec.createStream();
  stream.acceptWaveform(samples: padded, sampleRate: rate);
  rec.decode(stream);
  final result = rec.getResult(stream);
  stream.free();
  return [result.tokens, result.timestamps];
}

/// Transcribe mientras se graba: el modelo se carga al empezar y cada ventana se
/// reconoce apenas está completa, así al terminar queda poco o nada por hacer.
class ParakeetLiveSession {
  ParakeetLiveSession._(this._rate, this._onText, this._live);

  final int _rate;
  final void Function(String text) _onText;
  final LiveWindows _live;
  final _reply = ReceivePort();
  final _spans = <(int, int)>[];
  final _windows = <TimedWindow>[];
  final _done = Completer<String>();
  final _ready = Completer<SendPort>();
  bool _finished = false;

  static Future<ParakeetLiveSession> start({
    required String modelDir,
    required int sampleRate,
    required void Function(String text) onText,
  }) async {
    final session = ParakeetLiveSession._(
      sampleRate,
      onText,
      LiveWindows(window: _windowSeconds * sampleRate, overlap: _overlapSeconds * sampleRate),
    );
    session._reply.listen(session._onMessage);
    await Isolate.spawn(_liveEntry, [session._reply.sendPort, modelDir, sampleRate]);
    return session;
  }

  /// Más audio del micrófono.
  void add(Float32List samples) => _live.add(samples).forEach(_submit);

  /// Termina con lo que falta y devuelve todo el texto.
  Future<String> finish() {
    final last = _live.finish();
    if (last != null) _submit(last);
    _finished = true;
    _completeIfDone();
    return _done.future;
  }

  void cancel() {
    _stopWorker();
    if (!_done.isCompleted) _done.completeError(TranscriptionUnavailable('Grabación cancelada.'));
    unawaited(_done.future.catchError((_) => ''));
  }

  void _submit(AudioWindow w) {
    _spans.add((w.start, w.end));
    unawaited(_ready.future.then((port) => port.send(w.samples)));
  }

  void _onMessage(Object? msg) {
    if (msg is SendPort) {
      _ready.complete(msg);
    } else if (msg is List && msg.isNotEmpty && msg[0] == 'error') {
      if (!_done.isCompleted) _done.completeError(TranscriptionUnavailable('${msg[1]}'));
      _stopWorker();
    } else if (msg is List) {
      final (start, end) = _spans[_windows.length];
      _windows.add(
        TimedWindow(
          start: start / _rate,
          end: end / _rate,
          tokens: (msg[0] as List).cast<String>(),
          times: [for (final t in msg[1] as List) (t as double) - _marginSeconds],
        ),
      );
      _onText(mergeWindows(_windows));
      _completeIfDone();
    }
  }

  void _completeIfDone() {
    if (!_finished || _windows.length != _spans.length || _done.isCompleted) return;
    _done.complete(mergeWindows(_windows));
    _stopWorker();
  }

  /// El isolate termina solo tras liberar el modelo: matarlo lo dejaría en memoria.
  void _stopWorker() {
    _reply.close();
    unawaited(_ready.future.then((port) => port.send(_close)));
  }
}

void _liveEntry(List<Object> args) {
  final out = args[0] as SendPort;
  final dir = args[1] as String;
  final rate = args[2] as int;
  final input = ReceivePort();
  out.send(input.sendPort);
  final sherpa.OfflineRecognizer rec;
  try {
    rec = _newRecognizer(dir);
  } catch (e) {
    out.send(['error', 'No se pudo cargar el modelo de transcripción: $e']);
    input.close();
    return;
  }
  input.listen((msg) {
    if (msg == _close) {
      rec.free();
      input.close();
      return;
    }
    try {
      out.send(_recognize(rec, msg as Float32List, rate));
    } catch (e) {
      out.send(['error', '$e']);
    }
  });
}
