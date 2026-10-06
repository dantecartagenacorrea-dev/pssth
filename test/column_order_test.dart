import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/column_order.dart';

TextBox _b(String t, double l, double top, double r) =>
    TextBox(text: t, left: l, top: top, right: r, bottom: top - 10);

void main() {
  _tituloCentradoTests();
  _charTests();
  test('dos columnas: izquierda completa y luego derecha', () {
    final boxes = <TextBox>[
      _b('TITULO A ANCHO COMPLETO', 100, 780, 500),
      for (var i = 0; i < 6; i++) _b('izq$i', 50, 700 - i * 20, 280),
      for (var i = 0; i < 6; i++) _b('der$i', 320, 700 - i * 20, 550),
    ];
    final out = reorderColumns(boxes, 600);
    expect(out, isNotNull);
    final lines = out!.split('\n');
    expect(lines.first, 'TITULO A ANCHO COMPLETO');
    expect(lines.sublist(1, 7), ['izq0', 'izq1', 'izq2', 'izq3', 'izq4', 'izq5']);
    expect(lines.sublist(7), ['der0', 'der1', 'der2', 'der3', 'der4', 'der5']);
  });

  test('una sola columna: no se reordena', () {
    final boxes = [for (var i = 0; i < 12; i++) _b('linea $i', 50, 700 - i * 20, 550)];
    expect(reorderColumns(boxes, 600), isNull);
  });

  test('columna derecha insignificante: no se reordena', () {
    final boxes = [
      for (var i = 0; i < 10; i++) _b('texto largo de la izquierda $i', 50, 700 - i * 20, 280),
      _b('x', 400, 700, 420),
    ];
    expect(reorderColumns(boxes, 600), isNull);
  });
}

void _charTests() {
  test('caracteres en la misma línea con hueco grande forman bloques distintos', () {
    // "ab   cd" en una línea: a,b a la izquierda; c,d lejos a la derecha.
    final text = 'ab cd\nef';
    CharRect c(double x, double y) => CharRect(x, y + 10, x + 6, y);
    final rects = [c(10, 100), c(16, 100), c(22, 100), c(300, 100), c(306, 100), const CharRect(0, 0, 0, 0), c(10, 80), c(16, 80)];
    final boxes = boxesFromChars(text, rects);
    expect(boxes.map((b) => b.text).toList(), ['ab', 'cd', 'ef']);
    expect(boxes[1].left, 300);
  });
}

void _tituloCentradoTests() {
  test('un título centrado que cruza el canal no impide detectar columnas', () {
    final boxes = <TextBox>[
      _b('TITULO CENTRADO', 150, 794, 445), // 50 % del ancho, cruza el canal
      for (var i = 0; i < 10; i++) _b('izq$i', 51, 740 - i * 15, 270),
      for (var i = 0; i < 10; i++) _b('der$i', 313, 740 - i * 15, 530),
    ];
    final out = reorderColumns(boxes, 595);
    expect(out, isNotNull);
    final lines = out!.split('\n');
    expect(lines.first, 'TITULO CENTRADO');
    expect(lines[1], 'izq0');
    expect(lines[10], 'izq9');
    expect(lines[11], 'der0');
  });
}
