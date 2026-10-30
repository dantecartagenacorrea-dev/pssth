import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/study.dart';

void main() {
  group('QuizQuestion.fromMap', () {
    test('mezcla las opciones y sigue marcando la correcta', () {
      final q = QuizQuestion.fromMap({
        'question': '¿Capital de Bolivia?',
        'options': ['La Paz', 'Sucre', 'Lima', 'Quito'],
        'answer': 1,
        'explanation': 'Sucre es la capital constitucional.',
      }, math.Random(3))!;
      expect(q.options, hasLength(4));
      expect(q.options[q.answer], 'Sucre');
    });

    test('descarta preguntas mal formadas', () {
      final r = math.Random(1);
      expect(QuizQuestion.fromMap({'question': '', 'options': ['a', 'b'], 'answer': 0}, r), isNull);
      expect(QuizQuestion.fromMap({'question': 'x', 'options': ['a', 'b'], 'answer': 5}, r), isNull);
      expect(QuizQuestion.fromMap({'question': 'x', 'options': ['a'], 'answer': 0}, r), isNull);
      expect(QuizQuestion.fromMap({'question': 'x', 'options': ['a', 'A'], 'answer': 0}, r), isNull);
      expect(QuizQuestion.fromMap('nada', r), isNull);
    });

    test('con más de cuatro opciones conserva la correcta', () {
      final q = QuizQuestion.fromMap({
        'question': 'x',
        'options': ['a', 'b', 'c', 'd', 'e'],
        'answer': 4,
      }, math.Random(2))!;
      expect(q.options, hasLength(4));
      expect(q.options[q.answer], 'e');
    });
  });

  test('puntos por nivel y bono desde el tercer acierto seguido', () {
    expect(quizPoints(correct: false, level: QuizLevel.experto, streak: 0), 0);
    expect(quizPoints(correct: true, level: QuizLevel.basico, streak: 1), 10);
    expect(quizPoints(correct: true, level: QuizLevel.medio, streak: 2), 20);
    expect(quizPoints(correct: true, level: QuizLevel.experto, streak: 3), 35);
  });

  group('studyPages', () {
    final pages = List.generate(30, (i) => i == 0 ? 'Capítulo 1\nTexto' : i == 12 ? 'Capítulo 2\nTexto' : 'texto $i');

    test('página actual y documento entero', () {
      expect(studyPages(pages, StudyScope.pagina, 5), (5, 6));
      expect(studyPages(pages, StudyScope.documento, 5), (0, 30));
    });

    test('sin capítulos toma esta página y las nueve siguientes', () {
      final plain = List.generate(15, (i) => 'texto $i');
      expect(studyPages(plain, StudyScope.capitulo, 8), (8, 15));
      expect(studyPages(plain, StudyScope.capitulo, 2), (2, 12));
    });

    test('documento vacío', () {
      expect(studyPages(const [], StudyScope.capitulo, 0), (0, 0));
    });
  });

  test('splitForStudy no corta frases ni pasa del largo', () {
    final text = List.generate(200, (i) => 'Esta es la frase número $i del texto de prueba.').join(' ');
    final parts = splitForStudy(text, maxChars: 500);
    expect(parts.length, greaterThan(1));
    for (final p in parts) {
      expect(p.length, lessThanOrEqualTo(500));
      expect(p.trimRight(), endsWith('.'));
    }
    expect(parts.join(' '), text);
  });

  test('mergeSummaries no repite conceptos y usa el resumen final', () {
    const a = StudySummary(concepts: [(term: 'Poder', meaning: 'a')], ideas: ['i1'], brief: 'b1');
    const b = StudySummary(concepts: [(term: 'poder', meaning: 'b'), (term: 'Ley', meaning: 'c')], ideas: ['i2'], brief: 'b2');
    const overall = StudySummary(concepts: [(term: 'Estrategia', meaning: 'd')], ideas: [], brief: 'final');
    final m = mergeSummaries([a, b], overall: overall);
    expect(m.concepts.map((c) => c.term), ['Estrategia', 'Poder', 'Ley']);
    expect(m.ideas, ['i1', 'i2']);
    expect(m.brief, 'final');
    expect(m.toLines().first, 'final');
  });

  test('studyOutline arma la lista de lo que enumera el documento', () {
    final pages = [
      for (var i = 1; i <= 4; i++) 'LEY Nº\n$i\nTÍTULO NÚMERO $i\nCRITERIO\nTexto.',
    ];
    final o = studyOutline(pages, 0, 4)!;
    expect(o.$1, 'Las 4 leyes');
    expect(o.$2.first, 'Ley 1 · Título número 1');
    expect(studyOutline(pages, 0, 2), isNull); // menos de tres
    const s = StudySummary(concepts: [], ideas: ['Idea.'], brief: '');
    final lines = s.withOutline(o.$1, o.$2).toLines();
    expect(lines, containsAllInOrder(['Las 4 leyes.', 'Ley 1. Título número 1.']));
  });

  test('StudySummary.fromMap ignora lo vacío', () {
    final s = StudySummary.fromMap({
      'concepts': [
        {'term': ' ', 'meaning': 'x'},
        {'term': 'Ley', 'meaning': 'norma'},
      ],
      'ideas': ['', 'idea'],
      'brief': ' breve ',
    });
    expect(s.concepts.single.term, 'Ley');
    expect(s.ideas, ['idea']);
    expect(s.brief, 'breve');
  });
}
