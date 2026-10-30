import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/study.dart';

void main() {
  test('lee en voz alta la pregunta con sus letras y el resultado', () {
    const q = QuizQuestion(
      question: 'Completa la frase del texto: «El _____ del rey.»',
      options: ['poder', 'ministro'],
      answer: 0,
      explanation: 'El texto dice: «El poder del rey.»',
    );
    expect(quizQuestionSpeech(q), ['Completa la frase del texto: El … del rey.', 'A: poder.', 'B: ministro.']);
    expect(quizAnswerSpeech(q, 0), ['¡Correcto!', 'El texto dice: El poder del rey.']);
    expect(quizAnswerSpeech(q, 1).first, 'No era esa. Era la A: poder.');
  });
}
