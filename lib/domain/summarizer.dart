import 'dart:math' as math;

import 'chunker.dart' show splitSentences;
import 'study.dart' show StudySummary;

/// Resumen extractivo local: elige las frases más representativas del propio
/// texto (sin IA, sin red, sin inventar contenido) y las devuelve en su orden
/// original. Determinista y apto para documentos largos.
List<String> summarizeExtractive(
  String text, {
  double ratio = 0.2,
  int minSentences = 5,
  int maxSentences = 30,
  int minWords = 5,
}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) return const [];

  final sentences = _proseSentences(flat).where((s) {
    final w = _wordCount(s);
    return w >= minWords && w <= 70;
  }).toList();
  if (sentences.length <= minSentences) return sentences;

  final tokens = [for (final s in sentences) _contentWords(s)];

  final freq = <String, int>{};
  for (final ws in tokens) {
    for (final w in ws.toSet()) {
      freq[w] = (freq[w] ?? 0) + 1;
    }
  }
  // Una palabra en casi todas las frases no distingue; una única vez tampoco.
  final n = sentences.length;
  final weight = <String, double>{
    for (final e in freq.entries)
      if (e.value >= 2 && e.value <= n * 0.5) e.key: e.value.toDouble(),
  };

  final scores = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final uniq = tokens[i].toSet();
    if (uniq.isEmpty) continue;
    var sum = 0.0;
    for (final w in uniq) {
      sum += weight[w] ?? 0;
    }
    var score = sum / _pow06(uniq.length);
    if (i < n * 0.1) score *= 1.15; // el inicio suele presentar el tema
    scores[i] = score;
  }

  final target = (n * ratio).round().clamp(minSentences, maxSentences);
  final order = List<int>.generate(n, (i) => i)
    ..sort((a, b) {
      final c = scores[b].compareTo(scores[a]);
      return c != 0 ? c : a.compareTo(b);
    });

  final chosen = <int>[];
  for (final i in order) {
    if (chosen.length >= target) break;
    if (scores[i] <= 0) break;
    final set = tokens[i].toSet();
    final redundant = chosen.any((j) => _jaccard(set, tokens[j].toSet()) > 0.5);
    if (!redundant) chosen.add(i);
  }
  chosen.sort();
  return [for (final i in chosen) sentences[i]];
}

/// Resumen para estudiar sin IA (donde el equipo no tiene): las palabras que
/// más pesan en el texto como conceptos clave (con la frase donde se
/// explican), las frases más representativas como ideas principales y las
/// dos primeras de ellas como resumen breve. Todo sale del propio texto.
StudySummary studySummaryExtractive(String text, {int maxConcepts = 6, int maxIdeas = 8}) {
  // Ideas de al menos 8 palabras: las más cortas ("Esto sólo reduciría su poder.")
  // no se entienden fuera del texto.
  final ideas = summarizeExtractive(text, ratio: 0.15, minSentences: 3, maxSentences: maxIdeas, minWords: 8);
  if (ideas.isEmpty) return const StudySummary(concepts: [], ideas: [], brief: '');
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final sentences = _proseSentences(flat).toList();
  final n = sentences.length;
  // Peso de cada palabra: cuántas veces aparece × qué tan propia es (no está
  // en todas las frases). Solo palabras de 5 letras o más.
  final total = <String, int>{}, inSentences = <String, int>{};
  final shown = <String, String>{}; // cómo se escribe en la prosa (1.ª vez)
  final caps = <String, int>{}; // veces que aparece en mayúsculas (títulos)
  for (final s in sentences) {
    final seen = <String>{};
    for (final m in RegExp(r'\p{L}{5,}', unicode: true).allMatches(s)) {
      final word = m[0]!;
      final w = word.toLowerCase();
      if (_stop.contains(w)) continue;
      total[w] = (total[w] ?? 0) + 1;
      if (seen.add(w)) inSentences[w] = (inSentences[w] ?? 0) + 1;
      if (word == word.toUpperCase()) {
        caps[w] = (caps[w] ?? 0) + 1;
      } else {
        shown.putIfAbsent(w, () => word);
      }
    }
  }
  final ranked = [
    for (final e in total.entries)
      // Las que salen casi siempre en títulos no son conceptos del texto.
      if (e.value >= 2 && (caps[e.key] ?? 0) * 2 <= e.value)
        (word: e.key, score: e.value * math.log(1 + n / inSentences[e.key]!)),
  ]..sort((a, b) => b.score.compareTo(a.score));
  // Las palabras que más pesan: la frase de cada concepto es la que más
  // reúne (no la primera que lo nombra, que suele ser la portada o los
  // agradecimientos).
  final keys = {for (final r in ranked.take(_keyWords)) r.word};
  final used = <String>{}; // cada concepto con su propia frase
  final concepts = <({String term, String meaning})>[];
  for (final r in ranked) {
    if (concepts.length >= maxConcepts) break;
    // Sin repetir familias de palabras (poder / poderoso).
    if (concepts.any((c) => c.term.toLowerCase().startsWith(r.word.substring(0, 4)))) continue;
    final where = _explaining(r.word, sentences, keys, used);
    used.add(where);
    final term = shown[r.word] ?? r.word;
    concepts.add((
      term: term[0].toUpperCase() + term.substring(1),
      meaning: where.length > 180 ? '${where.substring(0, 177).trimRight()}…' : where,
    ));
  }
  return StudySummary(concepts: concepts, ideas: ideas, brief: ideas.take(2).join(' '));
}

