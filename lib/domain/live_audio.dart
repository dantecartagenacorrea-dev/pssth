import 'dart:typed_data';

/// Trozo del audio listo para reconocer; [start] y [end] en muestras.
class AudioWindow {
  const AudioWindow(this.start, this.end, this.samples);
  final int start;
  final int end;
  final Float32List samples;
}

/// Arma las ventanas a medida que llega el audio del micrófono, con los mismos
/// cortes que `audioWindows` da para un archivo completo. Guarda solo lo necesario.
class LiveWindows {
  LiveWindows({required this.window, required this.overlap});

  final int window;
  final int overlap;

  Float32List _buffer = Float32List(0);
  int _bufferStart = 0;
  int _total = 0;
  int _nextStart = 0;
  int _lastEnd = 0;

  int get bufferedSamples => _buffer.length;

  List<AudioWindow> add(Float32List chunk) {
    _buffer = Float32List(_buffer.length + chunk.length)
      ..setAll(0, _buffer)
      ..setAll(_buffer.length, chunk);
    _total += chunk.length;
    final ready = <AudioWindow>[];
    while (_nextStart + window <= _total) {
      ready.add(_slice(_nextStart, _nextStart + window));
      _lastEnd = _nextStart + window;
      _nextStart += window - overlap;
    }
    if (ready.isNotEmpty || _buffer.length > window) _trim();
    return ready;
  }

  /// Lo que faltó reconocer al terminar la grabación, o null si no falta nada.
  AudioWindow? finish() {
    if (_total == 0 || _total == _lastEnd) return null;
    final start = _total > window ? _total - window : 0;
    return _slice(start, _total);
  }

  AudioWindow _slice(int start, int end) =>
      AudioWindow(start, end, Float32List.sublistView(_buffer, start - _bufferStart, end - _bufferStart).sublist(0));

  /// Hace falta desde la próxima ventana o, para la del final, el último tramo.
  void _trim() {
    final tail = _total > window ? _total - window : 0;
    final keepFrom = _nextStart < tail ? _nextStart : tail;
    if (keepFrom <= _bufferStart) return;
    _buffer = _buffer.sublist(keepFrom - _bufferStart);
    _bufferStart = keepFrom;
  }
}

/// Bytes de PCM de 16 bits a muestras entre -1 y 1. Un bloque puede terminar a
/// mitad de una muestra: ese byte se guarda para el siguiente.
class Pcm16Decoder {
  int? _carry;

  Float32List convert(Uint8List bytes) {
    final carry = _carry;
    final data = carry == null
        ? bytes
        : (Uint8List(bytes.length + 1)
            ..[0] = carry
            ..setRange(1, bytes.length + 1, bytes));
    final count = data.length ~/ 2;
    _carry = data.length.isOdd ? data.last : null;
    final view = ByteData.sublistView(data);
    return Float32List(count)..setAll(0, [for (var i = 0; i < count; i++) view.getInt16(i * 2, Endian.little) / 32768]);
  }
}

/// Cabecera de un WAV PCM de 16 bits y un canal.
Uint8List pcm16WavHeader({required int dataBytes, required int sampleRate}) {
  final out = Uint8List(44);
  final h = ByteData.sublistView(out);
  void tag(int at, String s) => out.setAll(at, s.codeUnits);
  tag(0, 'RIFF');
  h.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, 1, Endian.little);
  h.setUint32(24, sampleRate, Endian.little);
  h.setUint32(28, sampleRate * 2, Endian.little);
  h.setUint16(32, 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  h.setUint32(40, dataBytes, Endian.little);
  return out;
}
