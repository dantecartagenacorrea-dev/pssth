import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/math/fraction_bars.dart';

class _Sheet {
  _Sheet(this.w, this.h) : dark = Uint8List(w * h);
  final int w, h;
  final Uint8List dark;

  void box(int x, int y, int width, int height) {
    for (var yy = y; yy < y + height; yy++) {
      for (var xx = x; xx < x + width; xx++) {
        dark[yy * w + xx] = 1;
      }
    }
  }

  /// Una cifra de mentira: un bloque.
  void digit(int x, int y) => box(x, y, 24, 40);

  void fraction(int x) {
    digit(x + 10, 40);
    box(x, 90, 44, 5);
    digit(x + 10, 105);
  }

  List<FractionBar> get bars => findFractionBars(dark, w, h);
}

void main() {
  group('rayas de fracción', () {
    test('encuentra una fracción con su número de arriba y de abajo', () {
      final s = _Sheet(400, 200)..fraction(100);
      final bar = s.bars.single;
      expect(bar.numerator, (left: 110, top: 40, right: 134, bottom: 80));
      expect(bar.denominator, (left: 110, top: 105, right: 134, bottom: 145));
    });

    test('varias, de izquierda a derecha', () {
      final s = _Sheet(500, 200)
        ..fraction(300)
        ..fraction(100);
      expect(s.bars.map((b) => b.left), [100, 300]);
    });

    test('un signo menos o un igual no es una fracción', () {
      final minus = _Sheet(400, 200)..box(100, 90, 44, 5);
      expect(minus.bars, isEmpty);
      final equals = _Sheet(400, 200)
        ..box(100, 80, 44, 5)
        ..box(100, 100, 44, 5);
      expect(equals.bars, isEmpty);
    });

    test('un «÷» no es una fracción', () {
      final s = _Sheet(400, 200)
        ..box(100, 90, 44, 5)
        ..box(118, 78, 7, 7)
        ..box(118, 100, 7, 7);
      expect(s.bars, isEmpty);
    });

    test('el trazo de arriba de una letra no es una raya', () {
      final s = _Sheet(400, 200)
        ..box(100, 40, 44, 5)
        ..box(110, 45, 24, 40);
      expect(s.bars, isEmpty);
    });

    test('un más no es una fracción', () {
      final s = _Sheet(400, 200)
        ..box(100, 90, 44, 5)
        ..box(119, 72, 6, 41);
      expect(s.bars, isEmpty);
    });

    test('a mano los números rozan la raya, y sigue siendo fracción', () {
      final s = _Sheet(400, 200)
        ..digit(120, 50)
        ..box(100, 90, 64, 5)
        ..digit(120, 95);
      expect(s.bars, hasLength(1));
    });

    test('torcida, también', () {
      final s = _Sheet(400, 200)
        ..digit(120, 40)
        ..digit(120, 105);
      for (var i = 0; i < 64; i++) {
        s.box(100 + i, 88 + i ~/ 16, 1, 6);
      }
      expect(s.bars, hasLength(1));
    });

    test('una raya entre renglones de texto no es una fracción', () {
      final s = _Sheet(600, 200)
        ..box(20, 40, 500, 40)
        ..box(100, 90, 44, 5)
        ..box(20, 105, 500, 40);
      expect(s.bars, isEmpty);
    });

    test('una imagen vacía no tiene nada', () {
      expect(_Sheet(100, 100).bars, isEmpty);
    });
  });

  group('signos por su forma', () {
    const area = (left: 0, top: 0, right: 100, bottom: 100);

    test('menos, igual y más', () {
      expect(classifyOperator((_Sheet(100, 100)..box(30, 48, 40, 5)).dark, 100, area), '-');
      final equals = _Sheet(100, 100)
        ..box(30, 40, 40, 5)
        ..box(30, 55, 40, 5);
      expect(classifyOperator(equals.dark, 100, area), '=');
      final plus = _Sheet(100, 100)
        ..box(30, 48, 40, 5)
        ..box(48, 30, 5, 40);
      expect(classifyOperator(plus.dark, 100, area), '+');
    });

    test('dividir: la raya con sus dos puntos', () {
      final s = _Sheet(100, 100)
        ..box(30, 48, 40, 5)
        ..box(47, 36, 6, 6)
        ..box(47, 59, 6, 6);
      expect(classifyOperator(s.dark, 100, area), '÷');
    });

    test('por: dos diagonales', () {
      final s = _Sheet(100, 100);
      for (var i = 0; i < 40; i++) {
        s.box(30 + i, 30 + i, 4, 4);
        s.box(66 - i, 30 + i, 4, 4);
      }
      expect(classifyOperator(s.dark, 100, area), '×');
    });

    test('una cifra o nada no es un signo', () {
      expect(classifyOperator(_Sheet(100, 100).dark, 100, area), isNull);
      expect(classifyOperator((_Sheet(100, 100)..box(30, 30, 24, 40)).dark, 100, area), isNull);
    });
  });

  group('un número leído tres veces', () {
    test('coinciden', () {
      expect(digitsFromRepeat('3 3 3'), '3');
      expect(digitsFromRepeat('12 12 12\n'), '12');
    });

    test('los espacios no cuentan', () {
      expect(digitsFromRepeat('333'), '3');
      expect(digitsFromRepeat('3 33'), '3');
      expect(digitsFromRepeat('121212'), '12');
      expect(digitsFromRepeat('12 1212'), '12');
    });

    test('corrige letras confundidas con cifras', () {
      expect(digitsFromRepeat('l l l'), '1');
      expect(digitsFromRepeat('O O O'), '0');
      expect(digitsFromRepeat('S S 5'), '5');
    });

    test('si no coinciden, no adivina', () {
      expect(digitsFromRepeat('3 8 3'), isNull);
      expect(digitsFromRepeat('3 3'), isNull);
      expect(digitsFromRepeat('a a a'), isNull);
      expect(digitsFromRepeat(''), isNull);
      expect(digitsFromRepeat('3 3 33'), isNull);
      expect(digitsFromRepeat('121213'), isNull);
    });
  });
}
