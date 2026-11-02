import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/platform/formula_model_reader.dart';

Uint8List _sheet(int w, int h, List<(int, int, int, int)> boxes) {
  final ink = Uint8List(w * h);
  for (final (x0, y0, x1, y1) in boxes) {
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        ink[y * w + x] = 1;
      }
    }
  }
  return ink;
}

void main() {
  group('limpiar la foto para el modelo', () {
    test('lo que toca el borde se quita, también de la imagen', () {
      const w = 100, h = 100;
      final ink = _sheet(w, h, [(0, 0, 100, 5), (40, 40, 60, 60)]);
      final clean = Uint8List(w * h * 3); // todo negro
      final kept = dropBorderInk(ink, w, h, clean);
      expect(kept[2 * w + 50], 0, reason: 'la franja del borde se va');
      expect(kept[50 * w + 50], 1, reason: 'lo escrito queda');
      expect(clean[(2 * w + 50) * 3], 255);
      expect(clean[(50 * w + 50) * 3], 0);
    });

    test('el recorte abarca lo escrito', () {
      final ink = _sheet(100, 100, [(20, 30, 40, 50), (60, 30, 80, 50)]);
      expect(inkBounds(ink, 100, 100), (left: 20, top: 30, right: 79, bottom: 49));
    });

    test('un punto suelto no estira el recorte', () {
      final ink = _sheet(100, 100, [(40, 40, 60, 60), (5, 5, 6, 6)]);
      expect(inkBounds(ink, 100, 100), (left: 40, top: 40, right: 59, bottom: 59));
    });

    test('sin nada escrito no hay recorte', () {
      expect(inkBounds(Uint8List(100), 10, 10), isNull);
    });
  });
}
