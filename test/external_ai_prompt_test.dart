import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/external_ai_prompt.dart';

void main() {
  test('trae las instrucciones antes del texto completo', () {
    final prompt = jsonSummaryPrompt('La clase trató sobre hornos.');
    expect(prompt, contains('Usa solo lo que dice el texto'));
    expect(prompt, contains('no lo adivines'));
    expect(prompt, contains('dice X; probablemente Y'));
    expect(prompt, contains('(deducido)'));
    expect(prompt, contains('qué va antes de qué'));
    expect(prompt.endsWith('La clase trató sobre hornos.'), isTrue);
    expect(prompt.indexOf('Usa solo'), lessThan(prompt.indexOf('La clase')));
  });

  test('la versión para la app pide JSON con las mismas reglas', () {
    final prompt = jsonSummaryPrompt('La clase trató sobre hornos.');
    expect(prompt, contains('JSON'));
    expect(prompt, contains('"concepts"'));
    expect(prompt, contains('(deducido)'));
    expect(prompt.endsWith('La clase trató sobre hornos.'), isTrue);
  });

  test('el repaso trae el resumen y el texto, y pide revisar el orden de las tareas', () {
    final prompt = jsonReviewPrompt('La tarea 5 va después de la 2.', '{"brief":"x"}');
    expect(prompt, contains('{"brief":"x"}'));
    expect(prompt, contains('después de la Y'));
    expect(prompt, contains('certificados'));
    expect(prompt, contains('JSON'));
    expect(prompt.endsWith('La tarea 5 va después de la 2.'), isTrue);
  });

  test('quita los espacios sobrantes del texto', () {
    expect(jsonSummaryPrompt('  hola  \n').endsWith('hola'), isTrue);
  });

  test('avisa si el texto es demasiado largo para enviarlo de una vez', () {
    expect(fitsExternalAi('a' * externalAiMaxChars), isTrue);
    expect(fitsExternalAi('a' * (externalAiMaxChars + 1)), isFalse);
  });

  test('un texto vacío no se envía', () {
    expect(fitsExternalAi('   '), isFalse);
  });
}
