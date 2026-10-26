import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/reading_window.dart';

void main() {
  test('muestra fragmentos antes y después del actual', () {
    expect(readingWindow(total: 100, index: 50), (48, 56));
  });

  test('al principio no se sale del documento y aprovecha el espacio', () {
    expect(readingWindow(total: 100, index: 0), (0, 8));
    expect(readingWindow(total: 100, index: 1), (0, 8));
  });

  test('al final tampoco', () {
    expect(readingWindow(total: 100, index: 99), (92, 100));
  });

  test('documento corto: se ve entero', () {
    expect(readingWindow(total: 3, index: 1), (0, 3));
  });

  test('sin fragmentos: ventana vacía', () {
    expect(readingWindow(total: 0, index: 0), (0, 0));
  });
}
