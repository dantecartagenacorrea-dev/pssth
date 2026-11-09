import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/perf_log.dart';
import '../../data/audio_cache.dart';
import '../../domain/wav_audio.dart';
import '../../domain/word_timing.dart';
import '../audio_prefetcher.dart';
import '../tts_engine.dart';
import 'kokoro_worker.dart';

/// Una voz instalable de un solo modelo: Piper ([onnx] y su archivo de
/// fonemas [tokens]) o Supertonic ([supertonic]: [onnx] y [tokens] son dos de
/// los archivos de su carpeta, para saber si está instalada; [sid] el hablante).
typedef PiperVoice = ({VoiceOption voice, String onnx, String tokens, int sid, bool supertonic});

/// Voces naturales locales (Luna con Supertonic, Claude con Piper) vía
/// sherpa-onnx. Offline, sin servidores. Sintetiza por fragmentos, guarda el
/// audio en caché y prepara los siguientes. (Se llama así por Kokoro, la
/// primera voz natural, ya retirada.)
class KokoroEngine extends TtsEngine implements SynthesizingEngine {
  KokoroEngine({required this.cache, this.piper = const [], AudioPlayer? player}) : _player = player ?? AudioPlayer();

  /// Voces naturales (cada una se ofrece si su modelo está instalado).
  final List<PiperVoice> piper;
  final AudioCache cache;

  final AudioPlayer _player;

  /// La voz elegida. Su modelo se carga al elegirla y queda uno solo en memoria.
  PiperVoice? _piperVoice;
  String? _piperOnnx;
  Future<KokoroWorker>? _piperWorker;

  /// ¿Hay con qué sintetizar la voz elegida?
  bool get _ready => _piperVoice != null;