/// Cuántas de las palabras que más pesan cuentan para elegir la frase de un
/// concepto.
const _keyWords = 30;

/// La frase que mejor explica [word]: entre las que la nombran (de 8 a 45
/// palabras), la que reúne más de las otras palabras que más pesan [keys] y
/// no explica ya otro concepto ([used]).
String _explaining(String word, List<String> sentences, Set<String> keys, Set<String> used) {
  var best = '';
  var bestScore = -1;
  for (final s in sentences) {
    final lower = s.toLowerCase();
    if (used.contains(s) || !lower.contains(word)) continue;
    final n = _wordCount(s);
    if (n < 8 || n > 45) continue;
    final words = RegExp(r'\p{L}{5,}', unicode: true).allMatches(lower).map((m) => m[0]!).toSet();
    final score = words.where(keys.contains).length;
    if (score > bestScore) {
      best = s;
      bestScore = score;
    }
  }
  return best.isNotEmpty ? best : sentences.firstWhere((s) => s.toLowerCase().contains(word), orElse: () => '');
}

/// Más mayúsculas que esto (de las letras de una frase) es un título, una
/// portada o un índice, no prosa.
const _maxCaps = 0.4;

/// Las frases de prosa del texto, sin el título en mayúsculas que el PDF
/// pega al comienzo de algunas.
Iterable<String> _proseSentences(String flat) sync* {
  for (final raw in splitSentences(flat)) {
    final s = withoutHeading(raw);
    if (_wordCount(s) < 5) continue;
    // Empieza en minúscula: es un pedazo de frase mal cortada (salto de página).
    if (RegExp(r'^\p{Ll}', unicode: true).hasMatch(s)) continue;
    final letters = RegExp(r'\p{L}', unicode: true).allMatches(s).length;
    final upper = RegExp(r'\p{Lu}', unicode: true).allMatches(s).length;
    if (letters == 0 || upper / letters > _maxCaps) continue;
    // "Ése era uno de los pilares…", "Era la posición…": fuera del texto no se
    // sabe de quién hablan.
    if (_leansOnPrevious.hasMatch(s)) continue;
    yield s;
  }
}

/// Frase que empieza apoyándose en la anterior: pronombre o verbo sin sujeto.
final _leansOnPrevious = RegExp(
  r'^(?:[ÉE]se|[ÉE]sa|[ÉE]sos|[ÉE]sas|Éste|Ésta|Éstos|Éstas|Esto|Eso|Aquello|Ello|Él|Ella|Ellos|Ellas|'
  r'Era|Eran|Fue|Fueron|Estaba|Estaban|Había|Habían|Se|Lo|Le|Les|Tampoco)\s+(?:era|eran|fue|fueron|\p{Ll})',
  unicode: true,
);

