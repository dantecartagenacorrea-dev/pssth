/// Puntuación de calidad de una voz del sistema, para elegir automáticamente
/// la mejor disponible sin que el usuario tenga que saber nombres técnicos.
///
/// iOS: flutter_tts informa `quality` (premium > enhanced > default).
/// Android (Google TTS): los nombres "…-x-…-local" son voces neuronales
/// locales; "…-network" requieren Internet; "xx-XX-language" es la genérica.
int voiceQualityScore({required String name, required String locale, String? quality}) {
  var score = 0;
  final q = (quality ?? '').toLowerCase();
  if (q.contains('premium')) score += 300;
  if (q.contains('enhanced')) score += 200;
  final n = name.toLowerCase();
  if (n.endsWith('-local')) score += 100;
  if (n.contains('-network')) score -= 100; // depende de Internet: evitar
  if (n.endsWith('-language')) score -= 50; // genérica, peor calidad
  if (n.contains('-x-')) score += 20; // variante neuronal de Google
  // Preferir el locale más cercano al español neutro/latino si hay varios.
  final l = locale.toLowerCase().replaceAll('_', '-');
  if (l == 'es-419' || l == 'es-us' || l == 'es-mx') score += 10;
  return score;
}

/// Ordena las voces de un idioma de mejor a peor calidad estimada.
List<T> rankVoices<T>(
  Iterable<T> voices, {
  required String Function(T) name,
  required String Function(T) locale,
  String? Function(T)? quality,
}) {
  final list = voices.toList();
  list.sort((a, b) {
    final sa = voiceQualityScore(name: name(a), locale: locale(a), quality: quality?.call(a));
    final sb = voiceQualityScore(name: name(b), locale: locale(b), quality: quality?.call(b));
    return sb.compareTo(sa);
  });
  return list;
}

/// ¿Funciona sin conexión esta voz del sistema? Android informa por voz si
/// sus datos no están descargados ("notInstalled" en [features]) y si
/// necesita Internet ([network] = "1"). Sin esos datos (iOS), sí.
bool isUsableSystemVoice({String? features, String? network}) =>
    !(features ?? '').contains('notInstalled') && network != '1';
