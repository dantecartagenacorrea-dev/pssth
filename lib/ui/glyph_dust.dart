import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Puntos de polvo que forman cada letra: se dibuja la letra una vez en una
/// imagen pequeña y se guarda un punto por cada lugar con tinta. Así el texto
/// puede deshacerse en polvo y volver a juntarse en su forma exacta.
class GlyphDust {
  GlyphDust._();

  /// Separación entre puntos, en píxeles lógicos.
  static const step = 1.5;

  static final _cache = <String, Float32List>{};
  static final _pending = <String, Future<void>>{};

  static String _key(String ch, TextStyle s, TextScaler scaler) =>
      '$ch|${s.fontSize}|${s.fontWeight}|${s.fontFamily}|${s.height}|${scaler.scale(1)}';

  /// Puntos (x, y alternados, desde la esquina de la letra) o null si aún no
  /// se prepararon.
  static Float32List? of(String ch, TextStyle s, TextScaler scaler) => _cache[_key(ch, s, scaler)];

  /// Prepara las letras de [text] que falten; termina cuando están todas.
  static Future<void> load(String text, TextStyle s, TextScaler scaler) {
    final waits = <Future<void>>[];
    for (final ch in text.split('').toSet()) {
      if (ch.trim().isEmpty) continue;
      final key = _key(ch, s, scaler);
      if (_cache.containsKey(key)) continue;
      waits.add(_pending.putIfAbsent(key, () async {
        _cache[key] = await _sample(ch, s, scaler);
        _pending.remove(key);
      }));
    }
    return Future.wait(waits);
  }

  static Future<Float32List> _sample(String ch, TextStyle s, TextScaler scaler) async {
    final tp = TextPainter(
      text: TextSpan(text: ch, style: s.copyWith(color: const Color(0xFFFFFFFF), shadows: const [])),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final w = tp.width.ceil() + 2;
    final h = tp.height.ceil() + 2;
    final recorder = ui.PictureRecorder();
    tp.paint(Canvas(recorder), const Offset(1, 1));
    tp.dispose();
    final image = await recorder.endRecording().toImage(w, h);
    final data = await image.toByteData();
    image.dispose();
    final out = <double>[];
    if (data == null) return Float32List(0);
    var row = 0;
    for (var y = 0.0; y < h; y += step, row++) {
      // Filas alternadas desplazadas: el polvo no queda en cuadrícula.
      for (var x = row.isOdd ? step / 2 : 0.0; x < w; x += step) {
        final alpha = data.getUint8((y.toInt() * w + x.toInt()) * 4 + 3);
        if (alpha > 110) {
          out
            ..add(x - 1)
            ..add(y - 1);
        }
      }
    }
    return Float32List.fromList(out);
  }
}
