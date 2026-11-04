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

  /// Volumen de la voz (0–1) mientras suena. Solo lo informan los motores que
  /// reproducen su propio audio; los demás avisan por palabra en [onProgress].
  void Function(double level)? onLevel;

  /// Error asíncrono del motor (p. ej. motor del sistema no disponible).
  void Function(String message)? onError;

  /// La lista de voces cambió sola (p. ej. se ocultaron voces que este equipo
  /// no alcanza a leer); [message] explica por qué, para mostrarlo.
  void Function(String message)? onVoicesChanged;

  Future<void> init();
  Future<List<VoiceOption>> voices();
  Future<void> setVoice(VoiceOption voice);
  Future<void> setLanguage(String locale);

  /// 0.5 = velocidad normal del motor Apple (ver [ttsRateFor]).
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> speak(String text);

  /// Pista de los fragmentos que vienen después (motores que sintetizan audio
  /// los preparan; el resto lo ignora).
  void prefetch(List<String> upcoming) {}

  /// Deja listo el audio de [text] con [voice] sin cambiar la voz que suena:
  /// al terminar, cambiar a esa voz y leer [text] empieza al instante. Los
  /// motores que hablan sin sintetizar antes (el del sistema) no esperan nada.
  Future<void> prepare(VoiceOption voice, String text) async {}

  /// ¿Puede empezar a sonar [text] ya, sin esperar a que se sintetice? Los
  /// motores que hablan directo (el del sistema) siempre pueden.
  Future<bool> canSpeakNow(String text) async => true;

  /// Como [speak], pero sin que otra voz cubra la espera: la misma voz lee todo, aunque
  /// tarde en empezar. Solo [FallbackTtsEngine] tiene otra voz con qué cubrirla.
  Future<void> speakSameVoice(String text) => speak(text);

  /// ¿Tiene sentido esperar a esta voz? No, si este equipo no alcanza a leer con ella.
  bool get worthWaiting => true;

  /// Sintetiza [text] en un archivo de audio en [path] (sin reproducirlo) y
  /// devuelve la ruta real escrita (la extensión puede cambiar según el motor:
  /// .wav en Android/Kokoro, .caf en iOS). `null` = el motor no sabe hacerlo.
  Future<String?> renderToFile(String text, String path) async => null;

  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();
}
