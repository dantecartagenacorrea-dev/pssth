import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/summarizer.dart';

void main() {
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
}
