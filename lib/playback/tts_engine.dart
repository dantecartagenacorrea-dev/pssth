/// Voz ofrecida por un motor TTS.
class VoiceOption {
  const VoiceOption({required this.name, required this.locale, this.quality});
  final String name;
  final String locale;

  /// Calidad informada por el sistema (iOS: default/enhanced/premium).
  final String? quality;
  String get id => '$name|$locale';
  String get label {
    final q = quality == null || quality!.isEmpty || quality == 'default' ? '' : ' · ${quality!}';
    return '$name ($locale)$q';
  }
}

/// Contrato mínimo de un motor de voz. El reproductor solo conoce esto.
///
/// Reglas:
/// - [speak] completa cuando termina el fragmento (o tras [stop]/[pause]).
/// - Un fallo se informa lanzando excepción en [speak]/[init] o por [onError].
/// - [AppleTtsEngine] es el motor estable y el último fallback.
abstract class TtsEngine {
  /// Identificador estable ('apple', 'kokoro', ...).
  String get id;

  /// Rango (inicio, fin) de la palabra leída dentro de [text].
  void Function(String text, int start, int end)? onProgress;

  /// Error asíncrono del motor (p. ej. motor del sistema no disponible).
  void Function(String message)? onError;

  Future<void> init();
  Future<List<VoiceOption>> voices();
  Future<void> setVoice(VoiceOption voice);
  Future<void> setLanguage(String locale);

  /// 0.5 = velocidad normal del motor Apple (ver [ttsRateFor]).
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> speak(String text);
  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();
}
