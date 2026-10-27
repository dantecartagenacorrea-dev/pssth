import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/wav_audio.dart';

void main() {
  test('el volumen sigue al audio: silencio 0, lo más fuerte 1', () {
    const rate = 1000; // 50 muestras por tramo de 50 ms
    final s = Float32List(150);
    for (var i = 50; i < 100; i++) {
      s[i] = 0.2; // tramo medio, suave
    }
    for (var i = 100; i < 150; i++) {
      s[i] = 0.8; // tramo final, fuerte
    }
    final env = WavAudio(s, rate).envelope();
    expect(env.length, 3);
    expect(env[0], 0);
    expect(env[1], closeTo(0.25, 1e-6));
    expect(env[2], closeTo(1, 1e-6));
  });

  test('un audio en silencio no se mueve', () {
    expect(WavAudio(Float32List(500), 1000).envelope(), everyElement(0));
    expect(WavAudio(Float32List(0), 1000).envelope(), isEmpty);
  });
}
