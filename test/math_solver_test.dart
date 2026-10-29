import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/math/expr.dart';
import 'package:lector_pdf/domain/math/rational.dart';
import 'package:lector_pdf/domain/math/solver.dart';

void main() {
  group('cuentas', () {
    test('respeta el orden de las operaciones', () {
      final s = solveMath('2 + 3 × 4');
      expect(s.answer, '14');
      expect(s.steps[1].note, 'Multiplicamos:');
      expect(s.steps[1].math, '2 + 12');
    });

    test('fracciones exactas con decimal al final', () {
      expect(solveMath('1/2 + 1/3').answer, '5/6 = 0,8333');
      expect(solveMath('(3/4) ÷ (1/2)').answer, '3/2 = 1,5');
    });

    test('potencias, raíces y porcentajes', () {
      expect(solveMath('2³ + √16').answer, '12');
      expect(solveMath('15% de 80').answer, '12');
      expect(solveMath('√2').answer, '1,4142');
      expect(solveMath('-2^2').answer, '-4');
    });

    test('decimales con coma y x como multiplicación', () {
      expect(solveMath('2,5 + 0,5').answer, '3');
      expect(solveMath('3x4').answer, '12');
    });

    test('errores claros', () {
      expect(() => solveMath('5 ÷ 0'), throwsA(isA<MathError>()));
      expect(() => solveMath('√-4'), throwsA(isA<MathError>()));
      expect(() => solveMath('2 + a'), throwsA(isA<MathError>()));
      expect(() => solveMath('(2 + 3'), throwsA(isA<MathError>()));
    });
  });

  group('ecuaciones de primer grado', () {
    test('despeja x y comprueba', () {
      final s = solveMath('2x + 3 = 11');
      expect(s.answer, 'x = 4');
      expect(s.steps.last.math, '11');
    });

    test('con paréntesis y x a ambos lados', () {
      expect(solveMath('3(x - 2) = x + 4').answer, 'x = 5');
      expect(solveMath('x/2 + 1 = 4').answer, 'x = 6');
    });

    test('resultado fraccionario', () {
      expect(solveMath('3x = 2').answer, 'x = 2/3 ≈ 0,6667');
    });

    test('sin solución o infinitas', () {
      expect(solveMath('x + 1 = x + 2').answer, contains('No tiene solución'));
      expect(solveMath('2(x + 1) = 2x + 2').answer, contains('infinitas'));
    });

    test('regla de tres: multiplica en cruz', () {
      final s = solveMath('3/5 = 12/x');
      expect(s.answer, 'x = 20');
      expect(s.steps[1].note, contains('en cruz'));
    });
  });

  group('ecuaciones de segundo grado', () {
    test('raíces exactas', () {
      expect(solveMath('x² - 5x + 6 = 0').answer, 'x₁ = 3,  x₂ = 2');
    });

    test('incompletas', () {
      expect(solveMath('x^2 = 9').answer, 'x = ±3');
      expect(solveMath('x² - 4x = 0').answer, 'x₁ = 0,  x₂ = 4');
    });

    test('raíz no exacta se simplifica', () {
      final s = solveMath('x² - 2x - 1 = 0');
      expect(s.answer, startsWith('x = (2 ± 2√2) ÷ 2'));
      expect(s.answer, contains('x₁ ≈ 2,4142'));
    });

    test('sin solución real y doble', () {
      expect(solveMath('x² + 1 = 0').answer, contains('No tiene solución real'));
      expect(solveMath('x² + 2x + 1 = 0').answer, contains('x = -1'));
    });

    test('gráfico de la parábola con raíces y vértice', () {
      final g = solveMath('x² - 5x + 6 = 0').graph!;
      final labels = g.points.map((p) => p.label).toList();
      expect(labels, contains('vértice'));
      expect(g.points.where((p) => p.y == 0).map((p) => p.x).toSet(), {2.0, 3.0});
      expect(g.curves.single.at(2), closeTo(0, 1e-9));
    });

    test('grado mayor queda fuera', () {
      expect(() => solveMath('x³ = 8'), throwsA(isA<MathError>()));
    });
  });

  group('sistemas', () {
    test('por reducción', () {
      expect(solveMath('x + y = 5\n x - y = 1').answer, 'x = 3;  y = 2');
      expect(solveMath('2x + 3y = 12; 3x - y = 7').answer, 'x = 3;  y = 2');
    });

    test('una ecuación sin x', () {
      expect(solveMath('2y = 4; x + y = 5').answer, 'x = 3;  y = 2');
    });

    test('los cuatro métodos dan lo mismo, cada uno con sus pasos', () {
      for (final m in SystemMethod.values) {
        final s = solveMath('2x + 3y = 12; 3x - y = 7', method: m);
        expect(s.answer, 'x = 3;  y = 2', reason: m.name);
        expect(s.kind, contains(m.label));
        expect(s.isSystem, isTrue);
      }
      expect(solveMath('x + y = 5; x - y = 1', method: SystemMethod.cramer).steps.map((s) => s.math).join(), contains('Δx'));
      expect(solveMath('x + y = 5; x - y = 1', method: SystemMethod.igualacion).steps[2].note, contains('igualamos'));
      expect(solveMath('x + y = 5; x - y = 1', method: SystemMethod.sustitucion).steps[1].note, contains('Despejamos x'));
    });

    test('gráfico: el cruce de las rectas', () {
      final g = solveMath('x + y = 5; x - y = 1').graph!;
      expect(g.curves, hasLength(2));
      expect((g.points.single.x, g.points.single.y), (3.0, 2.0));
    });

    test('paralelas e iguales', () {
      expect(solveMath('x + y = 1; 2x + 2y = 5').answer, contains('paralelas'));
      expect(solveMath('x + y = 1; 2x + 2y = 2').answer, contains('infinitas'));
    });
  });

  test('voz: pasa los símbolos a palabras', () {
    final spoken = solveMath('x² = 9').spoken().join(' ');
    expect(spoken, contains('al cuadrado'));
    expect(spoken, contains('más o menos'));
  });

  test('de una foto se queda solo con las líneas de matemáticas', () {
    expect(mathLinesIn('9el niño psst psst de que pais es X\nQgrupomatematico/video/7331802909002239237'), isEmpty);
    expect(mathLinesIn('Ejercicio 3: resuelve\n2x + 3 = 11\nPágina 45'), ['2x + 3 = 11']);
    expect(mathLinesIn('Calcula:\n3 × 4 + 2'), ['3 × 4 + 2']);
  });

  test('normalizeMath entiende lo que lee una foto', () {
    expect(normalizeMath('2 × 3 − 4 ÷ 2'), '2*3-4/2');
    expect(normalizeMath('raíz de 9'), '√9');
    expect(normalizeMath('X² = 4'), 'x^2=4');
  });

  test('Rational simplifica y simplifySqrt extrae cuadrados', () {
    expect(Rational.of(6, -8).toString(), '-3/4');
    expect(Rational.parse('0,125').toString(), '1/8');
    expect(simplifySqrt(BigInt.from(72)), (BigInt.from(6), BigInt.from(2)));
  });
}
