// Prueba mínima de humo: la lógica se prueba en los demás archivos de test/.
import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/playback/tts_audio_handler.dart';

void main() {
  test('velocidad 1.0 equivale a la velocidad normal del motor (0.5)', () {
    expect(ttsRateFor(1.0), 0.5);
    expect(ttsRateFor(2.0), 1.0);
    expect(ttsRateFor(0.5), 0.25);
  });
}
