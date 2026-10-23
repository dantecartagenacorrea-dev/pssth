import 'dart:io' show File, Platform;

import 'package:flutter_tts/flutter_tts.dart';

import '../tts_engine.dart';

/// Motor del sistema (AVSpeechSynthesizer en iOS, TextToSpeech en Android).
/// Estable, ligero, offline. Es el fallback universal.
class AppleTtsEngine extends TtsEngine {
  AppleTtsEngine([FlutterTts? tts]) : _tts = tts ?? FlutterTts();
  final FlutterTts _tts;

  @override
  String get id => 'apple';

  @override
  Future<void> init() async {
    await _tts.awaitSpeakCompletion(true);
    try {
      await _tts.awaitSynthCompletion(true);
    } catch (_) {}
    _tts.setProgressHandler((String text, int start, int end, String word) {
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

  @override
  Future<void> speak(String text) => _tts.speak(text);

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
  Future<void> pause() => _tts.pause();

  @override
  Future<void> stop() => _tts.stop();

  @override
  Future<void> dispose() => _tts.stop();
}
