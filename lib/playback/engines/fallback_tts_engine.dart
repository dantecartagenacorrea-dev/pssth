import 'package:flutter/foundation.dart';

import '../tts_engine.dart';

/// Combina un motor opcional ([primary], p. ej. voz natural) con el motor
/// estable ([fallback], el del sistema).
///
/// - Las voces de ambos aparecen en una sola lista; la voz elegida decide el motor.
/// - Si [primary] no está instalado o falla (al iniciar, al sintetizar...), se
///   pasa automáticamente a [fallback] sin cortar la escucha.
class FallbackTtsEngine extends TtsEngine {
  FallbackTtsEngine({
    required this.primary,
    required this.fallback,
    this.startWithPrimary = true,
  }) {
    _active = startWithPrimary ? primary : fallback;
  }

  final TtsEngine primary;
  final TtsEngine fallback;

  /// Motor usado hasta que se elija una voz concreta.
  final bool startWithPrimary;

  late TtsEngine _active;
  bool _primaryOk = true;
  bool _fallbackReady = false;
  double _rate = 0.5;
  double _volume = 1.0;
  String? _language;
  final Set<String> _primaryVoiceIds = {};

  /// Motivos de los fallos (para diagnóstico); el último al final.
  final List<String> errors = [];

  /// Avisa cuando se desactiva el motor primario.
  void Function(String reason)? onFallback;

  bool get usingFallback => identical(_active, fallback);
  bool get primaryAvailable => _primaryOk;

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
    try {
      await fallback.setVolume(_volume);
      await fallback.setRate(_rate);
      if (_language != null) await fallback.setLanguage(_language!);
    } catch (_) {}
  }

  Future<void> _disablePrimary(Object reason) async {
    if (!_primaryOk) return;
    _primaryOk = false;
    errors.add('${primary.id}: $reason');
    if (kDebugMode) debugPrint('[lector] motor ${primary.id} desactivado: $reason → ${fallback.id}');
    try {
      await primary.stop();
    } catch (_) {}
    _active = fallback;
    await _initFallback();
    onFallback?.call('$reason');
  }

  @override
  Future<void> init() async {
    _wire(primary);
    try {
      await primary.init();
      _primaryVoiceIds
        ..clear()
        ..addAll((await primary.voices()).map((v) => v.id));
    } catch (e) {
      _primaryOk = false;
      errors.add('${primary.id}: $e');
      if (kDebugMode) debugPrint('[lector] motor ${primary.id} no disponible: $e');
      _active = fallback;
    }
    await _initFallback();
    if (_primaryOk && !startWithPrimary) _active = fallback;
  }

  @override
  Future<List<VoiceOption>> voices() async {
    final out = <VoiceOption>[];
    try {
      out.addAll(await fallback.voices());
    } catch (_) {}
    if (_primaryOk) {
      try {
        out.insertAll(0, await primary.voices());
      } catch (_) {}
    }
    return out;
  }

  @override
  Future<void> setVoice(VoiceOption voice) async {
    if (_primaryOk && _primaryVoiceIds.contains(voice.id)) {
      _active = primary;
      try {
        await primary.setVoice(voice);
        await primary.setVolume(_volume);
        await primary.setRate(_rate);
        return;
      } catch (e) {
        await _disablePrimary(e);
        return;
      }
    }
    _active = fallback;
    await fallback.setVoice(voice);
  }

  @override
  Future<void> setLanguage(String locale) async {
    _language = locale;
    if (_fallbackReady) {
      try {
        await fallback.setLanguage(locale);
      } catch (_) {
        if (usingFallback) rethrow;
      }
    }
  }

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    if (_fallbackReady) {
      try {
        await fallback.setRate(rate);
      } catch (_) {}
    }
    if (_primaryOk) {
      try {
        await primary.setRate(rate);
      } catch (e) {
        await _disablePrimary(e);
      }
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    if (_fallbackReady) {
      try {
        await fallback.setVolume(volume);
      } catch (_) {}
    }
    if (_primaryOk) {
      try {
        await primary.setVolume(volume);
      } catch (e) {
        await _disablePrimary(e);
      }
    }
  }

  @override
  Future<void> speak(String text) async {
    try {
      await _active.speak(text);
    } catch (e) {
      if (usingFallback) rethrow;
      await _disablePrimary(e);
      await _active.speak(text);
    }
  }

  @override
  void prefetch(List<String> upcoming) {
    if (!usingFallback) primary.prefetch(upcoming);
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
