import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/wav_audio.dart';

Uint8List wav(List<double> samples, {int rate = 16000, int channels = 1}) {
  final n = samples.length;
  final b = ByteData(44 + n * 2 * channels);
  void s(int o, String t) {
    for (var i = 0; i < t.length; i++) {
      b.setUint8(o + i, t.codeUnitAt(i));
    }
  }

  s(0, 'RIFF');
  b.setUint32(4, 36 + n * 2 * channels, Endian.little);
  s(8, 'WAVE');
  s(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, channels, Endian.little);
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2 * channels, Endian.little);
  b.setUint16(32, 2 * channels, Endian.little);
  b.setUint16(34, 16, Endian.little);
  s(36, 'data');
  b.setUint32(40, n * 2 * channels, Endian.little);
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < channels; c++) {
      b.setInt16(44 + (i * channels + c) * 2, (samples[i] * 32767).round(), Endian.little);
    }
  }
  return b.buffer.asUint8List();
}

void main() {
  test('lee WAV mono y estéreo a mono', () {
    final a = WavAudio.parse(wav([0.5, -0.5, 0.25]));
    expect(a.sampleRate, 16000);
    expect(a.samples.length, 3);
    expect(a.samples[0], closeTo(0.5, 0.001));
    final st = WavAudio.parse(wav([0.5, -0.5], channels: 2));
    expect(st.samples.length, 2);
  });

  test('corta en el silencio, nunca más de 28 s por trozo', () {
    const rate = 16000;
    final s = List<double>.generate(70 * rate, (i) {
      final t = i / rate;
      final silent = (t > 20 && t < 21) || (t > 45 && t < 46);
      return silent ? 0.0 : 0.3 * math.sin(2 * math.pi * 220 * t);
    });
    final a = WavAudio.parse(wav(s));
    final parts = a.splitBySilence();
    expect(parts.length, 3);
    for (final p in parts) {
      expect(p.length <= 28 * rate, isTrue);
    }
    expect((parts[0].length / rate), closeTo(20.5, 0.6));
    expect(parts.fold<int>(0, (n, p) => n + p.length), s.length);
  });

  test('detecta silencio total', () {
    expect(WavAudio.parse(wav(List.filled(16000, 0.0))).hasSound, isFalse);
    expect(WavAudio.parse(wav(List.filled(16000, 0.1))).hasSound, isTrue);
  });

  test('rechaza datos que no son WAV', () {
    expect(() => WavAudio.parse(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });
}
