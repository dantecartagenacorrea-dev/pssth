import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';

import 'package:flutter_tts/flutter_tts.dart';

import '../tts_engine.dart';

/// Motor del sistema (AVSpeechSynthesizer en iOS, TextToSpeech en Android).
/// Estable, ligero, offline. Es el fallback universal.
class AppleTtsEngine extends TtsEngine {
  AppleTtsEngine([FlutterTts? tts]) : _tts = tts ?? FlutterTts();
  final FlutterTts _tts;

  @override
  String get id => 'apple';

  /// Sin avance de palabras durante este tiempo, la voz se da por muda.
  static const _stallLimit = Duration(seconds: 8);
  DateTime _lastActivity = DateTime.now();
  bool _heard = false; // si esta lectura ya avisó alguna palabra
  int _gen = 0; // cambia al pausar o detener: deja de vigilar

  @override
  Future<void> init() async {
    await _tts.awaitSpeakCompletion(true);
    try {
      await _tts.awaitSynthCompletion(true);
    } catch (_) {}
    _tts.setProgressHandler((String text, int start, int end, String word) {
      _lastActivity = DateTime.now();
      _heard = true;
      onProgress?.call(text, start, end);
    });
    _tts.setErrorHandler((message) => onError?.call('$message'));
    if (Platform.isIOS) {
      try {
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.allowAirPlay,
          ],
        );
      } catch (_) {}
    }
  }

  @override
  Future<List<VoiceOption>> voices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return [];
      final seen = <String>{};
      return raw
          .whereType<Map>()
          .map(
            (m) => VoiceOption(
              name: '${m['name'] ?? ''}',
              locale: '${m['locale'] ?? ''}',
              quality: m['quality'] == null ? null : '${m['quality']}',
            ),
          )
          .where((v) => v.name.isNotEmpty && seen.add(v.id))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> setVoice(VoiceOption voice) =>
      _tts.setVoice({'name': voice.name, 'locale': voice.locale});

  @override
  Future<void> setLanguage(String locale) => _tts.setLanguage(locale);

  @override
  Future<void> setRate(double rate) => _tts.setSpeechRate(rate);

  @override
  Future<void> setVolume(double volume) => _tts.setVolume(volume);

  /// Lee [text] y vigila que la voz siga sonando: si el servicio de voz del
  /// sistema muere a media frase (pasa en Android cuando se actualiza o el
  /// sistema lo cierra), la frase nunca termina y la lectura quedaba muda.
  /// Entonces se detiene y se vuelve a leer una vez; si sigue muda, se pasa a
  /// la siguiente en vez de quedarse en silencio.
  @override
  Future<void> speak(String text) async {
    final my = ++_gen;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (await _speakWatched(text, my)) return;
      if (kDebugMode) debugPrint('[lector] la voz del sistema quedó muda; reintento ${attempt + 1}');
      try {
        await _tts.stop();
      } catch (_) {}
      if (my != _gen) return;
    }
  }

  /// true si terminó (o se pausó/detuvo); false si la voz quedó muda.
  Future<bool> _speakWatched(String text, int my) async {
    _heard = false;
    final started = DateTime.now();
    _lastActivity = started;
    // Límite total para voces que no avisan palabra por palabra.
    final limit = Duration(seconds: 10 + (text.length * 0.4).round());
    final done = _tts.speak(text).then((_) => true, onError: (_) => true);
    while (true) {
      final finished = await Future.any([done, Future.delayed(const Duration(seconds: 1), () => false)]);
      if (finished || my != _gen) return true;
      final now = DateTime.now();
      if (_heard && now.difference(_lastActivity) > _stallLimit) return false;
      if (now.difference(started) > limit) return false;
    }
  }

  @override
  Future<String?> renderToFile(String text, String path) async {
    // iOS escribe CAF; Android, WAV. La extensión la decide la plataforma.
    final target = Platform.isIOS
        ? path.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '.caf')
        : path.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '.wav');
    final r = await _tts.synthesizeToFile(text, target, true);
    if (r != 1) return null;
    return File(target).existsSync() ? target : null;
  }

  @override
  Future<void> pause() {
    _gen++;
    return _tts.pause();
  }

  @override
  Future<void> stop() {
    _gen++;
    return _tts.stop();
  }

  @override
  Future<void> dispose() => _tts.stop();
}
