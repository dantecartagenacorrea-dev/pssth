import 'dart:math' as math;

import 'chapter_detector.dart';
import 'chunker.dart' show splitSentences;

/// Un concepto clave del resumen: el término y lo que significa.
typedef StudyConcept = ({String term, String meaning});

/// Resumen para estudiar: conceptos clave, ideas principales y resumen breve.
class StudySummary {
  const StudySummary({required this.concepts, required this.ideas, required this.brief});

  final List<StudyConcept> concepts;
  final List<String> ideas;
  final String brief;

  bool get isEmpty => concepts.isEmpty && ideas.isEmpty && brief.isEmpty;

  /// Lo que devuelve la IA nativa; descarta lo vacío o mal formado.
  factory StudySummary.fromMap(Object? raw) {
    final m = raw is Map ? raw : const {};
    final concepts = <StudyConcept>[
      for (final c in (m['concepts'] as List?) ?? const [])
        if (c is Map && '${c['term'] ?? ''}'.trim().isNotEmpty)
          (term: '${c['term']}'.trim(), meaning: '${c['meaning'] ?? ''}'.trim()),
    ];
    final ideas = [
      for (final i in (m['ideas'] as List?) ?? const [])
        if ('$i'.trim().isNotEmpty) '$i'.trim(),
    ];
    return StudySummary(concepts: concepts, ideas: ideas, brief: '${m['brief'] ?? ''}'.trim());
  }

  /// Texto plano para escuchar o descargar, en el orden en que se muestra.
  List<String> toLines() => [
        if (brief.isNotEmpty) brief,
        if (concepts.isNotEmpty) 'Conceptos clave.',
        for (final c in concepts) c.meaning.isEmpty ? '${c.term}.' : '${c.term}: ${c.meaning}',
        if (ideas.isNotEmpty) 'Ideas principales.',
        ...ideas,
      ];
}

/// Junta los resúmenes de cada parte: conceptos sin repetir (los del resumen
/// final primero), todas las ideas en orden y el resumen breve del final.
StudySummary mergeSummaries(List<StudySummary> parts, {StudySummary? overall, int maxConcepts = 12}) {
  final seen = <String>{};
  final concepts = <StudyConcept>[];
  for (final s in [?overall, ...parts]) {
    for (final c in s.concepts) {
      if (concepts.length >= maxConcepts) break;
      if (seen.add(c.term.toLowerCase())) concepts.add(c);
    }
  }
  final brief = overall?.brief ?? (parts.length == 1 ? parts.first.brief : parts.map((p) => p.brief).where((b) => b.isNotEmpty).join(' '));
  return StudySummary(concepts: concepts, ideas: [for (final p in parts) ...p.ideas], brief: brief);
}

/// Nivel de las preguntas y los puntos que da cada acierto.
enum QuizLevel {
  basico('Básico', 10),
  medio('Medio', 20),
  experto('Experto', 30);

  const QuizLevel(this.label, this.points);
  final String label;
  final int points;
}

/// Una pregunta de opción múltiple con su explicación.
class QuizQuestion {
  const QuizQuestion({required this.question, required this.options, required this.answer, required this.explanation});

  final String question;
  final List<String> options;
  final int answer;
  final String explanation;

  /// La pregunta tal como la manda la IA, o null si no sirve (sin texto, con
  /// menos de dos opciones, opciones repetidas o respuesta fuera de rango).
  /// Las opciones se mezclan para que la correcta no caiga siempre igual.
  static QuizQuestion? fromMap(Object? raw, math.Random rnd) {
    if (raw is! Map) return null;
    final question = '${raw['question'] ?? ''}'.trim();
    final options = [for (final o in (raw['options'] as List?) ?? const []) '$o'.trim()];
    final answer = raw['answer'];
    if (question.isEmpty || answer is! int || answer < 0 || answer >= options.length) return null;
    final correct = options[answer];
    final kept = options.take(4).toList();
    if (!kept.contains(correct)) kept[kept.length - 1] = correct;
    if (kept.length < 2 || kept.any((o) => o.isEmpty) || kept.map((o) => o.toLowerCase()).toSet().length != kept.length) {
      return null;
    }
    kept.shuffle(rnd);
    return QuizQuestion(
      question: question,
      options: kept,
      answer: kept.indexOf(correct),
      explanation: '${raw['explanation'] ?? ''}'.trim(),
    );
  }
}

/// Puntos de una respuesta: los del nivel si acierta, más 5 desde el tercer
/// acierto seguido. [streak] es la racha contando esta respuesta.
int quizPoints({required bool correct, required QuizLevel level, required int streak}) {
  if (!correct) return 0;
  return level.points + (streak >= 3 ? 5 : 0);
}

/// Qué parte del documento se estudia.
enum StudyScope {
  pagina('Esta página'),
  capitulo('Este capítulo'),
  documento('Todo el documento');

  const StudyScope(this.label);
  final String label;
}

/// Páginas a estudiar (desde, hasta exclusivo) según [scope]. Sin capítulos
/// detectados, "este capítulo" son esta página y las nueve siguientes.
(int, int) studyPages(List<String> pages, StudyScope scope, int current) {
  if (pages.isEmpty) return (0, 0);
  final page = current.clamp(0, pages.length - 1);
  switch (scope) {
    case StudyScope.pagina:
      return (page, page + 1);
    case StudyScope.documento:
      return (0, pages.length);
    case StudyScope.capitulo:
      final chapters = detectChapters(pages);
      if (chapters.isEmpty) return (page, math.min(pages.length, page + 10));
      var start = 0;
      var end = pages.length;
      for (final c in chapters) {
        if (c.pageIndex <= page) {
          start = c.pageIndex;
        } else {
          end = c.pageIndex;
          break;
        }
      }
      return (start, end);
  }
}

/// Divide el texto en partes de hasta [maxChars] sin cortar frases (una frase
/// más larga va sola, recortada), para que cada una quepa en la IA del equipo.
List<String> splitForStudy(String text, {int maxChars = 3500}) {
  final parts = <String>[];
  final buf = StringBuffer();
  for (final para in text.split(RegExp(r'\n\s*\n'))) {
    for (final raw in splitSentences(para.replaceAll(RegExp(r'\s+'), ' ').trim())) {
      final s = raw.length > maxChars ? raw.substring(0, maxChars) : raw;
      if (buf.isNotEmpty && buf.length + 1 + s.length > maxChars) {
        parts.add(buf.toString());
        buf.clear();
      }
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(s);
    }
  }
  if (buf.isNotEmpty) parts.add(buf.toString());
  return parts.where((p) => p.trim().length >= 80).toList();
}
