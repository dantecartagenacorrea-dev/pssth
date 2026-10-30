import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/quiz_local.dart';
import 'package:lector_pdf/domain/summarizer.dart' show withoutHeading;

void main() {
  const text =
      'La fotosíntesis es el proceso por el cual las plantas producen su alimento. '
      'Durante la fotosíntesis, la clorofila captura la energía de la luz solar. '
      'La clorofila se encuentra en los cloroplastos de las células vegetales. '
      'Los cloroplastos transforman el dióxido de carbono y el agua en glucosa. '
      'La glucosa es la fuente de energía que usan las plantas para crecer. '
      'Las plantas liberan oxígeno como resultado de este proceso. '
      'El oxígeno que respiramos proviene en gran parte de las plantas y las algas. '
      'Las algas también realizan fotosíntesis en los océanos del planeta. '
      'Sin la luz solar, las plantas no podrían fabricar glucosa ni liberar oxígeno. '
      'Los cloroplastos y la clorofila son esenciales para la vida en la Tierra.';

  test('arma preguntas de completar la frase con términos del propio texto', () {
    final qs = localQuiz(text, max: 3, rnd: math.Random(1));
    expect(qs, isNotEmpty);
    for (final q in qs) {
      expect(q.question, contains('_____'));
      expect(q.options, hasLength(4));
      final correct = q.options[q.answer];
      // Con la respuesta en el blanco, la frase es la del texto.
      final sentence = q.question.substring(q.question.indexOf('«') + 1, q.question.lastIndexOf('»'));
      expect(text, contains(sentence.replaceFirst('_____', correct)));
      expect(q.explanation, startsWith('El texto dice'));
    }
  });

  test('no pregunta dos veces por el mismo término', () {
    final qs = localQuiz(text, max: 6, rnd: math.Random(2));
    final answers = [for (final q in qs) q.options[q.answer].toLowerCase()];
    expect(answers.toSet(), hasLength(answers.length));
  });

  test('quita el título en mayúsculas pegado al comienzo de la frase', () {
    expect(
      withoutHeading('LEY N° 43 página 449 TRABAJE SOBRE EL CORAZÓN DE LOS DEMÁS La coerción provoca una reacción.'),
      'La coerción provoca una reacción.',
    );
    // Una sigla en medio de la prosa no es un título.
    const prose = 'La ONU dijo que El Salvador firmó el acuerdo.';
    expect(withoutHeading(prose), prose);
  });

  test('las opciones no salen en mayúsculas de un título', () {
    const caps =
        'LA FOTOSÍNTESIS Y LA CLOROFILA Las plantas usan la clorofila para captar la luz. '
        'La fotosíntesis produce oxígeno y glucosa en las hojas. La glucosa alimenta a la planta. '
        'El oxígeno sale por los estomas de las hojas. Las hojas tienen estomas y clorofila. '
        'La luz llega a las hojas y la clorofila la capta.';
    for (final q in localQuiz(caps, max: 4, rnd: math.Random(3))) {
      expect(q.question, isNot(contains('LA FOTOSÍNTESIS')));
      for (final o in q.options) {
        expect(o, isNot(o.toUpperCase()), reason: 'opción $o');
      }
    }
  });

  test('con poco texto no inventa preguntas', () {
    expect(localQuiz('Hola. Esto es corto.', max: 3), isEmpty);
    expect(localQuiz(text, max: 0), isEmpty);
  });
}
