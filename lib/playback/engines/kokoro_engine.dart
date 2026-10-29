import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/audio_cache.dart';
import '../../domain/wav_audio.dart';
import '../../domain/word_timing.dart';
import '../audio_prefetcher.dart';
import '../tts_engine.dart';
import 'kokoro_worker.dart';

/// Voz natural local (Kokoro-82M int8 vía sherpa-onnx). Offline, sin servidores.
/// Sintetiza por fragmentos, guarda el audio en caché y prepara los siguientes.
class KokoroEngine extends TtsEngine implements SynthesizingEngine {
  KokoroEngine({required this.modelDir, required this.cache});

  /// Carpeta del modelo (model.int8.onnx, voices.bin, tokens.txt...). Desde sherpa-onnx 2.0
  /// no se usa espeak-ng: el español se pasa como fonemas (ver spanish_phonemizer.dart).
  final String modelDir;
  final AudioCache cache;

  static const _voices = <VoiceOption, int>{
    VoiceOption(name: 'Dora (natural)', locale: 'es-ES', quality: 'natural'): 28,
    VoiceOption(name: 'Alex (natural)', locale: 'es-ES', quality: 'natural'): 29,
  };

  /// ¿Está instalado el modelo?
  static bool isInstalled(String dir) =>
      File('$dir/model.int8.onnx').existsSync() &&
      File('$dir/voices.bin').existsSync() &&
      File('$dir/tokens.txt').existsSync();

  KokoroWorker? _worker;
  final AudioPlayer _player = AudioPlayer();
  int _speaker = 28;
  double _speed = 1.0;
  AudioPrefetcher? _prefetcher;

  // Cada speak/stop/pause invalida los anteriores: un audio que llega tarde
  // no debe sonar encima del siguiente (varias voces a la vez).
  int _gen = 0;

  // Si sintetizar tarda mucho más que la duración del audio, este dispositivo
  // no puede leer en tiempo real: se desactiva la voz natural.
  int _slow = 0;
  bool _tooSlow = false;

  @override
  String get id => 'kokoro';

  AudioPrefetcher get _pf => _prefetcher ??= AudioPrefetcher(
        engine: this,
        cache: cache,
        voice: 'sid$_speaker',
        speed: _speed,
      );

  @override
  Future<void> init() async {
    if (!isInstalled(modelDir)) {
      throw StateError('Modelo de voz natural no instalado.');
    }
    _worker ??= await KokoroWorker.start(modelDir);
  }

  @override
  Future<List<VoiceOption>> voices() async => _voices.keys.toList();

  @override
  Future<void> setVoice(VoiceOption voice) async {
    final sid = _voices.entries.where((e) => e.key.id == voice.id).map((e) => e.value);
    if (sid.isEmpty) return;
    _speaker = sid.first;
    _prefetcher = null;
  }

  @override
  Future<void> setLanguage(String locale) async {}

  @override
  Future<void> setRate(double rate) async {
    // 0.5 = velocidad normal en la escala del motor Apple.
    _speed = (rate / 0.5).clamp(0.5, 2.0).toDouble();
    _prefetcher = null;
  }

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  // El worker sintetiza de a uno: se encolan aquí para medir solo lo que tarda
  // cada síntesis, no la espera detrás de las adelantadas (si no, un archivo
  // largo terminaba marcando el equipo como lento y apagando la voz natural).
  Future<void> _queue = Future.value();

  @override
  Future<Uint8List> synthesize(String text) {
    final job = _queue.then((_) => _synthesizeNow(text));
    _queue = job.then((_) {}, onError: (_) {});
    return job;
  }

  Future<Uint8List> _synthesizeNow(String text) async {
    final w = _worker;
    if (w == null) throw StateError('Kokoro no iniciado.');
    final sw = Stopwatch()..start();
    final wav = await w.synthesize(text, speaker: _speaker, speed: _speed);
    final audioMs = (wav.length - 44) / 2 / 24000 * 1000;
    if (audioMs > 500) {
      _slow = sw.elapsedMilliseconds > audioMs * 2 ? _slow + 1 : 0;
      if (_slow >= 2) _tooSlow = true;
    }
    if (kDebugMode) {
      debugPrint('[lector] kokoro sintetizó ${text.length} car. en ${sw.elapsedMilliseconds} ms (${wav.length ~/ 1024} KB)');
    }
    return wav;
  }

  @override
  Future<void> speak(String text) async {
    if (_tooSlow) {
      throw StateError('Este dispositivo es demasiado lento para la voz natural.');
    }
    final my = ++_gen;
    final file = await _pf.fileFor(text);
    if (my != _gen) return; // se pidió detener/otro fragmento mientras se sintetizaba
    StreamSubscription<Duration>? levels;
    try {
      await _player.setFilePath(file.path);
      if (my != _gen) return;
      levels = await _followLevel(file, text);
      await _player.play(); // completa al terminar o al pausar/detener
    } on PlayerInterruptedException {
      // detenido a propósito: no es un fallo
    } finally {
      await levels?.cancel();
      onLevel?.call(0);
    }
  }

  static const _levelStep = Duration(milliseconds: 50);

  /// Informa por [onLevel] el volumen del audio en el punto que va sonando y,
  /// por [onProgress], la palabra que se estima que suena (esta voz no marca
  /// tiempos: se reparte el tramo con voz según el largo de cada palabra).
  Future<StreamSubscription<Duration>?> _followLevel(File file, String text) async {
    if (onLevel == null && onProgress == null) return null;
    final List<double> env;
    try {
      env = WavAudio.parse(await file.readAsBytes()).envelope(windowMs: _levelStep.inMilliseconds);
    } on FormatException {
      return null;
    }
    if (env.isEmpty) return null;
    final voiced = voicedRange(env);
    (int, int)? lastWord;
    return _player.createPositionStream(minPeriod: _levelStep, maxPeriod: _levelStep).listen((pos) {
      final i = (pos.inMilliseconds ~/ _levelStep.inMilliseconds).clamp(0, env.length - 1);
      onLevel?.call(env[i]);
      if (voiced == null || i < voiced.$1) return;
      final span = voiced.$2 - voiced.$1;
      final word = wordAtFraction(text, span <= 0 ? 1 : (i - voiced.$1) / span);
      if (word == null || word == lastWord) return;
      lastWord = word;
      onProgress?.call(text, word.$1, word.$2);
    });
  }

  @override
  Future<String?> renderToFile(String text, String path) async {
    if (_worker == null) return null;
    final target = path.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '.wav');
    await File(target).writeAsBytes(await synthesize(text), flush: true);
    return target;
  }

  @override
  void prefetch(List<String> upcoming) {
    if (_worker == null || _tooSlow) return;
    for (final t in upcoming.take(2)) {
      if (t.trim().isEmpty) continue;
      _pf.fileFor(t).then((_) {}, onError: (_) {});
    }
  }

  @override
  Future<void> pause() {
    _gen++;
    return _player.pause();
  }

  @override
  Future<void> stop() {
    _gen++;
    return _player.stop();
  }

  @override
  Future<void> dispose() async {
    await _player.dispose();
    _worker?.dispose();
  }
}
