/// Normaliza texto SOLO para la reproducción por voz (TTS).
/// El texto original almacenado nunca se modifica.
class TextNormalizer {
  TextNormalizer({this.dictionary = const {}, this.legalMode = true});

  /// Diccionario de pronunciación del usuario: texto escrito -> pronunciación.
  final Map<String, String> dictionary;

  /// Reglas locales jurídico/contables (Art., Bs, %, etc.).
  final bool legalMode;

  static final _spaces = RegExp(r'[ \t ]+');
  static final _leaders = RegExp(r'\.{4,}|[_=\-–—]{3,}');
  static final _bullets = RegExp(r'[•▪◦●■□]');
  static const _l = r'(?<![\p{L}\p{N}])';

  static final List<(RegExp, String)> _legalRules = [
    (RegExp('${_l}Arts\\.', unicode: true), 'Artículos'),
    (RegExp('${_l}Art\\.', unicode: true), 'Artículo'),
    (RegExp('${_l}Incs\\.', unicode: true), 'Incisos'),
    (RegExp('${_l}Inc\\.', unicode: true), 'Inciso'),
    (RegExp('${_l}Núm\\.|${_l}Nro\\.|${_l}Nº|${_l}N°', unicode: true), 'número'),
    (RegExp('${_l}D\\.S\\.', unicode: true), 'Decreto Supremo'),
    (RegExp('${_l}R\\.A\\.', unicode: true), 'Resolución Administrativa'),
    (RegExp('${_l}Dr\\.', unicode: true), 'Doctor'),
    (RegExp('${_l}Dra\\.', unicode: true), 'Doctora'),
    (RegExp('${_l}Sr\\.', unicode: true), 'Señor'),
    (RegExp('${_l}Sra\\.', unicode: true), 'Señora'),
    (RegExp('${_l}Lic\\.', unicode: true), 'Licenciado'),
  ];

  // "Bs 1.234,50" / "Bs. 100" -> "1.234,50 bolivianos"
  static final _bs = RegExp(
    r'(?<![\p{L}\p{N}])Bs\.?\s*(\d+(?:[.,]\d+)*)',
    unicode: true,
  );
  static final _percent = RegExp(r'(\d)\s*%');
  static final _multiSpace = RegExp(r'\s{2,}');

  String normalize(String input) {
    var t = input.replaceAll('­', '');
    t = t.replaceAll(_bullets, '');
    t = t.replaceAll(_leaders, ' ');

    // El diccionario del usuario tiene prioridad sobre las reglas.
    for (final entry in dictionary.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) continue;
      final re = RegExp(
        '(?<![\\p{L}\\p{N}])${RegExp.escape(key)}(?![\\p{L}\\p{N}])',
        unicode: true,
      );
      t = t.replaceAll(re, entry.value);
    }

    if (legalMode) {
      t = t.replaceAllMapped(_bs, (m) => '${m[1]} bolivianos');
      for (final (re, spoken) in _legalRules) {
        t = t.replaceAll(re, spoken);
      }
    }
    t = t.replaceAllMapped(_percent, (m) => '${m[1]} por ciento');

    t = t.replaceAll(_spaces, ' ').replaceAll(_multiSpace, ' ').trim();
    return t;
  }
}
