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
  final limpio = _friendlyName(name.replaceAll(RegExp(r'\s*\(natural\)\s*$', caseSensitive: false), ''));
  return [limpio, ?region, calidad].join(' · ');
}

/// Las voces de Google en Android llegan como "es-us-x-esd-local": se
/// muestran como "Voz ESD" (el resto ya lo dicen la región y la calidad).
String _friendlyName(String name) {
  final m = RegExp(r'^[a-z]{2,3}-[a-z0-9]{2,3}-x-([a-z0-9]+)(?:-(?:local|network))?$', caseSensitive: false).firstMatch(name);
  if (m != null) return 'Voz ${m[1]!.toUpperCase()}';
  // Otras con forma de código ("es-ES-language"): el idioma ya se ve aparte.
  if (RegExp(r'^[a-z]{2,3}[-_][a-z]{2,3}([-_]\w+)*$', caseSensitive: false).hasMatch(name)) return 'Voz del sistema';
  return name;
}

/// Agrupa las voces para elegir sin perderse entre cientos: primero las
/// favoritas y las más usadas, luego unas pocas recomendadas (la natural y las
/// mejores del idioma preferido), el idioma preferido completo y después el
/// resto de idiomas, plegados. Las voces de efectos se descartan.
/// [id] identifica cada voz en [favorites] y en [uses] (veces elegida).
List<VoiceGroup<T>> groupVoices<T>(
  Iterable<T> voices, {
  required String preferredLanguage,
  required String Function(T) name,
  required String Function(T) locale,
  String? Function(T)? quality,
  String Function(T)? id,
  Set<String> favorites = const {},
  Map<String, int> uses = const {},
  int recommended = 3,
}) {
  final usable = voices.where((v) => !_isEffect(name(v))).toList();
  int usesOf(T v) => id == null ? 0 : uses[id(v)] ?? 0;
  bool isFavorite(T v) => id != null && favorites.contains(id(v));
  // De más a menos usada, sin perder el orden previo entre iguales.
  List<T> byUse(List<T> list) {
    final order = [for (var i = 0; i < list.length; i++) i]
      ..sort((a, b) {
        final c = usesOf(list[b]).compareTo(usesOf(list[a]));
        return c != 0 ? c : a.compareTo(b);
      });
    return [for (final i in order) list[i]];
  }

  List<T> ranked(Iterable<T> vs) {
    final list = vs.toList();
    final naturales = list.where((v) => _isNatural(quality?.call(v))).toList();
    final resto = rankVoices<T>(
      list.where((v) => !_isNatural(quality?.call(v))),
      name: name,
      locale: locale,
      quality: quality,
    );
    return [...byUse(naturales), ...byUse(resto)];
  }

  final favoritas = byUse(ranked(usable.where(isFavorite)));
  final masUsadas = byUse(ranked(usable.where((v) => !isFavorite(v) && usesOf(v) > 0))).take(recommended).toList();
  final destacadas = {...favoritas, ...masUsadas};

  final byLang = <String, List<T>>{};
  for (final v in usable.where((v) => !destacadas.contains(v))) {
    byLang.putIfAbsent(_lang(locale(v)), () => []).add(v);
  }
  final preferred = ranked(byLang.remove(preferredLanguage) ?? const []);
  final top = preferred.take(recommended).toList();
  final groups = <VoiceGroup<T>>[
    if (favoritas.isNotEmpty) VoiceGroup(title: 'Favoritas', voices: favoritas, expanded: true),
    if (masUsadas.isNotEmpty) VoiceGroup(title: 'Más usadas', voices: masUsadas, expanded: true),
    if (top.isNotEmpty) VoiceGroup(title: 'Recomendadas', voices: top, expanded: true),
    if (preferred.any((v) => !top.contains(v)))
      VoiceGroup(
        title: languageName(preferredLanguage),
        voices: preferred.where((v) => !top.contains(v)).toList(),
        expanded: true,
      ),
  ];
  final otros = byLang.entries.map((e) => (languageName(e.key), e.value)).toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));
  for (final (titulo, vs) in otros) {
    groups.add(VoiceGroup(title: titulo, voices: ranked(vs), expanded: false));
  }
  return groups;
}
