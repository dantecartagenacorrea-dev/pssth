import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/math/solver.dart';
import 'package:lector_pdf/domain/math/stacked_math.dart';
import 'package:lector_pdf/domain/scanned_pdf.dart';

ScannedLine _at(String text, double left, double top, {double? width}) =>
    (text: text, left: left, top: top, width: width ?? 0.05 * text.length, height: 0.1);

void main() {
  test('arma fracciones leídas como renglones sueltos', () {
    final text = stackedMath([
      _at('3', 0.2, 0.2),
      _at('1', 0.4, 0.2),
      _at('+', 0.3, 0.35),
      _at('=', 0.5, 0.35),
      _at('4', 0.2, 0.5),
      _at('2', 0.4, 0.5),
    ]);
    expect(text, '3/4 + 1/2 =');
    expect(solveMath(mathLinesIn(text!).single).answer, '5/4 = 1,25');
  });

  test('también si el lector junta los números en un renglón', () {
    expect(
      stackedMath([_at('3 1', 0.2, 0.2, width: 0.3), _at('+', 0.33, 0.35), _at('4 2', 0.2, 0.5, width: 0.3)]),
      '3/4 + 1/2',
    );
  });

  test('una sola fracción, y la raya leída como guion no es una resta', () {
    expect(stackedMath([_at('3', 0.2, 0.2), _at('4', 0.2, 0.5)]), '3/4');
    expect(stackedMath([_at('3', 0.2, 0.2), _at('—', 0.2, 0.35), _at('4', 0.2, 0.5)]), '3/4');
  });

  test('un entero con una fracción', () {
    expect(stackedMath([_at('1', 0.5, 0.2), _at('2', 0.2, 0.35), _at('+', 0.35, 0.35), _at('4', 0.5, 0.5)]), '2 + 1/4');
  });

  test('una división de fracciones va con paréntesis', () {
    final text = stackedMath([
      _at('1', 0.2, 0.2),
      _at('3', 0.4, 0.2),
      _at('÷', 0.3, 0.35),
      _at('2', 0.2, 0.5),
      _at('4', 0.4, 0.5),
    ]);
    expect(text, '(1/2) ÷ (3/4)');
    expect(solveMath(text!).answer, '2/3 = 0,6667');
  });

  test('lo que no es una fracción apilada no se inventa', () {
    expect(stackedMath([_at('Capítulo', 0.2, 0.2), _at('3', 0.2, 0.5)]), isNull);
    expect(stackedMath([_at('2x + 3 = 11', 0.2, 0.2)]), isNull);
    expect(stackedMath([_at('3', 0.2, 0.2), _at('4', 0.2, 0.4), _at('5', 0.2, 0.6), _at('6', 0.2, 0.8)]), isNull);
    expect(stackedMath([_at('3', 0.2, 0.2), _at('1', 0.4, 0.2), _at('4', 0.2, 0.5)]), isNull);
    expect(stackedMath(const []), isNull);
  });

  group('fracciones leídas por su raya', () {
    const a = (text: '3/4', left: 0.1, right: 0.2, top: 0.2, bottom: 0.6);
    const b = (text: '1/2', left: 0.4, right: 0.5, top: 0.2, bottom: 0.6);

    test('junta las fracciones con el signo que hay entre ellas', () {
      expect(assembleFractions([a, b], [_at('+', 0.3, 0.35), _at('=', 0.55, 0.35)]), '3/4 + 1/2 =');
    });

    test('lo que se lee dentro de la fracción no cuenta', () {
      expect(assembleFractions([a], [_at('—', 0.14, 0.35)]), '3/4');
    });

    test('sin signo entre dos fracciones no adivina', () {
      expect(assembleFractions([a, b], const []), isNull);
    });

    test('lo que está en otro renglón no se mezcla', () {
      expect(assembleFractions([a], [_at('5', 0.3, 0.8), _at('+', 0.5, 0.05)]), '3/4');
    });

    test('un entero con una fracción', () {
      expect(assembleFractions([b], [_at('2', 0.1, 0.35), _at('+', 0.25, 0.35)]), '2 + 1/2');
    });

    test('un producto de fracciones lleva paréntesis', () {
      expect(assembleFractions([a, b], [_at('×', 0.3, 0.35)]), '(3/4) × (1/2)');
    });

    test('una división de fracciones lleva paréntesis', () {
      expect(assembleFractions([a, b], [_at('÷', 0.3, 0.35)]), '(3/4) ÷ (1/2)');
    });
  });
}