/// Rótulos de sección de libros de estudio pegados a la frase que sigue
/// ("Interpretación César Borgia era…").
final _sectionLabel = RegExp(
  r'^(?:Interpretación|Inversión|Criterio|Comentario|Ejemplo|Nota)\s+(?=\p{Lu})',
  unicode: true,
);

/// Un título en mayúsculas (dos palabras o más) pegado al comienzo de la
/// frase, porque el PDF no los separa: "LEY N° 43 página 449 TRABAJE SOBRE
/// EL CORAZÓN La coerción provoca…".
final _heading = RegExp(r'^.*\p{Lu}{2,}[^\p{Ll}]*\s\p{Lu}{2,}[^\p{Ll}]*\s(?=\p{Lu}\p{Ll})', unicode: true);

/// [sentence] sin el título en mayúsculas que la precede.
String withoutHeading(String sentence) => sentence.replaceFirst(_heading, '').trim().replaceFirst(_sectionLabel, '');

int _wordCount(String s) => RegExp(r'\p{L}+', unicode: true).allMatches(s).length;

double _pow06(int n) => math.pow(n, 0.6).toDouble();

double _jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final inter = a.intersection(b).length;
  return inter / (a.length + b.length - inter);
}

List<String> _contentWords(String s) => RegExp(
  r'\p{L}{3,}',
  unicode: true,
).allMatches(s.toLowerCase()).map((m) => m[0]!).where((w) => !_stop.contains(w)).toList();

const _stop = {
  // español
  'que', 'los', 'las', 'del', 'por', 'con', 'para', 'una', 'uno', 'unos', 'unas',
  'como', 'más', 'pero', 'sus', 'este', 'esta', 'esto', 'estos', 'estas', 'son',
  'entre', 'sin', 'sobre', 'también', 'fue', 'han', 'ser', 'está', 'están',
  'cuando', 'donde', 'muy', 'ese', 'esa', 'eso', 'hay', 'todo', 'todos', 'todas',
  'les', 'nos', 'ante', 'bajo', 'hasta', 'desde', 'cada', 'otro', 'otra', 'otros',
  'puede', 'pueden', 'tiene', 'tienen', 'así', 'aunque', 'porque', 'según',
  'usted', 'ustedes', 'había', 'habían', 'nunca', 'siempre', 'hacer', 'hecho', 'mismo', 'misma',
  'mismos', 'mismas', 'entonces', 'después', 'antes', 'ahora', 'mucho', 'mucha', 'muchos', 'muchas',
  'quien', 'quienes', 'alguien', 'nadie', 'menos', 'mejor', 'parte', 'forma', 'manera', 'tanto',
  'tanta', 'sería', 'podría', 'debe', 'deben', 'debería', 'página', 'capítulo', 'otras', 'cosas',
  'tenía', 'tenían', 'estaba', 'estaban', 'hacia', 'mientras', 'menudo', 'vez', 'veces', 'durante', 'demás',
  'contra', 'ella', 'ellos', 'ellas', 'embargo', 'aquel', 'aquella', 'aquellos', 'aquellas', 'cual', 'cuales',
  'cuyo', 'cuya', 'algo', 'nada', 'sino', 'pues', 'luego', 'además', 'tal', 'tales', 'sólo', 'solo', 'aún',
  'todavía', 'cualquier', 'cualquiera', 'ningún', 'ninguna', 'algún', 'alguna', 'algunos', 'algunas',
  'demasiado', 'demasiada', 'demasiados', 'demasiadas',
  // inglés
  'the', 'and', 'that', 'for', 'with', 'was', 'are', 'this', 'from', 'have',
  'not', 'but', 'they', 'which', 'you', 'were', 'has', 'their', 'been', 'will',
  'would', 'there', 'what', 'when', 'where', 'who', 'its', 'also', 'than',
  // portugués / francés frecuentes
  'não', 'uma', 'são', 'com', 'dos', 'das', 'des', 'est', 'pour', 'dans',
  'qui', 'par', 'sur', 'pas', 'avec',
};
