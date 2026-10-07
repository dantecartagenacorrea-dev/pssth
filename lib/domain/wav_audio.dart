import 'dart:typed_data';

/// Lectura mínima de WAV PCM (16 bits, mono o estéreo → mono) y corte en
/// segmentos por silencio, sin dependencias.
class WavAudio {
  WavAudio(this.samples, this.sampleRate);
  final Float32List samples;
  final int sampleRate;

  Duration get duration => Duration(milliseconds: (samples.length * 1000 / sampleRate).round());

  static WavAudio parse(Uint8List bytes) {
    final b = ByteData.sublistView(bytes);
    if (bytes.length < 44 || String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') {
      throw const FormatException('No es un WAV');
    }
    var pos = 12;
    var channels = 1, rate = 16000, bits = 16;
    int? dataStart, dataLen;
    while (pos + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = b.getUint32(pos + 4, Endian.little);
      if (id == 'fmt ') {
        channels = b.getUint16(pos + 10, Endian.little);
        rate = b.getUint32(pos + 12, Endian.little);
        bits = b.getUint16(pos + 22, Endian.little);
      } else if (id == 'data') {
        dataStart = pos + 8;
        dataLen = size;
        break;
      }
      pos += 8 + size + (size & 1);
    }
    if (dataStart == null || bits != 16) {
      throw const FormatException('WAV no compatible');
    }
    final end = (dataStart + (dataLen ?? 0)).clamp(0, bytes.length);
    final frames = (end - dataStart) ~/ (2 * channels);
    final out = Float32List(frames);
    for (var i = 0; i < frames; i++) {
      var acc = 0;
      for (var c = 0; c < channels; c++) {
        acc += b.getInt16(dataStart + (i * channels + c) * 2, Endian.little);
      }
      out[i] = acc / channels / 32768.0;
    }
    return WavAudio(out, rate);
  }

  /// Trozos de como máximo [maxSeconds], cortando en el punto más silencioso
  /// entre [minSeconds] y [maxSeconds] (para no partir palabras).
  List<Float32List> splitBySilence({double maxSeconds = 28, double minSeconds = 15, double frameSeconds = 0.02}) {
    final maxLen = (maxSeconds * sampleRate).round();
    final minLen = (minSeconds * sampleRate).round();
    final frame = (frameSeconds * sampleRate).round().clamp(1, 1 << 20);
    final out = <Float32List>[];
    var start = 0;
    while (samples.length - start > maxLen) {
      var bestCut = start + maxLen;
      var bestEnergy = double.infinity;
      for (var i = start + minLen; i + frame <= start + maxLen; i += frame) {
        var e = 0.0;
        for (var j = i; j < i + frame; j++) {
          e += samples[j] * samples[j];
        }
        if (e < bestEnergy) {
          bestEnergy = e;
          bestCut = i + frame ~/ 2;
        }
      }
      out.add(samples.sublist(start, bestCut));
      start = bestCut;
    }
    if (samples.length > start) out.add(samples.sublist(start));
    return out;
  }

  /// ¿Hay algo más que silencio?
  bool get hasSound {
    var e = 0.0;
    for (final s in samples) {
      e += s * s;
    }
    return samples.isNotEmpty && e / samples.length > 1e-6;
  }
}
