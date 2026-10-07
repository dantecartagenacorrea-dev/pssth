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

  // Abreviaturas masónicas: "Mas.·.", "HH.·.", "Ord:." (letra doble = plural).
  static final _gadu = RegExp(r'G\.\s*·\.\s*A\.\s*·\.\s*D\.\s*·\.\s*U\.\s*·\.');
  static final _masonic = RegExp(
    r'(?<![\p{L}\p{N}])(\p{L}{1,6})(?:\.\s*·\.|[.:]·[.:]?|:\.)',
    unicode: true,
  );
  static const _masonicWords = {
    'mas': 'Masonería', 'ord': 'Orden', 'or': 'Oriente',
    'h': 'Hermano', 'hh': 'Hermanos', 'log': 'Logia', 'llog': 'Logias',
    'tall': 'Taller', 'ttall': 'Talleres', 'obed': 'Obediencia',
    'oobed': 'Obediencias', 'gr': 'Grado', 'ggr': 'Grados',
    'dign': 'Dignidad', 'ddign': 'Dignidades', 'mm': 'Maestros Masones',
  };

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
    (RegExp('${_l}Ing\\.', unicode: true), 'Ingeniero'),
    (RegExp('${_l}Ltda\\.', unicode: true), 'Limitada'),
    (RegExp('${_l}S\\.R\\.L\\.', unicode: true), 'Sociedad de Responsabilidad Limitada'),
    (RegExp('${_l}S\\.A\\.', unicode: true), 'Sociedad Anónima'),
    (RegExp('${_l}Cía\\.', unicode: true), 'Compañía'),
    (RegExp('${_l}Av\\.', unicode: true), 'Avenida'),
    (RegExp('${_l}Tel\\.', unicode: true), 'Teléfono'),
    (RegExp('${_l}pág\\.', unicode: true), 'página'),
    (RegExp('${_l}págs\\.', unicode: true), 'páginas'),
    (RegExp('${_l}Ud\\.', unicode: true), 'usted'),
    (RegExp('${_l}Uds\\.', unicode: true), 'ustedes'),
    (RegExp('${_l}etc\\.', unicode: true), 'etcétera'),
    (RegExp('${_l}Parág\\.', unicode: true), 'Parágrafo'),
    (RegExp('§', unicode: true), 'parágrafo '),
  ];

  // "Artículo IV" / "Capítulo XII" -> "Artículo 4" / "Capítulo 12"
  static final _romanAfterWord = RegExp(
    r'\b(Art[íi]culos?|Cap[íi]tulos?|T[íi]tulos?|Secci[óo]n(?:es)?|Libros?|Tomos?|Par[áa]grafos?|Incisos?|Anexos?|Disposici[óo]n(?:es)?|Parte)\s+([IVXLCDM]{1,8})\b(?!\.)',
    caseSensitive: false,
  );
  // 12/05/2024, 12-05-2024, 2024-05-12
  static final _dateDmy = RegExp(r'\b(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})\b');
  static final _dateYmd = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');
  // 1º 2ª 3.º 4.ª
  static final _ordinal = RegExp(r'\b(\d{1,2})\.?([ºª°])');
  // 2019-2020, 5-7 (rangos numéricos)
  static final _range = RegExp(r'\b(\d+)\s*[-–]\s*(\d+)\b');

  static const _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
    'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  static const _ordMasc = ['primero', 'segundo', 'tercero', 'cuarto', 'quinto', 'sexto', 'séptimo', 'octavo', 'noveno', 'décimo'];
  static const _ordFem = ['primera', 'segunda', 'tercera', 'cuarta', 'quinta', 'sexta', 'séptima', 'octava', 'novena', 'décima'];

  static int? romanToInt(String s) {
    const v = {'I': 1, 'V': 5, 'X': 10, 'L': 50, 'C': 100, 'D': 500, 'M': 1000};
    var total = 0, prev = 0;
    for (final ch in s.toUpperCase().split('').reversed) {
      final n = v[ch];
      if (n == null) return null;
      if (n < prev) {
        total -= n;
      } else {
        total += n;
        prev = n;
      }
    }
    return total > 0 ? total : null;
  }

  static String _dateWords(int d, int m, int y) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return '$d/$m/$y';
    return '$d de ${_meses[m - 1]} de $y';
  }

  // "Bs 1.234,50" / "Bs. 100" -> "1.234,50 bolivianos"
  static final _bs = RegExp(
    r'(?<![\p{L}\p{N}])Bs\.?\s*(\d+(?:[.,]\d+)*)',
    unicode: true,
  );
  static final _percent = RegExp(r'(\d)\s*%');
  static final _multiSpace = RegExp(r'\s{2,}');
  // "abate ;" -> "abate;"   "¡ Qué noche !" -> "¡Qué noche!"  (PDFs antiguos/OCR)
  static final _spaceBeforePunct = RegExp(r'\s+([;:,.!?…])');
  static final _spaceAfterOpen = RegExp(r'([¡¿(«])\s+');

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

    t = t.replaceAll(_gadu, 'Gran Arquitecto del Universo');
    t = t.replaceAllMapped(_masonic, (m) {
      final w = m[1]!;
      return _masonicWords[w.toLowerCase()] ?? w;
    });

    if (legalMode) {
      t = t.replaceAllMapped(_bs, (m) => '${m[1]} bolivianos');
      for (final (re, spoken) in _legalRules) {
        t = t.replaceAll(re, spoken);
      }
    }
    t = t.replaceAllMapped(_percent, (m) => '${m[1]} por ciento');
    t = t.replaceAllMapped(_romanAfterWord, (m) {
      final n = romanToInt(m[2]!);
      return n == null ? m[0]! : '${m[1]} $n';
    });
    t = t.replaceAllMapped(_dateYmd, (m) => _dateWords(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!)));
    t = t.replaceAllMapped(_dateDmy, (m) => _dateWords(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
    t = t.replaceAllMapped(_ordinal, (m) {
      final n = int.parse(m[1]!);
      final fem = m[2] == 'ª';
      if (n >= 1 && n <= 10) return fem ? _ordFem[n - 1] : _ordMasc[n - 1];
      return '$n';
    });
    t = t.replaceAllMapped(_range, (m) => '${m[1]} a ${m[2]}');

    t = t.replaceAllMapped(_spaceBeforePunct, (m) => m[1]!);
    t = t.replaceAllMapped(_spaceAfterOpen, (m) => m[1]!);
    t = t.replaceAll(_spaces, ' ').replaceAll(_multiSpace, ' ').trim();
    return t;
  }
}
