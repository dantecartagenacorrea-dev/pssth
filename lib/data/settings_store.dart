import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PlaybackPrefs {
  const PlaybackPrefs({
    this.speed = 1.0,
    this.voiceName,
    this.voiceLocale,
    this.lastDocumentId,
  });

  final double speed;
  final String? voiceName;
  final String? voiceLocale;
  final String? lastDocumentId;
}

class SettingsStore {
  static const _speedKey = 'speed';
  static const _voiceNameKey = 'voiceName';
  static const _voiceLocaleKey = 'voiceLocale';
  static const _lastDocKey = 'lastDocumentId';
  static const _favoriteVoicesKey = 'favoriteVoices';
  static const _voiceUsesKey = 'voiceUses';

  /// Voces marcadas con estrella (por su id).
  Future<Set<String>> loadFavoriteVoices() async =>
      ((await SharedPreferences.getInstance()).getStringList(_favoriteVoicesKey) ?? const []).toSet();

  Future<void> saveFavoriteVoices(Set<String> ids) async =>
      (await SharedPreferences.getInstance()).setStringList(_favoriteVoicesKey, ids.toList());

  /// Cuántas veces se eligió cada voz (por su id).
  Future<Map<String, int>> loadVoiceUses() async {
    final raw = (await SharedPreferences.getInstance()).getString(_voiceUsesKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toInt()));
    } on FormatException {
      return {};
    }
  }

  Future<void> countVoiceUse(String id) async {
    final uses = await loadVoiceUses();
    uses[id] = (uses[id] ?? 0) + 1;
    await (await SharedPreferences.getInstance()).setString(_voiceUsesKey, jsonEncode(uses));
  }

  Future<PlaybackPrefs> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PlaybackPrefs(
      speed: prefs.getDouble(_speedKey) ?? 1.0,
      voiceName: prefs.getString(_voiceNameKey),
      voiceLocale: prefs.getString(_voiceLocaleKey),
      lastDocumentId: prefs.getString(_lastDocKey),
    );
  }

  Future<void> saveSpeed(double speed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_speedKey, speed);
  }

  Future<void> saveVoice({String? name, String? locale}) async {
    final prefs = await SharedPreferences.getInstance();
    if (name == null) {
      await prefs.remove(_voiceNameKey);
    } else {
      await prefs.setString(_voiceNameKey, name);
    }
    if (locale == null) {
      await prefs.remove(_voiceLocaleKey);
    } else {
      await prefs.setString(_voiceLocaleKey, locale);
    }
  }

  Future<void> saveLastDocumentId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_lastDocKey);
    } else {
      await prefs.setString(_lastDocKey, id);
    }
  }
}
