import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/live_audio.dart';
import 'package:lector_pdf/domain/window_merge.dart';

Float32List _ramp(int from, int count) => Float32List.fromList([for (var i = 0; i < count; i++) (from + i).toDouble()]);

void main() {
  group('LiveWindows', () {
    test('entrega cada ventana apenas tiene el audio, con las muestras correctas', () {
      final live = LiveWindows(window: 4, overlap: 1);
      expect(live.add(_ramp(0, 3)), isEmpty);
      final first = live.add(_ramp(3, 2));
      expect(first.map((w) => (w.start, w.end)), [(0, 4)]);
      expect(first.single.samples, [0, 1, 2, 3]);
      final second = live.add(_ramp(5, 2));
      expect(second.map((w) => (w.start, w.end)), [(3, 7)]);
      expect(second.single.samples, [3, 4, 5, 6]);
    });

    test('un bloque grande de audio puede dar varias ventanas', () {
      final live = LiveWindows(window: 4, overlap: 1);
      expect(live.add(_ramp(0, 10)).map((w) => (w.start, w.end)), [(0, 4), (3, 7), (6, 10)]);
    });

    test('al terminar, la última ventana llega hasta el final con su largo completo', () {
      final live = LiveWindows(window: 4, overlap: 1);
      live.add(_ramp(0, 8));
      final last = live.finish();
      expect((last?.start, last?.end), (4, 8));
      expect(last?.samples, [4, 5, 6, 7]);
    });

    test('un audio corto sale en una sola ventana al terminar', () {
      final live = LiveWindows(window: 4, overlap: 1);
      live.add(_ramp(0, 3));
      final last = live.finish();
      expect((last?.start, last?.end), (0, 3));
      expect(last?.samples, [0, 1, 2]);
    });

    test('si el audio termina justo con una ventana no agrega otra', () {
      final live = LiveWindows(window: 4, overlap: 1);
      live.add(_ramp(0, 7));
      expect(live.finish(), isNull);
    });

    test('sin audio no hay ventana', () {
      expect(LiveWindows(window: 4, overlap: 1).finish(), isNull);
    });

    test('corta igual que la transcripción de un archivo completo', () {
      for (final length in [3, 40, 41, 70, 96, 100, 137]) {
        final live = LiveWindows(window: 40, overlap: 10);
        final spans = [for (final w in live.add(Float32List(length))) (w.start, w.end)];
        final last = live.finish();
        if (last != null) spans.add((last.start, last.end));
        expect(spans, audioWindows(length, window: 40, overlap: 10), reason: 'largo $length');
      }
    });

    test('no guarda más audio del que necesita', () {
      final live = LiveWindows(window: 40, overlap: 10);
      for (var i = 0; i < 1000; i++) {
        live.add(Float32List(7));
      }
      expect(live.bufferedSamples, lessThanOrEqualTo(47));
    });
  });

  group('Pcm16Decoder', () {
    test('convierte a valores entre -1 y 1', () {
      final out = Pcm16Decoder().convert(Uint8List.fromList([0x00, 0x40, 0x00, 0xC0]));
      expect(out, [0.5, -0.5]);
    });

    test('una muestra partida entre dos bloques no se pierde', () {
      final d = Pcm16Decoder();
      expect(d.convert(Uint8List.fromList([0x00, 0x40, 0x00])), [0.5]);
      expect(d.convert(Uint8List.fromList([0xC0])), [-0.5]);
    });
  });

  test('la cabecera WAV declara el tamaño y el formato de la grabación', () {
    final h = ByteData.sublistView(pcm16WavHeader(dataBytes: 3200, sampleRate: 16000));
    String tag(int at) => String.fromCharCodes([for (var i = at; i < at + 4; i++) h.getUint8(i)]);
    expect(h.lengthInBytes, 44);
    expect(tag(0), 'RIFF');
    expect(tag(8), 'WAVE');
    expect(tag(36), 'data');
    expect(h.getUint32(4, Endian.little), 3236);
    expect(h.getUint16(22, Endian.little), 1);
    expect(h.getUint32(24, Endian.little), 16000);
    expect(h.getUint32(28, Endian.little), 32000);
    expect(h.getUint16(34, Endian.little), 16);
    expect(h.getUint32(40, Endian.little), 3200);
  });
}
