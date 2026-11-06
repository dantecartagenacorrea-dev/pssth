import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/window_merge.dart';

void main() {
  group('audioWindows', () {
    test('el audio corto va en una sola ventana', () {
      expect(audioWindows(30, window: 40, overlap: 10), [(0, 30)]);
      expect(audioWindows(40, window: 40, overlap: 10), [(0, 40)]);
    });

    test('las ventanas se solapan y cubren todo el audio', () {
      expect(audioWindows(100, window: 40, overlap: 10), [(0, 40), (30, 70), (60, 100)]);
    });

    test('la última ventana termina en el final y conserva su largo', () {
      expect(audioWindows(96, window: 40, overlap: 10), [(0, 40), (30, 70), (56, 96)]);
    });

    test('sin audio no hay ventanas', () {
      expect(audioWindows(0, window: 40, overlap: 10), isEmpty);
    });
  });

  group('mergeWindows', () {
    test('una sola ventana devuelve su texto entero', () {
      final text = mergeWindows([
        const TimedWindow(start: 0, end: 40, tokens: [' La', ' ca', 'sa'], times: [1, 2, 3]),
      ]);
      expect(text, 'La casa');
    });

    test('lo que sale dos veces en el solape queda una sola vez', () {
      final text = mergeWindows([
        const TimedWindow(start: 0, end: 40, tokens: [' uno', ' dos', ' tres'], times: [10, 32, 38]),
        const TimedWindow(start: 30, end: 70, tokens: [' dos', ' tres', ' cuatro'], times: [2, 8, 20]),
      ]);
      expect(text, 'uno dos tres cuatro');
    });

    test('cada ventana manda en su mitad del solape', () {
      // Corte en el segundo 35: antes vale la primera ventana; después, la segunda.
      final text = mergeWindows([
        const TimedWindow(start: 0, end: 40, tokens: [' primera', ' mala'], times: [31, 38]),
        const TimedWindow(start: 30, end: 70, tokens: [' mala', ' segunda'], times: [1, 8]),
      ]);
      expect(text, 'primera segunda');
    });

    test('una palabra partida en piezas no se corta en el límite', () {
      final text = mergeWindows([
        const TimedWindow(start: 0, end: 40, tokens: [' galli', 'nas'], times: [34.9, 35.2]),
        const TimedWindow(start: 30, end: 70, tokens: [' galli', 'nas', ' gordas'], times: [4.9, 5.2, 6]),
      ]);
      expect(text, 'gallinas gordas');
    });

    test('una ventana que no escribió nada no borra a las demás', () {
      final text = mergeWindows([
        const TimedWindow(start: 0, end: 40, tokens: [' uno'], times: [5]),
        const TimedWindow(start: 30, end: 70, tokens: [], times: []),
        const TimedWindow(start: 60, end: 100, tokens: [' fin'], times: [20]),
      ]);
      expect(text, 'uno fin');
    });

    test('sin tiempos para cada pieza usa solo lo que tiene tiempo', () {
      final text = mergeWindows([
        const TimedWindow(start: 0, end: 40, tokens: [' uno', ' dos'], times: [5]),
      ]);
      expect(text, 'uno');
    });
  });
}
