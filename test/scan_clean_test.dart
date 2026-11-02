import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/scan_clean.dart';

const _w = 600, _h = 800;

Uint8List _paper() => Uint8List(_w * _h)..fillRange(0, _w * _h, 240);

void _box(Uint8List page, int x, int y, int width, int height, int value) {
  for (var yy = y; yy < y + height; yy++) {
    for (var xx = x; xx < x + width; xx++) {
      page[yy * _w + xx] = value;
    }
  }
}

Uint8List _clean(Uint8List page) => cleanDocumentPage(page, Uint8List(_w * _h)..fillRange(0, _w * _h, 240), _w, _h);

void main() {
  group('copia limpia', () {
    test('una arruga clara se va; la tinta queda', () {
      final page = _paper();
      _box(page, 100, 300, 400, 3, 195); // arruga, 80 % del papel
      _box(page, 100, 400, 60, 30, 30); // tinta
      final out = _clean(page);
      expect(out[301 * _w + 300], 255);
      expect(out[415 * _w + 130], lessThan(40));
    });

    test('una letra tenue queda entera si tiene una parte oscura', () {
      final page = _paper();
      _box(page, 100, 400, 60, 30, 170); // trazo tenue
      _box(page, 120, 410, 10, 10, 60); // su parte más oscura
      final out = _clean(page);
      expect(out[405 * _w + 105], lessThan(255), reason: 'la parte tenue no se borra');
    });

    test('lo que toca el borde de la foto se va', () {
      final page = _paper();
      _box(page, 0, 300, 50, 40, 20);
      expect(_clean(page)[320 * _w + 10], 255);
    });

    test('las marcas chicas de los márgenes y los puntitos se van', () {
      final page = _paper();
      _box(page, 200, 5, 8, 8, 20); // marca del margen de arriba
      _box(page, 300, 400, 1, 2, 20); // puntito en medio
      _box(page, 100, 400, 60, 30, 30); // tinta
      final out = _clean(page);
      expect(out[9 * _w + 204], 255);
      expect(out[401 * _w + 300], 255);
      expect(out[415 * _w + 130], lessThan(40));
    });

    test('una letra pegada al margen no se borra si tiene texto al lado', () {
      final page = _paper();
      _box(page, 8, 200, 12, 18, 30); // la «A» de «Artículo», dentro del margen
      _box(page, 26, 200, 300, 18, 30); // el resto del renglón
      expect(_clean(page)[209 * _w + 14], lessThan(40));
    });

    test('una letra cortada por el borde tampoco, si tiene texto al lado', () {
      final page = _paper();
      _box(page, 0, 200, 14, 18, 30);
      _box(page, 20, 200, 300, 18, 30);
      expect(_clean(page)[209 * _w + 6], lessThan(40));
    });

    test('un trazo fino que no llega a oscuro se queda si tiene texto al lado', () {
      final page = _paper();
      _box(page, 100, 200, 2, 18, 150); // la «I» de «Inc.»
      _box(page, 108, 200, 200, 18, 30); // el resto del renglón
      expect(_clean(page)[209 * _w + 100], lessThan(255));
    });

    test('el mismo trazo solo, lejos del texto, se va', () {
      final page = _paper();
      _box(page, 100, 200, 2, 18, 150);
      _box(page, 300, 500, 200, 18, 30);
      expect(_clean(page)[209 * _w + 100], 255);
    });

    test('una raya larga y fina de sombra se va', () {
      final page = _paper();
      for (var i = 0; i < 200; i++) {
        _box(page, 100 + i, 200 + i, 2, 2, 110); // diagonal fina, oscura pero no negra
      }
      expect(_clean(page)[300 * _w + 200], 255);
    });

    test('una firma, larga, fina y negra, se queda', () {
      final page = _paper();
      for (var i = 0; i < 200; i++) {
        _box(page, 100 + i, 200 + i, 2, 2, 30);
      }
      expect(_clean(page)[300 * _w + 200], lessThan(40));
    });

    test('una marca alta de un doblez en el margen se va', () {
      final page = _paper();
      _box(page, 6, 200, 5, 60, 30);
      _box(page, 100, 200, 300, 18, 30);
      expect(_clean(page)[230 * _w + 8], 255);
    });

    test('una hoja vacía queda blanca', () {
      expect(_clean(_paper()).every((v) => v == 255), isTrue);
    });
  });

  group('renglones parejos', () {
    Uint8List lines(int Function(int x) shift) {
      final page = Uint8List(_w * _h)..fillRange(0, _w * _h, 255);
      for (var row = 100; row < 700; row += 40) {
        for (var x = 40; x < 560; x++) {
          for (var y = 0; y < 10; y++) {
            page[(row + y + shift(x)) * _w + x] = 0;
          }
        }
      }
      return page;
    }

    double spread(Uint8List page, int row) {
      // Dónde empieza el renglón en dos columnas lejanas.
      int topAt(int x) {
        for (var y = row - 20; y < row + 25; y++) {
          if (page[y * _w + x] < 128) return y;
        }
        return -1;
      }

      return (topAt(100) - topAt(500)).abs().toDouble();
    }

    test('un renglón inclinado queda más derecho', () {
      final tilted = lines((x) => x ~/ 60);
      expect(spread(straightenLines(tilted, _w, _h), 300), lessThan(spread(tilted, 300)));
    });

    test('una hoja ya derecha no se mueve', () {
      final page = lines((_) => 0);
      expect(straightenLines(page, _w, _h), page);
    });

    test('casi sin texto no toca nada', () {
      final page = Uint8List(_w * _h)..fillRange(0, _w * _h, 255);
      for (var y = 100; y < 110; y++) {
        for (var x = 40; x < 80; x++) {
          page[y * _w + x] = 0;
        }
      }
      expect(straightenLines(page, _w, _h), page);
    });
  });

  group('color de firmas y sellos', () {
    Uint8List rgbOf(Uint8List gray) {
      final rgb = Uint8List(_w * _h * 3);
      for (var i = 0; i < gray.length; i++) {
        rgb[i * 3] = rgb[i * 3 + 1] = rgb[i * 3 + 2] = gray[i];
      }
      return rgb;
    }

    Uint8List lumOf(Uint8List rgb) {
      final lum = Uint8List(_w * _h);
      for (var i = 0; i < lum.length; i++) {
        lum[i] = (rgb[i * 3] * 299 + rgb[i * 3 + 1] * 587 + rgb[i * 3 + 2] * 114) ~/ 1000;
      }
      return lum;
    }

    void paint(Uint8List rgb, int x, int y, int width, int height, (int, int, int) color) {
      for (var yy = y; yy < y + height; yy++) {
        for (var xx = x; xx < x + width; xx++) {
          final i = (yy * _w + xx) * 3;
          rgb[i] = color.$1;
          rgb[i + 1] = color.$2;
          rgb[i + 2] = color.$3;
        }
      }
    }

    final paper = Uint8List(_w * _h)..fillRange(0, _w * _h, 240);

    test('un sello rojo tenue queda rojo, incluso en el margen', () {
      final rgb = rgbOf(_paper());
      paint(rgb, 200, 5, 60, 20, (215, 95, 95));
      final out = cleanDocumentColor(rgb, lumOf(rgb), paper, _w, _h);
      final i = (15 * _w + 230) * 3;
      expect(out[i], greaterThan(out[i + 1] + 40), reason: 'sigue rojo');
    });

    test('la tinta negra queda negra y el papel, blanco', () {
      final rgb = rgbOf(_paper());
      paint(rgb, 100, 400, 60, 30, (30, 30, 30));
      final out = cleanDocumentColor(rgb, lumOf(rgb), paper, _w, _h);
      expect(out[(415 * _w + 130) * 3], lessThan(40));
      expect(out[(100 * _w + 100) * 3], 255);
    });

    test('las líneas azules claras del cuaderno no son tinta', () {
      final rgb = rgbOf(_paper());
      paint(rgb, 50, 300, 500, 2, (165, 195, 225));
      paint(rgb, 100, 400, 60, 30, (30, 30, 30));
      final out = cleanDocumentColor(rgb, lumOf(rgb), paper, _w, _h);
      expect(out[(301 * _w + 300) * 3], 255);
    });
  });

  group('nitidez', () {
    test('un borde marcado es más nítido que uno borroso', () {
      final sharp = _paper();
      _box(sharp, 100, 100, 200, 200, 30);
      final soft = _paper();
      for (var x = 0; x < 40; x++) {
        _box(soft, 100 + x, 100, 1, 200, 240 - x * 5);
      }
      _box(soft, 140, 100, 160, 200, 40);
      final paper = Uint8List(_w * _h)..fillRange(0, _w * _h, 240);
      expect(pageSharpness(sharp, paper, _w, _h), greaterThan(pageSharpness(soft, paper, _w, _h)));
    });

    test('una hoja vacía no se considera nítida', () {
      final paper = Uint8List(_w * _h)..fillRange(0, _w * _h, 240);
      expect(pageSharpness(_paper(), paper, _w, _h), 0);
    });
  });
}
