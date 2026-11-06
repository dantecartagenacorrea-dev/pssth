import 'dart:typed_data';

/// Sube el volumen del micrófono: Android no deja a las apps fijar su ganancia,
/// así que se amplifica el audio ya grabado. Baja al instante ante un golpe fuerte
/// (no satura) y sube despacio (no bombea el ruido entre palabras).
class LevelBooster {
  /// Volumen al que se quiere llevar la voz.
  static const target = 0.7;

  /// Hasta 16 veces (+24 dB): probado con la voz atenuada hasta 30 dB.
  static const maxGain = 16.0;

  /// Por debajo de esto se considera silencio y la ganancia no sube.
  static const _silence = 0.002;

  /// Por muestra, a 16 kHz: el nivel seguido cae en ~0,6 s y la ganancia sube en ~1,25 s.
  static const _levelFall = 0.9999;
  static const _gainRise = 0.00005;

  double _level = 0;
  double _gain = 1;

  /// Devuelve tantas muestras como recibe, sin retrasar el audio. Trabaja muestra
  /// por muestra para no depender del tamaño de los bloques del micrófono.
  Float32List process(Float32List input) {
    final out = Float32List(input.length);
    for (var i = 0; i < input.length; i++) {
      final x = input[i];
      final size = x.abs();
      _level = size > _level ? size : _level * _levelFall;
      if (_level > _silence) {
        final limit = target / _level;
        final wanted = limit < maxGain ? limit : maxGain;
        _gain = wanted < _gain ? wanted : _gain + (wanted - _gain) * _gainRise;
      }
      final v = x * _gain;
      out[i] = v > 1 ? 1 : (v < -1 ? -1 : v);
    }
    return out;
  }
}

/// Muestras entre -1 y 1 a PCM de 16 bits.
Uint8List pcm16Bytes(Float32List samples) {
  final out = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(out);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, (samples[i] * 32767).round(), Endian.little);
  }
  return out;
}
