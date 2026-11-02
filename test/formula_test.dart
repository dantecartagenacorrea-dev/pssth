import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/math/formula.dart';
import 'package:lector_pdf/domain/math/rational.dart';

double calc(String s, {bool degrees = true, double ans = 0}) => parseFormula(s, degrees: degrees, ans: ans).at();

void main() {
  group('cuentas', () {
    test('respeta el orden de las operaciones', () {
      expect(calc('2 + 3 × 4'), 14);
      expect(calc('(2 + 3) × 4'), 20);
      expect(calc('-2^2'), -4);
      expect(calc('2^3^2'), 512);
      expect(calc('2^-1'), 0.5);
      expect(calc('10 ÷ 4'), 2.5);
      expect(calc('3,5 + 1,5'), 5);
    });

    test('entiende multiplicación implícita, constantes y Ans', () {
      expect(calc('2π'), closeTo(2 * math.pi, 1e-12));
      expect(calc('2(3+1)'), 8);
      expect(calc('(1+1)(2+1)'), 6);
      expect(calc('e'), closeTo(math.e, 1e-12));
      expect(calc('Ans × 2', ans: 21), 42);
      expect(calc('50%'), 0.5);
      expect(calc('5!'), 120);
    });

    test('un paréntesis abierto al final se cierra solo', () {
      expect(calc('2 × (3 + 1'), 8);
      expect(calc('sen(90'), 1);
    });

    test('funciones en grados dan valores exactos', () {
      expect(calc('sen(90)'), 1);
      expect(calc('cos(90)'), 0);
      expect(calc('sen(180)'), 0);
      expect(formatNumber(calc('sen(30)')), '0,5');
      expect(formatNumber(calc('tan(45)')), '1');
      expect(formatNumber(calc('arcsen(1)')), '90');
    });

    test('funciones en radianes', () {
      expect(calc('sen(π/2)', degrees: false), 1);
      expect(calc('cos(π)', degrees: false), -1);
    });

    test('logaritmos, raíces y valor absoluto', () {
      expect(formatNumber(calc('log(1000)')), '3');
      expect(calc('ln(e)'), 1);
      expect(calc('√16'), 4);
      expect(calc('√(9+16)'), 5);
      expect(calc('raíz de 25'), 5);
      expect(calc('abs(-3)'), 3);
    });

    test('lo que no existe no inventa un número', () {
      expect(calc('√(-1)'), isNaN);
      expect(calc('ln(-1)'), isNaN);
      expect(calc('tan(90)'), isNaN);
      expect(calc('1/0'), double.infinity);
      expect(calc('1,5!'), isNaN);
    });

    test('avisa lo que no entiende', () {
      expect(() => parseFormula(''), throwsA(isA<MathError>()));
      expect(() => parseFormula('2 +'), throwsA(isA<MathError>()));
      expect(() => parseFormula('z + 1'), throwsA(isA<MathError>()));
      expect(() => parseFormula('x = 3'), throwsA(isA<MathError>()));
      expect(() => parseFormula('sen x'), throwsA(isA<MathError>()));
      expect(() => parseFormula('(2) 3)'), throwsA(isA<MathError>()));
    });
  });

  group('formato', () {
    test('coma decimal, sin el ruido de los decimales', () {
      expect(formatNumber(calc('0,1 + 0,2')), '0,3');
      expect(formatNumber(1 / 3), '0,333333333333');
      expect(formatNumber(1000000), '1000000');
      expect(formatNumber(-2.5), '−2,5');
      expect(formatNumber(100), '100');
      expect(formatNumber(0.00001), '0,00001');
    });

    test('muy grande o muy chico, con potencia de 10', () {
      expect(formatNumber(1.5e20), '1,5 × 10^20');
      expect(formatNumber(2e-12), '2 × 10^-12');
      expect(formatNumber(double.nan), 'no existe');
      expect(formatNumber(double.infinity), 'infinito');
    });
  });

  group('fórmulas con x', () {
    test('quita el «y =» y evalúa', () {
      final f = parseFormula('y = 2x + 1');
      expect(f.usesX, isTrue);
      expect(f.at(3), 7);
      expect(parseFormula('f(x) = x²').at(3), 9);
      expect(parseFormula('xsen(x)').at(0), 0);
      expect(parseFormula('3').usesX, isFalse);
    });

    test('la curva se corta donde no existe', () {
      const w = (minX: -2.0, maxX: 2.0, minY: -5.0, maxY: 5.0);
      expect(plotSegments(parseFormula('√x').at, w), hasLength(1));
      expect(plotSegments(parseFormula('√x').at, w).single.first.$1, greaterThanOrEqualTo(0));
    });

    test('una asíntota no se une con una raya', () {
      const w = (minX: -2.0, maxX: 2.0, minY: -5.0, maxY: 5.0);
      expect(plotSegments(parseFormula('1/x').at, w, samples: 401), hasLength(2));
    });

    test('una recta empinada sí es un solo tramo', () {
      const w = (minX: -10.0, maxX: 10.0, minY: -5.0, maxY: 5.0);
      expect(plotSegments(parseFormula('2x').at, w), hasLength(1));
    });

    test('encuentra dónde corta el eje x', () {
      expect(formulaRoots(parseFormula('x - 2').at, -10, 10).single, closeTo(2, 1e-9));
      final roots = formulaRoots(parseFormula('x^2 - 4').at, -10, 10);
      expect(roots, hasLength(2));
      expect(roots[0], closeTo(-2, 1e-9));
      expect(roots[1], closeTo(2, 1e-9));
      expect(formulaRoots(parseFormula('sen(x)').at, -4, 4), hasLength(3));
    });

    test('también si toca el eje sin cruzarlo', () {
      expect(formulaRoots(parseFormula('x^2').at, -3.3, 7.1).single, closeTo(0, 1e-4));
    });

    test('un salto no es una raíz', () {
      expect(formulaRoots(parseFormula('1/x').at, -3, 3), isEmpty);
      expect(formulaRoots(parseFormula('x^2 + 1').at, -3, 3), isEmpty);
      expect(formulaRoots(parseFormula('0').at, -3, 3), isEmpty);
    });

    test('el ajuste de alto no se deja engañar por una asíntota', () {
      final fit = fitHeight([parseFormula('tan(x)').at], -1.5, 1.6);
      expect(fit.maxY, lessThan(1000));
      final flat = fitHeight([parseFormula('3').at], -1, 1);
      expect(flat.minY, lessThan(3));
      expect(flat.maxY, greaterThan(3));
    });
  });

  group('fracciones', () {
    test('las cuentas con fracciones dan exacto', () {
      expect(exactValue('1/2 + 1/3'), Rational.of(5, 6));
      expect(exactValue('3/4 × 2/3'), Rational.of(1, 2));
      expect(exactValue('(1/2) ÷ (1/4)'), Rational.of(2));
      expect(exactValue('(1/2)^2'), Rational.of(1, 4));
      expect(exactValue('0,5 + 1/4'), Rational.of(3, 4));
      expect(exactValue('√(9/16)'), Rational.of(3, 4));
      expect(exactValue('1/2 + (1/3'), Rational.of(5, 6));
    });

    test('Ans sigue exacto: un tercio por tres es uno', () {
      expect(exactValue('Ans × 3', ans: Rational.of(1, 3)), Rational.one);
      expect(exactValue('Ans + 1'), isNull);
    });

    test('lo que no es una fracción no se hace pasar por una', () {
      expect(exactValue('sen(30)'), isNull);
      expect(exactValue('π/2'), isNull);
      expect(exactValue('√2'), isNull);
      expect(exactValue('1/0'), isNull);
      expect(nearFraction(math.sqrt(2)), isNull);
      expect(nearFraction(math.pi), isNull);
      expect(nearFraction(math.e), isNull);
    });

    test('un decimal que es una fracción sencilla se reconoce', () {
      expect(nearFraction(0.49999999999999994), Rational.of(1, 2));
      expect(nearFraction(-0.75), Rational.of(-3, 4));
      expect(nearFraction(1 / 3), Rational.of(1, 3));
      expect(nearFraction(2.5), Rational.of(5, 2));
    });

    test('número mixto: se escribe y se separa', () {
      expect(exactValue('2 1/3'), Rational.of(7, 3));
      expect(exactValue('2 1/3 + 1 1/3'), Rational.of(11, 3));
      expect(exactValue('3 × 2 1/2'), Rational.of(15, 2));
      expect(parseFormula('2 1/2').at(), 2.5);
      expect(parseFormula('-2 1/2').at(), -2.5);
      expect(mixedParts(Rational.of(7, 2)), (BigInt.from(3), Rational.of(1, 2)));
      expect(mixedParts(Rational.of(-7, 2)), (BigInt.from(3), Rational.of(1, 2)));
      expect(mixedParts(Rational.of(1, 2)), isNull);
      expect(mixedParts(Rational.of(4)), isNull);
    });

    test('un número mixto a medias avisa, no da otro número', () {
      expect(() => parseFormula('2 1'), throwsA(isA<MathError>()));
    });

    test('también se grafica', () {
      expect(parseFormula('y = 1/2 x').at(4), 2);
      expect(parseFormula('y = x/3 + 1/2').at(3), 1.5);
    });
  });

  test('la describe en palabras', () {
    final said = describeFormula(parseFormula('y = 2x - 4'), -10, 10);
    expect(said, contains('2x menos 4'));
    expect(said, contains('Corta el eje y en menos 4'));
    expect(said, contains('Corta el eje x en 2'));
    expect(spokenFormula('sen(x)^2'), 'seno de x al cuadrado');
    expect(describeFormula(parseFormula('1/x'), -3, 3), contains('No corta el eje y'));
  });

  test('dos lecturas de la misma foto se comparan por su valor', () {
    expect(readingsDiffer('5/4 - 2/3', '5/6-2/3'), isTrue);
    expect(readingsDiffer('(2/3)×(3/5)', '2/3 × 3/5'), isFalse);
    expect(readingsDiffer('(1/2)÷(3/4)', '(1/2) ÷ (3/4)'), isFalse);
    expect(readingsDiffer('sen(30)', '1/2'), isFalse, reason: 'una no se puede calcular exacta');
  });
}
