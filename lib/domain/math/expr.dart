import 'dart:math' as math;

import 'rational.dart';

/// Expresión matemática del colegio: números exactos, x e y, + − × ÷,
/// potencias, raíz cuadrada y porcentaje.
sealed class Expr {
  const Expr();
}

/// Número exacto.
class Num extends Expr {
  const Num(this.value);
  final Rational value;
}

/// Número aproximado (una raíz que no es exacta).
class Approx extends Expr {
  const Approx(this.value);
  final double value;
}

class Var extends Expr {
  const Var(this.name);
  final String name;
}

class Neg extends Expr {
  const Neg(this.child);
  final Expr child;
}

/// [op] es uno de + - * / ^.
class Bin extends Expr {
  const Bin(this.op, this.left, this.right);
  final String op;
  final Expr left;
  final Expr right;
}

class Sqrt extends Expr {
  const Sqrt(this.child);
  final Expr child;
}

class Pct extends Expr {
  const Pct(this.child);
  final Expr child;
}

bool isNumber(Expr e) => e is Num || e is Approx;

/// Deja el texto (escrito o leído de una foto) en la forma que entiende el
/// lector: × · ÷ − ² ³ √ "raíz" "15% de 80"… Si no hay "=", una x entre
/// números es una multiplicación (2x3).
String normalizeMath(String raw) {
  var s = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[×·∙•✕]'), '*')
      .replaceAll(RegExp(r'[÷:]'), '/')
      .replaceAll(RegExp(r'[−–—]'), '-')
      .replaceAll(RegExp(r'[\[{]'), '(')
      .replaceAll(RegExp(r'[\]}]'), ')')
      .replaceAll('²', '^2')
      .replaceAll('³', '^3')
      .replaceAll(RegExp(r'ra[ií]z(\s*cuadrada)?(\s*de)?|sqrt'), '√')
      .replaceAll(RegExp(r'%\s*de\s*'), '%*');
  if (!s.contains('=')) s = s.replaceAllMapped(RegExp(r'(\d)\s*x\s*(?=\d)'), (m) => '${m[1]}*');
  return s.replaceAll(RegExp(r'\s+'), '');
}

/// Lee una expresión ya normalizada. Lanza [MathError] con lo que no entiende.
Expr parseExpr(String s) {
  final p = _Parser(s);
  final e = p.expr();
  if (!p.atEnd) throw MathError('No entiendo "${s.substring(p.pos)}".');
  return e;
}

class _Parser {
  _Parser(this.s);
  final String s;
  int pos = 0;

  bool get atEnd => pos >= s.length;
  String? get peek => atEnd ? null : s[pos];

  bool _eat(String c) {
    if (peek == c) {
      pos++;
      return true;
    }
    return false;
  }

  Expr expr() {
    var e = term();
    while (peek == '+' || peek == '-') {
      final op = s[pos++];
      e = Bin(op, e, term());
    }
    return e;
  }

  bool get _startsFactor {
    final c = peek;
    return c != null && (c == '(' || c == '√' || c == 'x' || c == 'y' || _isDigit(c) || c == '.');
  }

  Expr term() {
    var e = unary();
    while (true) {
      if (peek == '*' || peek == '/') {
        final op = s[pos++];
        e = Bin(op, e, unary());
      } else if (_startsFactor && !(_isDigit(peek!) && e is! Var && !_endsWithParen)) {
        // Multiplicación implícita: 3x, 2(x+1), x(x-1), (x+1)(x-1), 2√3.
        e = Bin('*', e, unary());
      } else {
        return e;
      }
    }
  }

  bool get _endsWithParen => pos > 0 && s[pos - 1] == ')';

  Expr unary() {
    if (_eat('-')) return Neg(unary());
    if (_eat('+')) return unary();
    return power();
  }

  Expr power() {
    final base = postfix();
    if (_eat('^')) return Bin('^', base, unary());
    return base;
  }

  Expr postfix() {
    var e = primary();
    while (_eat('%')) {
      e = Pct(e);
    }
    return e;
  }

