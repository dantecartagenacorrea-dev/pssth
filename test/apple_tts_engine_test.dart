import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:lector_pdf/playback/engines/apple_tts_engine.dart';

/// Voz del sistema que nunca termina ni avisa palabras: quedó muda.
class _MuteTts extends FlutterTts {
  int spoken = 0;

  @override
  Future<dynamic> speak(String text, {bool focus = false}) {
    spoken++;
    return Completer<dynamic>().future;
  }

  @override
  Future<dynamic> stop() async => 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('si la voz queda muda dos veces avisa el fallo en vez de saltar la frase', () async {
    final tts = _MuteTts();
    final engine = AppleTtsEngine(tts, Duration.zero);

    await expectLater(engine.speak('a'), throwsStateError);
    expect(tts.spoken, 2);
  });

  test('detenerla mientras está muda no cuenta como fallo', () async {
    final tts = _MuteTts();
    final engine = AppleTtsEngine(tts, const Duration(seconds: 30));

    final speaking = engine.speak('hola');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await engine.stop();

    await expectLater(speaking, completes);
  });
}
