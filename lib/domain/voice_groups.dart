import 'voice_ranking.dart';

/// Grupo de voces para el selector: "Recomendadas" y uno por idioma.
class VoiceGroup<T> {
  const VoiceGroup({required this.title, required this.voices, required this.expanded});
  final String title;
  final List<T> voices;

  /// Si se muestra desplegado de entrada (solo recomendadas e idioma preferido).
  final bool expanded;
}

/// Voces de efectos de Apple (campanas, burbujas, robots…): no sirven para leer.
const _effectVoices = {
  'albert', 'bad news', 'bahh', 'bells', 'boing', 'bubbles', 'cellos', 'good news',
  'jester', 'organ', 'superstar', 'trinoids', 'whisper', 'wobble', 'zarvox',
  'malas noticias', 'campanas', 'burbujas', 'violonchelos', 'buenas noticias',
  'bufón', 'órgano', 'superestrella', 'trinoides', 'susurro', 'bamboleo',
};

const _languageNames = {
  'es': 'Español', 'en': 'Inglés', 'pt': 'Portugués', 'fr': 'Francés', 'it': 'Italiano',
  'de': 'Alemán', 'ca': 'Catalán', 'gl': 'Gallego', 'eu': 'Euskera', 'nl': 'Neerlandés',
  'ru': 'Ruso', 'zh': 'Chino', 'ja': 'Japonés', 'ko': 'Coreano', 'ar': 'Árabe',
};

const _regionNames = {
  'ES': 'España', 'MX': 'México', 'US': 'EE. UU.', 'AR': 'Argentina', 'CO': 'Colombia',
  'CL': 'Chile', 'PE': 'Perú', '419': 'Latinoamérica', 'GB': 'Reino Unido', 'AU': 'Australia',
  'IE': 'Irlanda', 'IN': 'India', 'ZA': 'Sudáfrica', 'CA': 'Canadá', 'FR': 'Francia',
  'BR': 'Brasil', 'PT': 'Portugal',
};

String _lang(String locale) => locale.toLowerCase().replaceAll('_', '-').split('-').first;

bool _isEffect(String name) => _effectVoices.contains(name.toLowerCase().trim());

bool _isNatural(String? quality) => (quality ?? '').toLowerCase() == 'natural';

/// Nombre del idioma para el usuario (o el código si no está en la lista).
String languageName(String code) => _languageNames[code] ?? code.toUpperCase();

/// "Paulina · México · Premium": sin códigos técnicos de idioma ni de calidad.
String voiceDisplayLabel({required String name, required String locale, String? quality}) {
  final parts = locale.replaceAll('_', '-').split('-');
  final region = parts.length > 1 ? (_regionNames[parts[1].toUpperCase()] ?? parts[1].toUpperCase()) : null;
  final q = (quality ?? '').toLowerCase();
  final n = name.toLowerCase();
  final calidad = switch (q) {
    'natural' => 'Natural',
    'premium' => 'Premium',
    'enhanced' => 'Mejorada',
    _ when n.contains('-network') => 'Requiere Internet',
    _ when n.endsWith('-local') => 'Alta',
    _ => 'Básica',
  };
  final limpio = name.replaceAll(RegExp(r'\s*\(natural\)\s*$', caseSensitive: false), '');
  return [limpio, ?region, calidad].join(' · ');
}

/// Agrupa las voces para elegir sin perderse entre cientos: primero unas pocas
/// recomendadas (la natural y las mejores del idioma preferido), luego el
/// idioma preferido completo y después el resto de idiomas, plegados.
/// Las voces de efectos se descartan.
List<VoiceGroup<T>> groupVoices<T>(
  Iterable<T> voices, {
  required String preferredLanguage,
  required String Function(T) name,
  required String Function(T) locale,
  String? Function(T)? quality,
  int recommended = 3,
}) {
  final usable = voices.where((v) => !_isEffect(name(v))).toList();
  List<T> ranked(Iterable<T> vs) {
    final list = vs.toList();
    final naturales = list.where((v) => _isNatural(quality?.call(v))).toList();
    final resto = rankVoices<T>(
      list.where((v) => !_isNatural(quality?.call(v))),
      name: name,
      locale: locale,
      quality: quality,
    );
    return [...naturales, ...resto];
  }

  final byLang = <String, List<T>>{};
  for (final v in usable) {
    byLang.putIfAbsent(_lang(locale(v)), () => []).add(v);
  }
  final preferred = ranked(byLang.remove(preferredLanguage) ?? const []);
  final top = preferred.take(recommended).toList();
  final groups = <VoiceGroup<T>>[
    if (top.isNotEmpty) VoiceGroup(title: 'Recomendadas', voices: top, expanded: true),
    if (preferred.length > top.length)
      VoiceGroup(title: languageName(preferredLanguage), voices: preferred.skip(top.length).toList(), expanded: true),
  ];
  final otros = byLang.entries.map((e) => (languageName(e.key), e.value)).toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));
  for (final (titulo, vs) in otros) {
    groups.add(VoiceGroup(title: titulo, voices: ranked(vs), expanded: false));
  }
  return groups;
}