  Expr primary() {
    final c = peek;
    if (c == null) throw const MathError('Falta algo al final.');
    if (_eat('(')) {
      final e = expr();
      if (!_eat(')')) throw const MathError('Falta cerrar un paréntesis.');
      return e;
    }
    if (_eat('√')) return Sqrt(power());
    if (c == 'x' || c == 'y') {
      pos++;
      return Var(c);
    }
    if (_isDigit(c) || c == '.' || c == ',') {
      final m = RegExp(r'\d*[.,]?\d+|\d+').matchAsPrefix(s, pos);
      if (m == null) throw MathError('No entiendo "$c".');
      pos = m.end;
      return Num(Rational.parse(m[0]!));
    }
    if (RegExp(r'[a-z]').hasMatch(c)) throw MathError('Solo se puede usar x e y como incógnitas (encontré "$c").');
    throw MathError('No entiendo el símbolo "$c".');
  }
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

int _prec(Expr e) => switch (e) {
      Bin(op: '+' || '-') => 1,
      Bin(op: '*' || '/') => 2,
      Neg() => 3,
      Num(:final value) when value.isNegative => 3,
      Bin(op: '^') => 4,
      _ => 5,
    };

const _sup = {'0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹'};

/// Cómo se ve: 3x² − 2(x + 1) = 5 · 3/4 ÷ 2.
String showExpr(Expr e) {
  String wrap(Expr c, int min) => _prec(c) < min ? '(${showExpr(c)})' : showExpr(c);
  return switch (e) {
    Num(:final value) => value.toString(),
    Approx(:final value) => formatDecimal(value),
    Var(:final name) => name,
    Neg(:final child) => '−${wrap(child, 4)}',
    Pct(:final child) => '${wrap(child, 5)}%',
    Sqrt(:final child) => '√${wrap(child, 5)}',
    Bin(op: '^', :final left, :final right) => right is Num && right.value.isInteger && !right.value.isNegative && right.value.num < BigInt.from(10)
        ? '${wrap(left, 5)}${_sup['${right.value.num}']}'
        : '${wrap(left, 5)}^${wrap(right, 5)}',
    Bin(op: '*', :final left, :final right) when (right is Var || right is Sqrt || (right is Bin && right.op == '^' && right.left is Var)) && isNumber(left) =>
      '${wrap(left, 2)}${showExpr(right)}',
    Bin(op: '*', :final left, :final right) => '${wrap(left, 2)} × ${wrap(right, 3)}',
    Bin(op: '/', :final left, :final right) => '${wrap(left, 2)} ÷ ${wrap(right, 3)}',
    Bin(:final op, :final left, :final right) => '${wrap(left, 1)} ${op == '-' ? '−' : op} ${wrap(right, 2)}',
  };
}

/// En notación matemática (LaTeX), para dibujarla como en un cuaderno:
/// fracciones apiladas, exponentes arriba, raíces con su techo.
String texExpr(Expr e) {
  int prec(Expr c) => switch (c) {
        Bin(op: '/') => 5, // la fracción apilada no necesita paréntesis
        _ => _prec(c),
      };
  String wrap(Expr c, int min) => prec(c) < min ? r'\left(' '${texExpr(c)}' r'\right)' : texExpr(c);
  return switch (e) {
    Num(:final value) => texRational(value),
    Approx(:final value) => texDecimal(value),
    Var(:final name) => name,
    Neg(:final child) => '-${wrap(child, 4)}',
    Pct(:final child) => '${wrap(child, 5)}\\%',
    Sqrt(:final child) => '\\sqrt{${texExpr(child)}}',
    Bin(op: '^', :final left, :final right) => '{${wrap(left, 5)}}^{${texExpr(right)}}',
    Bin(op: '/', :final left, :final right) => '\\frac{${texExpr(left)}}{${texExpr(right)}}',
    Bin(op: '*', :final left, :final right) when (right is Var || right is Sqrt || (right is Bin && right.op == '^' && right.left is Var)) && isNumber(left) =>
      '${wrap(left, 2)}${texExpr(right)}',
    Bin(op: '*', :final left, :final right) => '${wrap(left, 2)} \\times ${wrap(right, 3)}',
    Bin(:final op, :final left, :final right) => '${wrap(left, 1)} $op ${wrap(right, 2)}',
  };
}

/// Fracción apilada (−3/4 → −\frac{3}{4}) o entero.
String texRational(Rational r) {
  if (r.isInteger) return '${r.num}';
  final a = r.abs();
  return '${r.isNegative ? '-' : ''}\\frac{${a.num}}{${a.den}}';
}

/// Decimal con coma sin el espacio que LaTeX pone tras la coma.
String texDecimal(double v) => formatDecimal(v).replaceAll(',', '{,}');

/// Pasa a LaTeX el texto de un paso tal como lo escribe el solucionador
/// (3/4, √2, x², ±, ÷, ×, Δ, x₁…). Las palabras sueltas quedan como texto.
String texFromDisplay(String s) {
  var t = s
      .replaceAllMapped(RegExp(r'(-?)(\d+)/(\d+)'), (m) => '${m[1]}\\frac{${m[2]}}{${m[3]}}')
      .replaceAllMapped(RegExp(r'√(\d+)'), (m) => '\\sqrt{${m[1]}}')
      .replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}{,}${m[2]}')
      .replaceAll('²', '^{2}')
      .replaceAll('³', '^{3}')
      .replaceAll('×', r' \times ')
      .replaceAll('÷', r' \div ')
      .replaceAll('−', '-')
      .replaceAll('±', r'\pm ')
      .replaceAll('≈', r' \approx ')
      .replaceAll('Δ', r'\Delta ')
      .replaceAll('₁', '_1')
      .replaceAll('₂', '_2');
  // Palabras (o, y como conjunción no; "o" entre soluciones): como texto.
  t = t.replaceAllMapped(RegExp(r'\s{2,}o\s{2,}'), (_) => r'\quad\text{o}\quad ');
  t = t.replaceAll(';', r',\quad ');
  return t;
}

