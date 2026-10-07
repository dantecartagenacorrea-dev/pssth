import 'package:flutter/foundation.dart';

import '../tts_engine.dart';

/// Cadena de seguridad: usa [primary] y, ante cualquier fallo, pasa
/// automáticamente a [fallback] (motor estable) sin cortar la escucha.
class FallbackTtsEngine extends TtsEngine {
  FallbackTtsEngine({required this.primary, required this.fallback}) {
    _active = primary;
  }

  final TtsEngine primary;
  final TtsEngine fallback;
  late TtsEngine _active;
  bool _fallbackReady = false;
  double _rate = 0.5;
  double _volume = 1.0;
  String? _language;

  /// Motivos de los fallos (para diagnóstico); el último al final.
  final List<String> errors = [];

  /// Avisa cuando se activa el fallback (la interfaz puede informarlo).
  void Function(String reason)? onFallback;

  bool get usingFallback => identical(_active, fallback);

  @override
  String get id => _active.id;

  void _wire(TtsEngine e) {
    e.onProgress = (t, s, en) => onProgress?.call(t, s, en);
    e.onError = (m) => onError?.call(m);
  }

  Future<void> _initFallback() async {
    if (_fallbackReady) return;
    _wire(fallback);
    await fallback.init();
    _fallbackReady = true;
  }

  Future<void> _switchToFallback(Object reason) async {
    if (usingFallback) throw reason;
    errors.add('${primary.id}: $reason');
    if (kDebugMode) debugPrint('[lector] motor ${primary.id} falló: $reason → ${fallback.id}');
    try {
      await primary.stop();
    } catch (_) {}
    _active = fallback;
    await _initFallback();
    try {
      await fallback.setVolume(_volume);
      await fallback.setRate(_rate);
      if (_language != null) await fallback.setLanguage(_language!);
    } catch (_) {}
    onFallback?.call('$reason');
  }

  @override
  Future<void> init() async {
    _wire(primary);
    try {
      await primary.init();
    } catch (e) {
      await _switchToFallback(e);
    }
    if (!usingFallback) await _initFallback();
  }

  @override
  Future<List<VoiceOption>> voices() async {
    try {
      final v = await _active.voices();
      if (v.isNotEmpty || usingFallback) return v;
    } catch (e) {
      await _switchToFallback(e);
    }
    return _active.voices();
  }

  @override
  Future<void> setVoice(VoiceOption voice) async {
    try {
      await _active.setVoice(voice);
    } catch (e) {
      if (usingFallback) rethrow;
      await _switchToFallback(e);
    }
  }

  @override
  Future<void> setLanguage(String locale) async {
    _language = locale;
    try {
      await _active.setLanguage(locale);
    } catch (e) {
      if (usingFallback) rethrow;
      await _switchToFallback(e);
    }
  }

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    try {
      await _active.setRate(rate);
    } catch (e) {
      if (usingFallback) rethrow;
      await _switchToFallback(e);
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    try {
      await _active.setVolume(volume);
    } catch (e) {
      if (usingFallback) rethrow;
      await _switchToFallback(e);
    }
  }

  @override
  Future<void> speak(String text) async {
    try {
      await _active.speak(text);
    } catch (e) {
      if (usingFallback) rethrow;
      await _switchToFallback(e);
      await _active.speak(text);
    }
  }

  @override
  Future<void> pause() => _active.pause();

  @override
  Future<void> stop() => _active.stop();

  @override
  Future<void> dispose() async {
    await primary.dispose();
    if (_fallbackReady) await fallback.dispose();
  }
}
