import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lector_pdf/domain/retype_ink.dart';
import 'package:lector_pdf/domain/scanned_pdf.dart';

/// Una hoja de mentira donde se dibuja con rectángulos.
class _Sheet {
  _Sheet(this.w, this.h) : rgb = Uint8List(w * h * 3)..fillRange(0, w * h * 3, 240);
  final int w, h;
  final Uint8List rgb;

  void box(int x0, int y0, int x1, int y1, [List<int> color = const [10, 10, 10]]) {
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final j = (y * w + x) * 3;
        rgb.setRange(j, j + 3, color);
      }
    }
  }

  /// Una palabra de [letters] letras de 20 de alto y trazo [stroke].
  void word(int x, int y, int letters, int stroke) {
    for (var i = 0; i < letters; i++) {
      final left = x + i * 18;
      box(left, y, left + stroke, y + 20);
      box(left + 10, y, left + 10 + stroke, y + 20);
      box(left, y, left + 10 + stroke, y + stroke);
    }
  }

  PageInk read(List<ScannedLine> lines) {
    final lum = Uint8List(w * h);
    for (var i = 0; i < lum.length; i++) {
      lum[i] = rgb[i * 3 + 1];
    }
    return readPageInk(rgb, lum, Uint8List(w * h)..fillRange(0, w * h, 240), w, h, lines);
  }
}