/// Cómo se dice en voz alta: "3 x al cuadrado menos 2 por paréntesis…".
String speakExpr(Expr e) {
  String inner(Expr c, int min) => _prec(c) < min ? 'abre paréntesis ${speakExpr(c)} cierra paréntesis' : speakExpr(c);
  String num(Rational r) {
    final sign = r.isNegative ? 'menos ' : '';
    final a = r.abs();
    return a.isInteger ? '$sign${a.num}' : '$sign${a.num} sobre ${a.den}';
  }

  return switch (e) {
    Num(:final value) => num(value),
    Approx(:final value) => formatDecimal(value),
    Var(:final name) => name,
    Neg(:final child) => 'menos ${inner(child, 4)}',
    Pct(:final child) => '${inner(child, 5)} por ciento',
    Sqrt(:final child) => 'raíz cuadrada de ${inner(child, 5)}',
    Bin(op: '^', :final left, right: Num(:final value)) when value == Rational.of(2) => '${inner(left, 5)} al cuadrado',
    Bin(op: '^', :final left, right: Num(:final value)) when value == Rational.of(3) => '${inner(left, 5)} al cubo',
    Bin(op: '^', :final left, :final right) => '${inner(left, 5)} elevado a ${inner(right, 5)}',
    Bin(op: '*', :final left, :final right) => '${inner(left, 2)} por ${inner(right, 3)}',
    Bin(op: '/', :final left, :final right) => '${inner(left, 2)} entre ${inner(right, 3)}',
    Bin(:final op, :final left, :final right) => '${inner(left, 1)} ${op == '-' ? 'menos' : 'más'} ${inner(right, 2)}',
  };
}

/// Un paso de una cuenta: hace una sola operación (la que toca según el orden
/// de las operaciones). null si ya es un número.
Expr? reduceOnce(Expr e) {
  switch (e) {
    case Num() || Approx():
      return null;
    case Var(:final name):
      throw MathError('Hay una incógnita ($name) pero no un "=": escribe una ecuación para despejarla.');
    case Neg(:final child):
      if (child is Num) return Num(-child.value);
      if (child is Approx) return Approx(-child.value);
      return Neg(reduceOnce(child)!);
    case Pct(:final child):
      if (child is Num) return Num(child.value / Rational.of(100));
      if (child is Approx) return Approx(child.value / 100);
      return Pct(reduceOnce(child)!);
    case Sqrt(:final child):
      if (child is Num) return sqrtValue(child.value);
      if (child is Approx) {
        if (child.value < 0) throw const MathError('No existe la raíz cuadrada real de un número negativo.');
        return Approx(math.sqrt(child.value));
      }
      return Sqrt(reduceOnce(child)!);
    case Bin(:final op, :final left, :final right):
      if (isNumber(left) && isNumber(right)) return _compute(op, left, right);
      if (!isNumber(left)) return Bin(op, reduceOnce(left)!, right);
      return Bin(op, left, reduceOnce(right)!);
  }
}

/// √ de un número: exacta si se puede, si no aproximada.
Expr sqrtValue(Rational v) {
  if (v.isNegative) throw const MathError('No existe la raíz cuadrada real de un número negativo.');
  final exact = v.sqrtExact();
  return exact != null ? Num(exact) : Approx(math.sqrt(v.toDouble()));
}

double _d(Expr e) => e is Num ? e.value.toDouble() : (e as Approx).value;

Expr _compute(String op, Expr l, Expr r) {
  if (l is Num && r is Num) {
    final a = l.value, b = r.value;
    switch (op) {
      case '+':
        return Num(a + b);
      case '-':
        return Num(a - b);
      case '*':
        return Num(a * b);
      case '/':
        return Num(a / b);
      case '^':
        if (b.isInteger) {
          if (a.isZero && b.isNegative) throw const MathError('No se puede dividir entre cero.');
          return Num(a.pow(b.num.toInt()));
        }
        if (a.isNegative) throw const MathError('Esa potencia no da un número real.');
        return Approx(math.pow(a.toDouble(), b.toDouble()).toDouble());
    }
  }
  final a = _d(l), b = _d(r);
  return Approx(switch (op) {
    '+' => a + b,
    '-' => a - b,
    '*' => a * b,
    '/' => b == 0 ? throw const MathError('No se puede dividir entre cero.') : a / b,
    _ => math.pow(a, b).toDouble(),
  });
}