  static bool _piperInstalled(PiperVoice p) => File(p.onnx).existsSync() && File(p.tokens).existsSync();
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
    voice: _cacheVoice(_piperVoice),
    speed: _speed,
  );

  static String _cacheVoice(PiperVoice? p) => 'piper-${p?.voice.name}';

  /// Sintetiza con [voice] y lo guarda en la caché con la misma clave que
  /// usará [speak] después de [setVoice]: mientras tanto sigue sonando la voz
  /// anterior, y al cambiar no hay que esperar la síntesis.
  @override
  Future<void> prepare(VoiceOption voice, String text) async {
    if (_tooSlow || text.trim().isEmpty) return;
    final p = piper.where((p) => p.voice.id == voice.id).firstOrNull;
    if (p == null) return;
    final speed = _speed;
    await AudioPrefetcher(
      engine: _VoiceSynth(id, (t) => _enqueue(() => _synthesizeNow(t, p, speed))),
      cache: cache,
      voice: _cacheVoice(p),
      speed: speed,
    ).fileFor(text);
  }

  @override
  Future<void> init() async {
    // Se vuelve a medir: una lentitud pasajera (otra tarea pesada al mismo
    // tiempo) no debe apagar la voz natural para siempre.
    _slow = 0;
    _tooSlow = false;
    if (!piper.any(_piperInstalled)) {
      throw StateError('Modelo de voz natural no instalado.');
    }
  }

  @override
  Future<List<VoiceOption>> voices() async => [
    for (final p in piper)
      if (_piperInstalled(p)) p.voice,
  ];

  @override
  Future<void> setVoice(VoiceOption voice) async {
    final p = piper.where((p) => p.voice.id == voice.id);
    if (p.isNotEmpty) {
      _piperVoice = p.first;
      _changed();
      unawaited(_piperFor(p.first).then((_) {}, onError: (_) {})); // que cargue ya
    }
  }

  /// El proceso de la voz Piper [p]: si es otra que la cargada, la reemplaza.
  Future<KokoroWorker> _piperFor(PiperVoice p) {
    if (_piperOnnx == p.onnx && _piperWorker != null) return _piperWorker!;
    final old = _piperWorker;
    _piperOnnx = p.onnx;
    final next = p.supertonic
        ? KokoroWorker.startSupertonic(File(p.onnx).parent.path)
        : KokoroWorker.startPiper(p.onnx, p.tokens);
    _piperWorker = next;
    next.then(
      (_) {},
      onError: (_) {
        if (identical(_piperWorker, next)) _piperWorker = null; // se reintenta la próxima vez
      },
    );
    // La voz anterior se cierra cuando termina lo que ya estaba sintetizando:
    // cerrarla a mitad dejaba esa frase (y toda la fila detrás) sin respuesta.
    final pending = _queue;
    old?.then((w) => pending.whenComplete(w.dispose), onError: (_) {});
    return next;
  }

  @override
  Future<void> setLanguage(String locale) async {}

  @override
  Future<void> setRate(double rate) async {
    // 0.5 = velocidad normal en la escala del motor Apple.
    _speed = (rate / 0.5).clamp(0.5, 3.0).toDouble();
    _changed();
  }

  /// Cambió la voz o la velocidad: lo que estaba en fila para la anterior se
  /// descarta, así la frase siguiente no espera a que se sinteticen dos
  /// frases que ya no van a sonar (era el corte al cambiar de voz).
  void _changed() {
    _settings++;
    _prefetcher = null;
  }

  int _settings = 0;

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  // El worker sintetiza de a uno: se encolan aquí para medir solo lo que tarda
  // cada síntesis, no la espera detrás de las adelantadas (si no, un archivo
  // largo terminaba marcando el equipo como lento y apagando la voz natural).
  Future<void> _queue = Future.value();

  @override
  Future<Uint8List> synthesize(String text) {
    // Con la voz y la velocidad de ahora: el audio se guarda con esa clave.
    final piperVoice = _piperVoice;
    final speed = _speed;
    final settings = _settings;
    return _enqueue(() {
      if (settings != _settings) throw const _Stale();
      if (piperVoice == null) throw StateError('No hay voz natural elegida.');
      return _synthesizeNow(text, piperVoice, speed);
    });
  }

  Future<Uint8List> _enqueue(Future<Uint8List> Function() work) {
    final job = _queue.then((_) => work());
    _queue = job.then((_) {}, onError: (_) {});
    return job;
  }

  Future<Uint8List> _synthesizeNow(String text, PiperVoice piperVoice, double speed) async {
    final w = await _piperFor(piperVoice);
    final sw = Stopwatch()..start();
    // Las voces Piper tienen un solo hablante (el 0); Supertonic, el elegido.
    final wav = await w.synthesize(text, speaker: piperVoice.sid, speed: speed);
    final rate = ByteData.sublistView(wav).getUint32(24, Endian.little);
    final audioMs = (wav.length - 44) / 2 / rate * 1000;
    if (audioMs > 500) {
      _slow = sw.elapsedMilliseconds > audioMs * 2 ? _slow + 1 : 0;
      if (_slow >= 2) _tooSlow = true;
    }
    perfLog('voz natural: ${audioMs.round()} ms de audio en ${sw.elapsedMilliseconds} ms (${text.length} car.)');
    return wav;
  }

  @override
  Future<void> speak(String text) async {
    if (_tooSlow) {
      throw StateError('Este dispositivo es demasiado lento para la voz natural.');
    }
    final my = ++_gen;
    File? file;
    // Si la voz o la velocidad cambian mientras espera en la fila, se pide
    // de nuevo con las nuevas (las veces que haga falta).
    while (file == null) {
      try {
        file = await _pf.fileFor(text);
      } on _Stale {
        if (my != _gen) return;
      }
    }
    if (my != _gen) return; // se pidió detener/otro fragmento mientras se sintetizaba
    StreamSubscription<Duration>? levels;
    try {
      // Al terminar un audio el reproductor sigue «tocando», y así play() vuelve al
      // instante: la frase siguiente se pisaba con esta o con la voz del sistema.
      if (_player.playing) await _player.stop();
      if (my != _gen) return;
      await _player.setFilePath(file.path);
      if (my != _gen) return;
      levels = await _followLevel(file, text);
      await _player.play(); // completa al terminar o al pausar/detener
    } on PlayerInterruptedException {
      // detenido a propósito: no es un fallo
    } finally {
      await levels?.cancel();
    }
  }

  static const _levelStep = Duration(milliseconds: 50);

  /// Informa por [onProgress] la palabra que se estima que suena (esta voz no marca
  /// tiempos: se reparte el tramo con voz según el largo de cada palabra).
  Future<StreamSubscription<Duration>?> _followLevel(File file, String text) async {
    if (onProgress == null) return null;
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
    if (!_ready) return null;
    final target = path.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '.wav');
    await File(target).writeAsBytes(await synthesize(text), flush: true);
    return target;
  }

  /// Sin audio listo, [speak] esperaría la síntesis (en un equipo lento, más
  /// de un minuto en silencio). Si no hay con qué sintetizar o es demasiado
  /// lento, sí: [speak] falla y se pasa a la voz del sistema con aviso.
  @override
  bool get worthWaiting => true;

  @override
  Future<bool> canSpeakNow(String text) async {
    if (!_ready || _tooSlow) return true;
    return _pf.isReady(text);
  }

  @override
  void prefetch(List<String> upcoming) {
    if (!_ready || _tooSlow) return;
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
    _piperWorker?.then((w) => w.dispose(), onError: (_) {});
  }
}

/// Sintetiza con una voz fija (la que se prepara antes de cambiar).
class _VoiceSynth implements SynthesizingEngine {
  _VoiceSynth(this.id, this._synth);

  @override
  final String id;
  final Future<Uint8List> Function(String text) _synth;

  @override
  Future<Uint8List> synthesize(String text) => _synth(text);
}

/// Síntesis descartada porque cambió la voz o la velocidad antes de empezar.
class _Stale implements Exception {
  const _Stale();
}
