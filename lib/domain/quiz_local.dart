import 'dart:math' as math;

import 'study.dart';
import 'summarizer.dart';

/// Preguntas sin IA, al instante, sacadas del propio texto: frases clave con
/// un término importante en blanco ("completa la frase"). Las opciones
/// incorrectas son otros términos clave del mismo texto, así que todas suenan
/// posibles. Primero las ideas principales; si hacen falta más, las frases
/// donde se explica cada concepto. Nada se inventa.
List<QuizQuestion> localQuiz(String text, {required int max, math.Random? rnd}) {
  if (max <= 0) return const [];
  final r = rnd ?? math.Random();
  final s = studySummaryExtractive(text, maxConcepts: 12, maxIdeas: 10);
  final terms = [for (final c in s.concepts) c.term.toLowerCase()];
  if (terms.length < 4) return const []; // no alcanza para tres opciones falsas
  final flat = text.replaceAll(RegExp(r'\s+'), ' ');
  final sentences = <String>{...s.ideas, for (final c in s.concepts) c.meaning};
  final out = <QuizQuestion>[];
  final usedTerms = <String>{};
  for (final raw in sentences) {
    if (out.length >= max) break;
    final sentence = withoutHeading(raw);
    if (sentence.length < _minSentence) continue;
    final q = _cloze(sentence, terms, usedTerms, flat, r);
    if (q != null) out.add(q);
  }
  return out;
}

/// La frase con su término clave (el más importante que no se preguntó aún)
/// en blanco, o null si no tiene ninguno.
QuizQuestion? _cloze(String sentence, List<String> terms, Set<String> used, String text, math.Random r) {
  if (sentence.trim().isEmpty || sentence.endsWith('…')) return null;
  for (final term in terms) {
    if (used.contains(term)) continue;
    final m = _word(term).firstMatch(sentence);
    if (m == null) continue;
    final others = [
      for (final t in terms)
        if (t != term) t,
    ]..shuffle(r);
    final options = [m[0]!, for (final t in others.take(3)) _formIn(text, t)];
    final q = QuizQuestion.fromMap({
      'question': 'Completa la frase del texto: «${sentence.replaceRange(m.start, m.end, '_____')}»',
      'options': options,
      'answer': 0,
      'explanation': 'El texto dice: «$sentence»',
    }, r);
    if (q == null) continue;
    used.add(term);
    return q;
  }
  return null;
}

/// Más corta que esto, la frase no da para una pregunta.
const _minSentence = 25;

/// La palabra entera, sin importar mayúsculas (y no dentro de otra palabra).
RegExp _word(String w) => RegExp('(?<!\\p{L})${RegExp.escape(w)}(?!\\p{L})', caseSensitive: false, unicode: true);

/// Cómo se escribe [word] en la prosa del texto (respeta los nombres
/// propios). Las apariciones en un título en mayúsculas no cuentan.
String _formIn(String text, String word) {
  for (final m in _word(word).allMatches(text)) {
    final w = m[0]!;
    if (w != w.toUpperCase()) return w;
  }
  return word;
}
