import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/math/solver.dart';

void main() {
  test('fracciones apiladas y respuestas en notación matemática', () {
    expect(solveMath('3/5 = 12/x').problemLatex, contains(r'\frac{3}{5}'));
    expect(solveMath('1/2 + 1/3').answerLatex, r'\frac{5}{6} = 0{,}8333');
    expect(solveMath('x + y = 5; x - y = 1').answerLatex, r'(x,\ y) = \left(3,\ 2\right)');
    expect(solveMath('x + y = 5; x - y = 1').problemLatex, startsWith(r'\begin{cases}'));
    expect(solveMath('x² + 1 = 0').answerLatex, isNull); // es una frase
  });

  testWidgets('todo lo que genera el solucionador se puede dibujar', (tester) async {
    const ejercicios = [
      '2 + 3 × 4',
      '1/2 + 1/3',
      '2³ + √16',
      '15% de 80',
      '√2',
      '2x + 3 = 11',
      '3(x - 2) = x + 4',
      '3/5 = 12/x',
      'x² - 5x + 6 = 0',
      'x² - 2x - 1 = 0',
      'x^2 = 9',
      'x² - 4x = 0',
      'x + y = 5\nx - y = 1',
      '2y = 4; x + y = 5',
    ];
    final errors = <String>[];
    final soluciones = [
      for (final e in ejercicios) (e, solveMath(e)),
      for (final m in SystemMethod.values) ('2x + 3y = 12; 3x - y = 7 (${m.short})', solveMath('2x + 3y = 12; 3x - y = 7', method: m)),
    ];
    for (final (e, s) in soluciones) {
      final all = [for (final st in s.steps) st.latex, ?s.answerLatex];
      for (final tex in all) {
        await tester.pumpWidget(MaterialApp(
          home: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(tex, onErrorFallback: (err) {
              errors.add('$e → $tex → ${err.message}');
              return const SizedBox();
            }),
          ),
        ));
      }
    }
    expect(errors, isEmpty);
  });
}
