import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/summarizer.dart';

void main() {
  test('resumen para estudiar sin IA: conceptos, ideas y resumen breve', () {
    final text = List.generate(
      12,
      (i) =>
          'El poder se conquista con estrategia y paciencia número $i. '
          'La estrategia exige observar a los rivales con calma. '
          'Quien domina la paciencia controla el tiempo del juego.',
    ).join(' ');
    final s = studySummaryExtractive(text);
    expect(s.ideas, isNotEmpty);
    expect(s.brief, isNotEmpty);
    final terms = s.concepts.map((c) => c.term.toLowerCase()).toList();
    expect(terms, contains('estrategia'));
    expect(terms, contains('paciencia'));
    expect(s.concepts.every((c) => c.meaning.isNotEmpty), isTrue);
    expect(studySummaryExtractive('corto').isEmpty, isTrue);
  });

  const texto = '''
La masonería simbólica trabaja con herramientas de la construcción para enseñar virtudes morales a sus miembros.
El mandil es una de las herramientas simbólicas más antiguas de la masonería y representa el trabajo honesto.
Los profanos suelen preguntar por el significado del mandil y por las herramientas de la masonería simbólica.
Ayer llovió mucho en la ciudad y las calles quedaron llenas de agua durante toda la tarde.
Los miembros de la masonería aprenden que el trabajo y las virtudes morales son la base de la construcción personal.
El mandil se entrega al iniciado como símbolo del trabajo honesto y de las virtudes que debe cultivar.
Un vecino comentó que el autobús llegó tarde porque había obras en la avenida principal del barrio.
La masonería simbólica enseña con alegorías y las herramientas representan virtudes morales concretas del trabajo.
El iniciado recibe el mandil y comprende que el trabajo honesto es la base de la masonería simbólica.
Las herramientas de la construcción sirven como lenguaje simbólico para transmitir virtudes morales y trabajo.
''';

  test('devuelve frases del texto original, en orden, sin inventar', () {
    final r = summarizeExtractive(texto, ratio: 0.4, minSentences: 3);
    expect(r.length, inInclusiveRange(3, 5));
    final orig = texto.replaceAll('\n', ' ');
    for (final s in r) {
      expect(orig.contains(s), isTrue);
    }
    final pos = r.map(orig.indexOf).toList();
    expect([...pos]..sort(), pos);
  });

  test('prefiere el tema central frente a frases laterales', () {
    final r = summarizeExtractive(texto, ratio: 0.4, minSentences: 3).join(' ');
    expect(r.contains('mandil') || r.contains('masonería'), isTrue);
    expect(r.contains('autobús'), isFalse);
    expect(r.contains('llovió'), isFalse);
  });

  test('textos vacíos o muy cortos', () {
    expect(summarizeExtractive(''), isEmpty);
    expect(summarizeExtractive('Una frase suficientemente larga para contar.'), hasLength(1));
  });

  test('es determinista y rápido con un documento largo', () {
    final largo = List.generate(
      5000,
      (i) => 'La frase número ${i % 97} habla del tema ${i % 13} con palabras comunes del documento largo.',
    ).join(' ');
    final sw = Stopwatch()..start();
    final a = summarizeExtractive(largo);
    final b = summarizeExtractive(largo);
    expect(a, b);
    expect(a.length, lessThanOrEqualTo(30));
    expect(sw.elapsedMilliseconds, lessThan(5000));
  });

  test('el resumen para estudiar no toma títulos en mayúsculas ni palabras comunes', () {
    const text =
        'LAS 48 LEYES DEL PODER ROBERT GREENE EDITORIAL ATLANTIDA BUENOS AIRES. '
        'LEY N° 1 página 29 NUNCA LE HAGA SOMBRA A SU AMO Usted debe hacer que sus superiores se sientan superiores. '
        'La ingratitud tiene una historia larga y profunda entre los cortesanos. '
        'Los cortesanos que olvidan la ingratitud de su amo pierden el favor. '
        'Usted nunca debe confiar en la gratitud de los cortesanos ni del amo. '
        'La gratitud del amo dura poco y la ingratitud dura mucho entre cortesanos. '
        'Un cortesano prudente conoce la ingratitud y la gratitud de cada amo.';
    final s = studySummaryExtractive(text);
    final terms = [for (final c in s.concepts) c.term.toLowerCase()];
    expect(terms, isNot(contains('usted')));
    expect(terms, isNot(contains('nunca')));
    expect(terms, isNot(contains('leyes')));
    for (final part in [s.brief, ...s.ideas, for (final c in s.concepts) c.meaning]) {
      expect(part, isNot(contains('GREENE')), reason: part);
      expect(part, isNot(contains('NUNCA LE HAGA')), reason: part);
    }
  });

  test('quita el rótulo de sección pegado a la frase', () {
    expect(withoutHeading('Interpretación César Borgia era un maestro.'), 'César Borgia era un maestro.');
    expect(withoutHeading('Interpretación de los hechos.'), 'Interpretación de los hechos.');
  });

  test('no usa frases que solo se entienden con la anterior ni rótulos pegados', () {
    const text =
        'Fouquet ofreció una fiesta enorme para impresionar al rey en su castillo nuevo. '
        'Ése era uno de los pilares del prestigio del ministro ante la corte. '
        'Era la posición de menor seguridad que existía en toda la corte francesa. '
        'Se había recreado en un hombre de prestigio dentro de la corte francesa. '
        'Interpretación Fouquet no entendió que el rey quería brillar más que su ministro. '
        'El rey encarceló al ministro poco después de la fiesta del castillo nuevo. '
        'Luis construyó Versailles para superar el castillo nuevo y la fiesta del ministro. '
        'La corte francesa aprendió contra su voluntad que el prestigio del rey no se discute.';
    final s = studySummaryExtractive(text);
    for (final part in [s.brief, ...s.ideas, for (final c in s.concepts) c.meaning]) {
      expect(part, isNot(startsWith('Ése')), reason: part);
      expect(part, isNot(startsWith('Era ')), reason: part);
      expect(part, isNot(startsWith('Se había')), reason: part);
      expect(part, isNot(startsWith('Interpretación')), reason: part);
    }
    expect(s.ideas, isNotEmpty);
    expect([for (final c in s.concepts) c.term.toLowerCase()], isNot(contains('contra')));
  });
}
