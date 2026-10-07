import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/audio_cache.dart';
import '../audio_prefetcher.dart';
import '../tts_engine.dart';
import 'kokoro_worker.dart';

/// Voz natural local (Kokoro-82M int8 vía sherpa-onnx). Offline, sin servidores.
/// Sintetiza por fragmentos, guarda el audio en caché y prepara los siguientes.
class KokoroEngine extends TtsEngine implements SynthesizingEngine {
  KokoroEngine({required this.modelDir, required this.cache});

  /// Carpeta del modelo (model.int8.onnx, voices.bin, tokens.txt, espeak-ng-data...).
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
      File('$dir/tokens.txt').existsSync() &&
      Directory('$dir/espeak-ng-data').existsSync();

  KokoroWorker? _worker;
  final AudioPlayer _player = AudioPlayer();
  int _speaker = 28;
  double _speed = 1.0;
  AudioPrefetcher? _prefetcher;

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

  @override
  Future<Uint8List> synthesize(String text) async {
    final w = _worker;
    if (w == null) throw StateError('Kokoro no iniciado.');
    final sw = Stopwatch()..start();
    final wav = await w.synthesize(text, speaker: _speaker, speed: _speed);
    if (kDebugMode) {
      debugPrint('[lector] kokoro sintetizó ${text.length} car. en ${sw.elapsedMilliseconds} ms (${wav.length ~/ 1024} KB)');
    }
    return wav;
  }

  @override
  Future<void> speak(String text) async {
    final file = await _pf.fileFor(text);
    await _player.setFilePath(file.path);
    await _player.play(); // completa al terminar o al pausar/detener
  }

  @override
  void prefetch(List<String> upcoming) {
    if (_worker == null) return;
    for (final t in upcoming.take(2)) {
      if (t.trim().isEmpty) continue;
      _pf.fileFor(t).then((_) {}, onError: (_) {});
    }
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() async {
    await _player.dispose();
    _worker?.dispose();
  }
}
