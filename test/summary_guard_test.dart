import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/study.dart';
import 'package:lector_pdf/domain/summary_guard.dart';

void main() {
  const source =
      'La panadería abre de lunes a sábado. El curso empieza el 3 de marzo y dura dos semanas. '
      'El método KLM ordena los hornos por temperatura.';

  Map<String, Object> note(String note, String quote) => {
    'notes': [
      {'note': note, 'quote': quote},
    ],
  };

  group('trustedNotes', () {
    test('conserva el apunte cuya cita está en el texto', () {
      final raw = note('El curso empieza el 3 de marzo.', 'El curso empieza el 3 de marzo');
      expect(trustedNotes(raw, source), ['El curso empieza el 3 de marzo.']);
    });

    test('descarta el apunte cuya cita no está en el texto', () {
      final raw = note('Los hornos usan energía solar.', 'instalaron paneles solares gigantes');
      expect(trustedNotes(raw, source), isEmpty);
    });

    test('descarta el apunte con una cifra que el texto no trae', () {
      final raw = note('El curso cuesta 500 pesos.', 'El curso empieza');
      expect(trustedNotes(raw, source), isEmpty);
    });

    test('descarta el apunte con una sigla que el texto no trae', () {
      final raw = note('El método XYZ ordena los hornos.', 'ordena los hornos');
      expect(trustedNotes(raw, source), isEmpty);
    });

    test('acepta una cifra que el texto escribe con letras', () {
      final raw = note('El curso dura 2 semanas.', 'dura dos semanas');
      expect(trustedNotes(raw, source), ['El curso dura 2 semanas.']);
    });

    test('quita los apuntes repetidos', () {
      final raw = {
        'notes': [
          {'note': 'Abre de lunes a sábado.', 'quote': 'abre de lunes a sábado'},
          {'note': 'abre de lunes a sábado.', 'quote': 'abre de lunes a sábado'},
        ],
      };
      expect(trustedNotes(raw, source), ['Abre de lunes a sábado.']);
    });

    test('una respuesta mal formada no deja apuntes', () {
      expect(trustedNotes('nada', source), isEmpty);
      expect(trustedNotes({'notes': 'nada'}, source), isEmpty);
    });
  });

  group('withoutInvented', () {
    test('quita conceptos e ideas con datos que el texto no trae y conserva el resto', () {
      const summary = StudySummary(
        concepts: [(term: 'KLM', meaning: 'Ordena los hornos.'), (term: 'PQR', meaning: 'Una sigla inventada.')],
        ideas: ['El curso dura dos semanas.', 'Se fundó en 1950.'],
        brief: 'Un curso de panadería. Tiene 40 alumnos.',
      );
      final clean = withoutInvented(summary, source);
      expect(clean.concepts.map((c) => c.term), ['KLM']);
      expect(clean.ideas, ['El curso dura dos semanas.']);
      expect(clean.brief, 'Un curso de panadería.');
    });
  });
}
