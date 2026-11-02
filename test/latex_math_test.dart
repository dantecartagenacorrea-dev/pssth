import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/math/formula.dart';
import 'package:lector_pdf/domain/math/latex_math.dart';
import 'package:lector_pdf/domain/math/solver.dart';

void main() {
  group('lo que entregó el modelo en las pruebas', () {
    const cases = {
      r'2 x + 3 = 1 1': '2x+3=11',
      r'\frac { 3 } { 4 } + \frac { 1 } { 2 }': '3/4+1/2',
      r'\frac { 5 } { 6 } - \frac { 1 } { 3 }': '5/6-1/3',
      r'y = x ^ { 2 } - 3 x + 2': 'y=x^2-3x+2',
      r'\frac { 2 } { 3 } ~ \ast ~ \frac { 3 } { 5 }': '(2/3)×(3/5)',
      r'\frac { 1 } { 2 } ~ \div ~ \frac { 3 } { 4 }': '(1/2)÷(3/4)',
      r'\frac { 7 } { 8 }': '7/8',
      r'\mathbf { x } ^ { 2 } - 5 \mathbf { x } + \mathbf { 6 } = 0': 'x^2-5x+6=0',
      r'\operatorname { s e n } ( 3 0 ) + 1 =': 'sen(30)+1=',
      r'\frac { 1 2 } { 2 5 } \: + \: \frac { 3 7 } { 5 0 }': '12/25+37/50',
      r'\frac { \; 1 2 \; } { 2 5 } \; + \; \frac { \; 3 7 \; } { 5 0 }': '12/25+37/50',
      r'\sqrt { 1 6 } + 2 ^ { 3 } =': '√(16)+2^3=',
      r'\begin{array} { c } { 2 } \\ \hline { 3 } \\ \end{array} \div \begin{array} { c } { 4 } \\ \hline { 5 } \\ \end{array}':
          '(2/3)÷(4/5)',
    };
    cases.forEach((latex, plain) {
      test(latex, () => expect(latexToPlain(latex), plain));
    });
  });

  group('otras formas', () {
    test('número mixto', () {
      expect(latexToPlain(r'2 \frac { 1 } { 2 }'), '(2+1/2)');
      expect(latexToPlain(r'3 + 2 \frac { 1 } { 2 }'), '3+(2+1/2)');
    });

    test('fracciones con cuentas adentro', () {
      expect(latexToPlain(r'\frac { x + 1 } { 2 }'), '((x+1)/2)');
      expect(latexToPlain(r'\frac { \frac { 1 } { 2 } } { 3 }'), '((1/2)/3)');
    });

    test('funciones con y sin paréntesis', () {
      expect(latexToPlain(r'\sin ( 3 0 )'), 'sen(30)');
      expect(latexToPlain(r'\sin { x }'), 'sen(x)');
      expect(latexToPlain(r'\sin x'), 'sen(x)');
      expect(latexToPlain(r'\log { 1 0 0 }'), 'log(100)');
      expect(latexToPlain(r'y = \cos ( x )'), 'y=cos(x)');
    });

    test('paréntesis, porcentaje y π', () {
      expect(latexToPlain(r'\left( 3 + 4 \right) \times 2'), '(3+4)×2');
      expect(latexToPlain(r'1 5 \% + 2'), '15%+2');
      expect(latexToPlain(r'2 \pi'), '2π');
    });

    test('potencia con cuenta adentro', () {
      expect(latexToPlain(r'2 ^ { x + 1 }'), '2^(x+1)');
    });
  });

  group('lo que no sabe hacer, no lo inventa', () {
    for (final latex in [
      r'x _ { 1 } + 2',
      r'\sqrt [ 3 ] { 8 }',
      r'\int x',
      r'\begin{array} { c } { 3 } \\ { 4 } \\ \end{array}',
      r'\begin{cases} x \\ y \end{cases}',
      r'\frac { 1 }',
      r'{ 3',
      '',
      '   ',
    ]) {
      test('«$latex»', () => expect(latexToPlain(latex), isNull));
    }
  });

  group('el resultado lo resuelve la app', () {
    test('cuentas', () {
      String solve(String latex) => solveMath(mathLinesIn(latexToPlain(latex)!).single).answer;
      expect(solve(r'\frac { 3 } { 4 } + \frac { 1 } { 2 }'), '5/4 = 1,25');
      expect(solve(r'\frac { 2 } { 3 } ~ \ast ~ \frac { 3 } { 5 }'), '2/5 = 0,4');
      expect(solve(r'\frac { 1 } { 2 } ~ \div ~ \frac { 3 } { 4 }'), '2/3 = 0,6667');
      expect(solve(r'\sqrt { 1 6 } + 2 ^ { 3 } ='), '12');
      expect(solve(r'2 \frac { 1 } { 2 } + 1'), '7/2 = 3,5');
    });

    test('una fórmula para graficar', () {
      final line = formulaLinesIn(latexToPlain(r'y = x ^ { 2 } - 3 x + 2')!).single;
      expect(parseFormula(line).at(1), 0);
    });
  });

  group('un número solo', () {
    test('sale sin adornos y corrige letras', () {
      expect(numberFromLatex(r'\mathbf { 2 5 }'), '25');
      expect(numberFromLatex(r'\overline { { 4 } }'), '4');
      expect(numberFromLatex(r'^ { \bf 1 }'), '1');
      expect(numberFromLatex(r'\bf { S O }'), '50');
    });

    test('lo que no es un número no pasa', () {
      expect(numberFromLatex(r'x + 1'), isNull);
      expect(numberFromLatex(''), isNull);
    });
  });

  group('vocabulario', () {
    test('los números vuelven a ser texto', () {
      final vocab = vocabularyFrom({
        '<pad>': 0,
        '<s>': 1,
        '</s>': 2,
        '<unk>': 3,
        '<mask>': 4,
        r'\frac': 5,
        'Ġ{': 6,
        'Ġ3': 7,
        'Ġ}': 8,
      });
      expect(decodeFormulaTokens([1, 5, 6, 7, 8, 2], vocab), r'\frac { 3 }');
    });
  });
}
