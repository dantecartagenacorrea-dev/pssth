import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/level_booster.dart';

/// Tono de voz simulado, del volumen pedido.
Float32List _tone(double amplitude, {int samples = 16000 * 4}) =>
    Float32List.fromList([for (var i = 0; i < samples; i++) amplitude * sin(2 * pi * 200 * i / 16000)]);

double _peak(Iterable<double> s) => s.fold(0.0, (p, v) => max(p, v.abs()));

void main() {
  test('una voz baja se sube hasta acercarse al objetivo', () {
    final out = LevelBooster().process(_tone(0.1));
    final end = out.sublist(out.length - 16000);
    expect(_peak(end), closeTo(LevelBooster.target, 0.05));
  });

  test('no sube más que el máximo aunque la voz sea muy baja', () {
    final out = LevelBooster().process(_tone(0.005));
    final end = out.sublist(out.length - 16000);
    expect(_peak(end), closeTo(0.005 * LevelBooster.maxGain, 0.01));
  });

  test('el silencio no se amplifica', () {
    final out = LevelBooster().process(_tone(0.001));
    expect(_peak(out), closeTo(0.001, 0.0005));
  });

  test('una voz fuerte no se baja ni se recorta', () {
    final out = LevelBooster().process(_tone(0.9));
    expect(_peak(out), lessThanOrEqualTo(1));
    expect(_peak(out), greaterThan(0.6));
  });

  test('un golpe fuerte después de una voz baja no se satura', () {
    final b = LevelBooster();
    b.process(_tone(0.02));
    final out = b.process(_tone(0.9, samples: 3200));
    expect(_peak(out), lessThanOrEqualTo(1));
    expect(_peak(out.sublist(1600)), closeTo(LevelBooster.target, 0.05));
  });

  test('funciona igual aunque el audio llegue en bloques de cualquier tamaño', () {
    final whole = LevelBooster().process(_tone(0.1, samples: 16000));
    final parts = LevelBooster();
    final source = _tone(0.1, samples: 16000);
    final out = <double>[];
    for (var i = 0; i < source.length; i += 777) {
      out.addAll(parts.process(Float32List.sublistView(source, i, min(i + 777, source.length))));
    }
    expect(out.length, whole.length);
    for (var i = 0; i < out.length; i++) {
      expect(out[i], closeTo(whole[i], 0.001));
    }
  });

  test('pasa a PCM de 16 bits sin desbordarse', () {
    final bytes = pcm16Bytes(Float32List.fromList([0, 0.5, -0.5, 1, -1]));
    final v = ByteData.sublistView(bytes);
    expect(bytes.length, 10);
    expect(v.getInt16(0, Endian.little), 0);
    expect(v.getInt16(2, Endian.little), 16384);
    expect(v.getInt16(4, Endian.little), -16384);
    expect(v.getInt16(6, Endian.little), 32767);
    expect(v.getInt16(8, Endian.little), -32767);
  });
}