void main() {
  const w = 1000, h = 1000;

  /// Renglones de 5 palabras normales; la tercera del renglón [boldLine] va gruesa.
  _Sheet sheet(int boldLine) {
    final s = _Sheet(w, h);
    for (var row = 0; row < 4; row++) {
      for (var word = 0; word < 5; word++) {
        s.word(100 + word * 150, 100 + row * 50, 5, row == boldLine && word == 2 ? 5 : 3);
      }
    }
    return s;
  }

  final lines = <ScannedLine>[
    for (var row = 0; row < 4; row++)
      (text: 'uno dos TRES cuatro cinco', left: 0.09, top: (95 + row * 50) / h, width: 0.8, height: 0.03),
  ];

  test('la palabra de trazo grueso es negrita y las demás no, aunque vayan en mayúsculas', () {
    final ink = sheet(1).read(lines);
    expect(ink.bold[1], [false, false, true, false, false]);
    expect(ink.bold[0], [false, false, false, false, false]);
    expect(ink.marks, isEmpty);
  });

  test('una palabrita gruesa sola no es negrita; junto a una negrita, sí', () {
    final s = _Sheet(w, h);
    for (var row = 0; row < 4; row++) {
      for (var word = 0; word < 5; word++) {
        s.word(100 + word * 150, 100 + row * 50, row == 1 && word == 0 ? 1 : 5, row == 2 && word == 3 ? 5 : 3);
      }
    }
    s.box(100, 150, 113, 170); // la palabrita, maciza
    final mixed = <ScannedLine>[
      for (var row = 0; row < 4; row++)
        (
          text: row == 1 ? 'el dos tres cuatro cinco' : 'uno dos tres cuatro cinco',
          left: 0.09,
          top: (95 + row * 50) / h,
          width: 0.8,
          height: 0.03,
        ),
    ];
    final ink = s.read(mixed);
    expect(ink.bold[1]!.first, isFalse);
    expect(ink.bold[2], [false, false, false, true, false]);
  });

  test('si no alcanzan los trazos para las palabras, ese renglón no se mide', () {
    final ink = sheet(1).read([...lines, (text: 'a b c d e f', left: 0.09, top: 0.6, width: 0.8, height: 0.03)]);
    expect(ink.bold.last, isNull);
  });

  test('una firma fuera del texto se recorta con su lugar y su color', () {
    final s = sheet(-1);
    for (var i = 0; i < 24; i++) {
      final dip = i.isEven ? 0 : 30;
      s.box(300 + i * 5, 600 + dip, 306 + i * 5, 660 + dip, const [20, 30, 160]);
    }
    final mark = s.read(lines).marks.single;
    expect(mark.left, closeTo(0.3, 0.01));
    expect(mark.top, closeTo(0.6, 0.01));
    final crop = img.decodeJpg(mark.jpeg)!;
    final ink = crop.getPixel(6, 20);
    expect(ink.b, greaterThan(ink.r), reason: 'conserva su color');
  });

  test('una letra suelta junto a la firma no va en el recorte', () {
    final s = sheet(-1);
    for (var i = 0; i < 24; i++) {
      final dip = i.isEven ? 0 : 30;
      s.box(300 + i * 5, 600 + dip, 306 + i * 5, 660 + dip);
    }
    s.box(280, 570, 290, 582);
    final mark = s.read(lines).marks.single;
    expect(mark.left, closeTo(0.3, 0.01), reason: 'la letra quedaba a la izquierda');
    expect(mark.top, closeTo(0.6, 0.01));
  });

  test('el recorte no se lleva el texto que queda dentro', () {
    final s = sheet(-1);
    // Un marco alto que abarca dos renglones de texto.
    s.box(200, 140, 800, 145);
    s.box(200, 140, 206, 260);
    s.box(794, 140, 800, 260);
    s.box(200, 255, 800, 260);
    final mark = s.read(lines).marks.single;
    final crop = img.decodeJpg(mark.jpeg)!;
    // Donde estaba la tercera palabra del renglón de 150.
    final word = crop.getPixel(400 - 197, 160 - 137);
    expect(word.r, greaterThan(230));
  });

  test('texto que el lector no ubicó no pasa como firma', () {
    final s = sheet(-1);
    for (var row = 0; row < 3; row++) {
      for (var word = 0; word < 5; word++) {
        s.word(100 + word * 150, 500 + row * 50, 5, 3);
      }
    }
    expect(s.read(lines).marks, isEmpty);
  });

  test('una hoja llena de manchas no se cuelga', () {
    final s = sheet(-1);
    for (var y = 400; y < 990; y += 6) {
      for (var x = 10; x < 990; x += 6) {
        s.box(x, y, x + 3, y + 3);
      }
    }
    final clock = Stopwatch()..start();
    final ink = s.read(lines);
    expect(clock.elapsed.inSeconds, lessThan(10));
    expect(ink.bold, hasLength(lines.length));
  });

  test('la cuadrícula de una tabla no se lleva su texto ni pasa como firma', () {
    final s = sheet(-1);
    s.box(50, 80, 950, 84);
    s.box(50, 300, 950, 304);
    s.box(50, 80, 54, 304);
    s.box(946, 80, 950, 304);
    final ink = s.read(lines);
    expect(ink.stamps, isEmpty);
    expect(ink.marks, isEmpty);
  });

  test('una sombra clara de arruga no es una firma', () {
    final s = sheet(-1);
    s.box(100, 600, 700, 660, const [130, 130, 130]);
    expect(s.read(lines).marks, isEmpty);
  });

  test('lo que toca el borde de la foto es el fondo', () {
    final s = sheet(-1);
    s.box(0, 500, 300, 700);
    expect(s.read(lines).marks, isEmpty);
  });

  test('una raya suelta no es una firma', () {
    final s = sheet(-1);
    s.box(100, 700, 800, 704);
    expect(s.read(lines).marks, isEmpty);
  });

  test('sin texto no se mide nada: la página va con su foto', () {
    expect(sheet(-1).read(const []).marks, isEmpty);
  });

  group('sellos', () {
    void ring(_Sheet s) {
      const red = [200, 40, 40];
      s.box(600, 500, 800, 506, red);
      s.box(600, 694, 800, 700, red);
      s.box(600, 500, 606, 700, red);
      s.box(794, 500, 800, 700, red);
    }

    test('el renglón dentro de un sello va con el sello y no con el texto', () {
      final s = sheet(-1);
      ring(s);
      s.box(660, 590, 666, 610, const [200, 40, 40]);
      s.box(680, 590, 686, 610, const [200, 40, 40]);
      final ink = s.read([...lines, (text: 'NOTARIA', left: 0.64, top: 0.585, width: 0.1, height: 0.03)]);
      expect(ink.stamps, {4});
      expect(ink.marks, hasLength(1));
      final crop = img.decodeJpg(ink.marks.single.jpeg)!;
      final letter = crop.getPixel(663 - 597, 600 - 497);
      expect(letter.r, greaterThan(letter.g + 40), reason: 'la letra quedó en el recorte');
    });

    test('lo escrito dentro de un sello negro también va con el sello', () {
      final s = sheet(-1);
      s.box(600, 500, 800, 506);
      s.box(600, 694, 800, 700);
      s.box(600, 500, 606, 700);
      s.box(794, 500, 800, 700);
      s.box(660, 590, 666, 610);
      s.box(680, 590, 686, 610);
      final ink = s.read([...lines, (text: 'NOTARIA', left: 0.64, top: 0.585, width: 0.1, height: 0.03)]);
      expect(ink.stamps, {4});
      final crop = img.decodeJpg(ink.marks.single.jpeg)!;
      expect(crop.getPixel(663 - 597, 600 - 497).r, lessThan(100));
    });

    test('un renglón que una firma abierta tiene encima sigue siendo texto', () {
      final s = sheet(-1);
      s.box(600, 500, 800, 506);
      s.box(600, 500, 606, 700);
      s.box(660, 590, 666, 610);
      s.box(680, 590, 686, 610);
      final ink = s.read([...lines, (text: 'Juan', left: 0.64, top: 0.585, width: 0.1, height: 0.03)]);
      expect(ink.stamps, isEmpty);
    });

    test('un sello claro también es tinta', () {
      final s = sheet(-1);
      const pale = [235, 130, 130];
      s.box(600, 500, 800, 506, pale);
      s.box(600, 694, 800, 700, pale);
      s.box(600, 500, 606, 700, pale);
      s.box(794, 500, 800, 700, pale);
      s.box(660, 590, 666, 610, pale);
      s.box(680, 590, 686, 610, pale);
      final ink = s.read([...lines, (text: 'NOTARIA', left: 0.64, top: 0.585, width: 0.1, height: 0.03)]);
      expect(ink.stamps, {4});
    });

    test('un renglón de color suelto es texto: no se pierde', () {
      final s = sheet(-1);
      s.word(100, 500, 5, 3);
      for (var i = 0; i < 90; i++) {
        s.box(100, 500, 190, 520, const [200, 40, 40]);
      }
      final ink = s.read([...lines, (text: 'Aviso', left: 0.09, top: 0.495, width: 0.3, height: 0.03)]);
      expect(ink.stamps, isEmpty);
    });

    test('una hoja escrita en azul no se toma por sello', () {
      final s = _Sheet(w, h);
      for (var row = 0; row < 4; row++) {
        for (var word = 0; word < 5; word++) {
          for (var i = 0; i < 5; i++) {
            s.box(100 + word * 150 + i * 18, 100 + row * 50, 110 + word * 150 + i * 18, 120 + row * 50, const [
              20,
              30,
              160,
            ]);
          }
        }
      }
      final ink = s.read(lines);
      expect(ink.stamps, isEmpty);
      expect(ink.bold.first, isNotNull);
    });
  });

  group('al corregir', () {
    test('misma cantidad de palabras: por lugar', () {
      expect(boldAfterEdit('ROBO de auto', 'R0BO de auto', [true, false, false]), [true, false, false]);
    });

    test('otra cantidad: por texto', () {
      expect(boldAfterEdit('ROBO de auto', 'ROBO de un auto', [true, false, false]), [true, false, false, false]);
    });

    test('sin medida sigue sin medida', () {
      expect(boldAfterEdit('uno', 'uno dos', null), isNull);
    });
  });
}
