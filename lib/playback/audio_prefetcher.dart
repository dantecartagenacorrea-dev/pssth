import 'dart:typed_data';

import '../data/audio_cache.dart';

/// Motor capaz de producir audio (Kokoro, Pocket TTS...). Apple TTS no lo es.
abstract class SynthesizingEngine {
  String get id;
  Future<Uint8List> synthesize(String text);
}

/// Prepara los siguientes fragmentos mientras suena el actual.
/// Sin silencios, sin pregenerar el libro entero: solo [ahead] fragmentos.
class AudioPrefetcher {
  AudioPrefetcher({
    required this.engine,
    required this.cache,
    required this.voice,
    required this.speed,
    this.ahead = 2,
  });

  final SynthesizingEngine engine;
  final AudioCache cache;
  final String voice;
  final double speed;
  final int ahead;

  final Map<String, Future<Uint8List>> _pending = {};

  String _key(String text) => AudioCache.keyFor(
        text: text,
        engine: engine.id,
        voice: voice,
        speed: speed,
      );

  /// Audio del fragmento: caché → síntesis en curso → sintetizar y guardar.
  Future<Uint8List> audioFor(String text) {
    final key = _key(text);
    return _pending[key] ??= _load(key, text).whenComplete(() {
          _pending.remove(key); // sin devolver el Future: se esperaría a sí mismo
        });
  }

  Future<Uint8List> _load(String key, String text) async {
    final hit = await cache.get(key);
    if (hit != null) return hit;
    final data = await engine.synthesize(text);
    await cache.put(key, data);
    return data;
  }

  /// Lanza (sin esperar) los [ahead] fragmentos siguientes a [index].
  void prefetch(List<String> chunks, int index) {
    for (var i = index + 1; i <= index + ahead && i < chunks.length; i++) {
      if (chunks[i].trim().isEmpty) continue;
      audioFor(chunks[i]).then((_) {}, onError: (_) {});
    }
  }
}
