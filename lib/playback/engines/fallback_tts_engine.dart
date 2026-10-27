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
  final Map<String, String> _primaryVoiceLocale = {};
  VoiceOption? _primaryVoice;

  /// Motivos de los fallos (para diagnóstico); el último al final.
  final List<String> errors = [];

  /// Avisa cuando se desactiva el motor primario.
  void Function(String reason)? onFallback;

  bool get usingFallback => identical(_active, fallback);
  bool get primaryAvailable => _primaryOk;

  @override
  String get id => _active.id;

  TtsEngine get _other => identical(_active, primary) ? fallback : primary;

  bool _ready(TtsEngine e) => identical(e, primary) ? _primaryOk : _fallbackReady;

  /// Cambia de motor callando el que se deja: puede estar hablando o tener un
  /// audio a medio sintetizar que, si no, sonaría encima del nuevo.
  Future<void> _switchTo(TtsEngine next) async {
    if (identical(next, _active)) return;
    final prev = _active;
    _active = next;
    if (!_ready(prev)) return;
    try {
      await prev.stop();
    } catch (_) {}
  }

  Future<void> _stopOther() async {
    final other = _other;
    if (!_ready(other)) return;
    try {
      await other.stop();
    } catch (_) {}
  }

  void _wire(TtsEngine e) {
    e.onProgress = (t, s, en) => onProgress?.call(t, s, en);
    e.onLevel = (l) => onLevel?.call(l);
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
      await _indexPrimaryVoices();
    } catch (e) {
      _primaryOk = false;
      errors.add('${primary.id}: $e');
      if (kDebugMode) debugPrint('[lector] motor ${primary.id} no disponible: $e');
      _active = fallback;
    }
    await _initFallback();
    if (_primaryOk && !startWithPrimary) _active = fallback;
  }

  Future<void> _indexPrimaryVoices() async {
    final vs = await primary.voices();
    _primaryVoiceIds
      ..clear()
      ..addAll(vs.map((v) => v.id));
    _primaryVoiceLocale
      ..clear()
      ..addEntries(vs.map((v) => MapEntry(v.id, v.locale.toLowerCase())));
  }

  /// Vuelve a intentar el motor primario (p. ej. tras instalar el modelo).
  Future<bool> retryPrimary() async {
    if (_primaryOk) return true;
    try {
      _wire(primary);
      await primary.init();
      await _indexPrimaryVoices();
      await primary.setVolume(_volume);
      await primary.setRate(_rate);
      _primaryOk = true;
      _primaryVoice = null;
      return true;
    } catch (e) {
      errors.add('${primary.id}: $e');
      return false;
    }
  }

  bool _primarySpeaks(String locale) {
    final v = _primaryVoice;
    if (v == null) return false;
    final l = locale.toLowerCase();
    final pl = _primaryVoiceLocale[v.id] ?? '';
    return pl.startsWith(l) || l.startsWith(pl.split('-').first);
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
      _primaryVoice = voice;
      await _switchTo(primary);
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
    _primaryVoice = null;
    await _switchTo(fallback);
    await fallback.setVoice(voice);
  }

  /// Idioma del fragmento que viene. Si la voz natural elegida no habla ese
  /// idioma, ese fragmento sale por el motor del sistema; al volver al idioma
  /// de la voz natural, se retoma.
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
    if (_primaryOk && _primaryVoice != null) {
      await _switchTo(_primarySpeaks(locale) ? primary : fallback);
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
  Future<String?> renderToFile(String text, String path) async {
    if (!usingFallback) {
      try {
        final r = await primary.renderToFile(text, path);
        if (r != null) return r;
      } catch (e) {
        await _disablePrimary(e);
      }
    }
    await _initFallback();
    return fallback.renderToFile(text, path);
  }

  @override
  Future<void> pause() async {
    await _stopOther();
    await _active.pause();
  }

  @override
  Future<void> stop() async {
    await _stopOther();
    await _active.stop();
  }

  @override
  Future<void> dispose() async {
    await primary.dispose();
    if (_fallbackReady) await fallback.dispose();
  }
}
