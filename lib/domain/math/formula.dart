import 'dart:math' as math;

import 'expr.dart';
import 'rational.dart';

/// Una fórmula con funciones (seno, logaritmo…) para la calculadora y el
/// graficador. A diferencia del resolvedor, da valores aproximados (double).
/// Fuera de su dominio da NaN, y al dividir por cero, infinito.
class MathFormula {
  const MathFormula._(this.source, this._f, this.usesX);

  /// Lo que se escribió, sin el «y =».
  final String source;
  final double Function(double x) _f;
  final bool usesX;

  double at([double x = 0]) => _f(x);
}

/// Una ventana del plano.
typedef GraphWindow = ({double minX, double maxX, double minY, double maxY});

/// Lee una fórmula. [degrees]: los ángulos van en grados. [ans]: el valor de
/// «Ans». Lanza [MathError] con lo que no entiende.
MathFormula parseFormula(String raw, {bool degrees = false, double ans = 0}) {
  final mixed = expandMixedNumbers(raw);
  if (RegExp(r'\d\s+\d').hasMatch(mixed)) throw const MathError('Completa el número mixto: por ejemplo 2 1/3.');
  var s = normalizeMath(mixed).replaceFirst(RegExp(r'^(y|f\(x\))='), '');
  if (s.contains('=')) throw const MathError('Para graficar escribe y = y la fórmula, por ejemplo y = 2x + 1.');
  if (s.isEmpty) throw const MathError('Escribe una fórmula.');
  s = s.replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}');
  final parser = _FormulaParser(s, degrees: degrees, ans: ans);
  final f = parser.expr();
  if (!parser.atEnd) throw MathError('No entiendo "${s.substring(parser.pos)}".');
  return MathFormula._(s, f, parser.usesX);
}

/// «2 1/3» es dos enteros y un tercio: (2+1/3).
String expandMixedNumbers(String raw) =>
    raw.replaceAllMapped(RegExp(r'(\d+)\s+(\d+)\s*/\s*(\d+)'), (m) => '(${m[1]}+${m[2]}/${m[3]})');

/// El resultado exacto de una cuenta con fracciones; null si no lo tiene (lleva
/// seno, π o una raíz que no es exacta) o si la cuenta no se puede hacer.
/// [ans] es el valor exacto de «Ans».
Rational? exactValue(String raw, {Rational? ans}) {
  var text = expandMixedNumbers(raw);
  final hasAns = RegExp('ans', caseSensitive: false).hasMatch(text);
  if (hasAns && ans == null) return null;
  if (hasAns) text = text.replaceAll(RegExp('ans', caseSensitive: false), '($ans)');
  final open = '('.allMatches(text).length - ')'.allMatches(text).length;
  if (open > 0) text += ')' * open;
  try {
    Expr? e = parseExpr(normalizeMath(text));
    Expr last = e;
    while (e != null) {
      last = e;
      e = reduceOnce(e);
    }
    return last is Num ? last.value : null;
  } on MathError {
    return null;
  }
}

/// ¿Dos lecturas de la misma foto dan cuentas distintas? Si alguna no se puede
/// calcular, no hay con qué compararla: no cuenta como diferencia.
bool readingsDiffer(String a, String b) {
  final x = exactValue(a), y = exactValue(b);
  return x != null && y != null && x != y;
}

/// La fracción sencilla que da ese decimal (sen(30°) = 1/2), si la hay. Una
/// raíz o π no se dejan pasar por fracción.
Rational? nearFraction(double v) {
  const maxDen = 10000, tolerance = 1e-12;
  if (!v.isFinite || v.abs() > 1e9) return null;
  var h0 = 0, h1 = 1, k0 = 1, k1 = 0;
  var x = v.abs();
  while (true) {
    final a = x.floor();
    final h = a * h1 + h0, k = a * k1 + k0;
    if (k > maxDen) return null;
    h0 = h1;
    h1 = h;
    k0 = k1;
    k1 = k;
    if ((h / k - v.abs()).abs() < tolerance) return Rational.of(v < 0 ? -h : h, k);
    if (x == a) return null;
    x = 1 / (x - a);
  }
}

/// Una fracción impropia en su parte entera y lo que sobra: 7/2 → (3, 1/2).
/// null si no tiene parte entera.
(BigInt, Rational)? mixedParts(Rational r) {
  final a = r.abs();
  if (a.isInteger || a.num < a.den) return null;
  final whole = a.num ~/ a.den;
  return (whole, a - Rational(whole));
}

typedef _Fn = double Function(double x);

class _FormulaParser {
  _FormulaParser(this.s, {required this.degrees, required this.ans});
  final String s;
  final bool degrees;
  final double ans;
  int pos = 0;
  bool usesX = false;

  /// Lo más largo primero: «arcsen» no es «a» + «rcsen», ni «exp» es «e».
  static const _functions = [
    'arcsen', 'arcsin', 'arccos', 'arctan', 'asen', 'asin', 'acos', 'atan', //
    'sen', 'sin', 'cos', 'tan', 'exp', 'abs', 'ln', 'log', 'tg',
  ];

  bool get atEnd => pos >= s.length;
  String? get _peek => atEnd ? null : s[pos];

  bool _eat(String c) {
    if (_peek != c) return false;
    pos++;
    return true;
  }

  _Fn expr() {
    var f = _term();
    while (_peek == '+' || _peek == '-') {
      final add = s[pos++] == '+';
      final a = f, b = _term();
      f = add ? (x) => a(x) + b(x) : (x) => a(x) - b(x);
    }
    return f;
  }

  bool get _startsFactor {
    final c = _peek;
    return c != null && RegExp(r'[0-9.(√πa-z]').hasMatch(c);
  }

  _Fn _term() {
    var f = _unary();
    while (true) {
      final a = f;
      if (_eat('*')) {
        final b = _unary();
        f = (x) => a(x) * b(x);
      } else if (_eat('/')) {
        final b = _unary();
        f = (x) => a(x) / b(x);
      } else if (_startsFactor) {
        // Multiplicación implícita: 2x, 3sen(x), (x+1)(x-1), 2π.
        final b = _unary();
        f = (x) => a(x) * b(x);
      } else {
        return f;
      }
    }
  }

  _Fn _unary() {
    if (_eat('-')) {
      final a = _unary();
      return (x) => -a(x);
    }
    if (_eat('+')) return _unary();
    return _power();
  }

  _Fn _power() {
    final base = _postfix();
    if (!_eat('^')) return base;
    final exponent = _unary();
    return (x) => math.pow(base(x), exponent(x)).toDouble();
  }

  _Fn _postfix() {
    var f = _primary();
    while (true) {
      final a = f;
      if (_eat('%')) {
        f = (x) => a(x) / 100;
      } else if (_eat('!')) {
        f = (x) => _factorial(a(x));
      } else {
        return f;
      }
    }
  }

  _Fn _primary() {
    if (_eat('(')) return _closed();
    if (_eat('√')) {
      final a = _peek == '(' ? _primary() : _power();
      return (x) => math.sqrt(a(x));
    }
    if (_eat('π')) return (_) => math.pi;
    final number = RegExp(r'\d+\.?\d*|\.\d+').matchAsPrefix(s, pos);
    if (number != null) {
      pos = number.end;
      final v = double.parse(number[0]!);
      return (_) => v;
    }
    for (final name in _functions) {
      if (!s.startsWith(name, pos)) continue;
      pos += name.length;
      if (!_eat('(')) throw MathError('Escribe $name(…) con paréntesis.');
      return _apply(name, _closed());
    }
    if (s.startsWith('ans', pos)) {
      pos += 3;
      final v = ans;
      return (_) => v;
    }
    if (s.startsWith('pi', pos)) {
      pos += 2;
      return (_) => math.pi;
    }
    if (_eat('e')) return (_) => math.e;
    if (_eat('x')) {
      usesX = true;
      return (x) => x;
    }
    if (atEnd) throw const MathError('Falta completar la fórmula.');
    throw MathError('No entiendo "${s.substring(pos)}".');
  }

  /// Lo de adentro de un paréntesis; se puede dejar sin cerrar al final.
  _Fn _closed() {
    final a = expr();
    if (!_eat(')') && !atEnd) throw MathError('No entiendo "${s.substring(pos)}".');
    return a;
  }

  _Fn _apply(String name, _Fn a) {
    final toRad = degrees ? math.pi / 180 : 1.0;
    final fromRad = degrees ? 180 / math.pi : 1.0;
    return switch (name) {
      'sen' || 'sin' => (x) => _tidy(math.sin(a(x) * toRad)),
      'cos' => (x) => _tidy(math.cos(a(x) * toRad)),
      // Sin cuidar esto, tan(90°) daría un número enorme en vez de no existir.
      'tan' || 'tg' => (x) {
        final angle = a(x) * toRad;
        return _tidy(math.cos(angle)) == 0 ? double.nan : _tidy(math.tan(angle));
      },
      'arcsen' || 'arcsin' || 'asen' || 'asin' => (x) => math.asin(a(x)) * fromRad,
      'arccos' || 'acos' => (x) => math.acos(a(x)) * fromRad,
      'arctan' || 'atan' => (x) => math.atan(a(x)) * fromRad,
      'ln' => (x) => math.log(a(x)),
      'log' => (x) => math.log(a(x)) / math.ln10,
      'exp' => (x) => math.exp(a(x)),
      _ => (x) => a(x).abs(),
    };
  }

  /// Sen(180°) no da 0 por los decimales de π: lo que es casi cero, es cero.
  static double _tidy(double v) => v.abs() < 1e-14 ? 0 : v;

  static double _factorial(double v) {
    if (v < 0 || v != v.roundToDouble() || v > 170) return double.nan;
    var out = 1.0;
    for (var i = 2; i <= v; i++) {
      out *= i;
    }
    return out;
  }
}

/// Un número como se escribe aquí: coma decimal y 12 cifras (así 0,1 + 0,2
/// da 0,3). Muy grande o muy chico, con potencia de 10.
String formatNumber(double v) {
  if (v.isNaN) return 'no existe';
  if (v.isInfinite) return v < 0 ? '−infinito' : 'infinito';
  if (v == 0) return '0';
  final abs = v.abs();
  final sign = v < 0 ? '−' : '';
  String clean(String digits) {
    final trimmed = digits.contains('.') ? digits.replaceFirst(RegExp(r'\.?0+$'), '') : digits;
    return trimmed.replaceAll('.', ',');
  }

  if (abs >= 1e15 || abs < 1e-9) {
    final parts = abs.toStringAsExponential(9).split('e');
    return '$sign${clean(parts[0])} × 10^${int.parse(parts[1])}';
  }
  final whole = (math.log(abs) / math.ln10).floor();
  return '$sign${clean(abs.toStringAsFixed((11 - whole).clamp(0, 20)))}';
}

/// Los tramos de la curva para dibujarla: se corta donde no existe y donde
/// salta de un extremo al otro (y = 1/x, y = tan(x)), sin unirlos con una raya.
List<List<(double, double)>> plotSegments(double Function(double) f, GraphWindow w, {int samples = 500}) {
  final out = <List<(double, double)>>[];
  var current = <(double, double)>[];
  double? last;
  final span = w.maxY - w.minY;
  for (var k = 0; k <= samples; k++) {
    final x = w.minX + (w.maxX - w.minX) * k / samples;
    final y = f(x);
    final jumps = last != null && ((last > w.maxY && y < w.minY) || (last < w.minY && y > w.maxY));
    if (!y.isFinite || jumps) {
      if (current.length > 1) out.add(current);
      current = [];
    }
    if (y.isFinite) {
      // Muy afuera no se ve, y a la pantalla no le gustan los números enormes.
      current.add((x, y.clamp(w.minY - 2 * span, w.maxY + 2 * span)));
      last = y;
    } else {
      last = null;
    }
  }
  if (current.length > 1) out.add(current);
  return out;
}

/// El alto que muestra casi toda la curva en ese ancho, sin que una asíntota
/// lo arruine: se deja afuera lo más extremo.
({double minY, double maxY}) fitHeight(Iterable<double Function(double)> curves, double minX, double maxX) {
  const samples = 400;
  final ys = <double>[
    for (final f in curves)
      for (var k = 0; k <= samples; k++)
        if (f(minX + (maxX - minX) * k / samples) case final y when y.isFinite) y,
  ]..sort();
  if (ys.isEmpty) return (minY: -1, maxY: 1);
  final lo = ys[(ys.length * 0.03).floor()], hi = ys[(ys.length * 0.97).floor().clamp(0, ys.length - 1)];
  final margin = hi - lo < 1e-9 ? 1.0 : (hi - lo) * 0.1;
  return (minY: lo - margin, maxY: hi + margin);
}

/// Dónde cruza o toca el eje x, dentro de ese ancho.
List<double> formulaRoots(double Function(double) f, double minX, double maxX, {int samples = 500}) {
  final step = (maxX - minX) / samples;
  double xAt(int k) => minX + step * k;
  final ys = [for (var k = 0; k <= samples; k++) f(xAt(k))];
  if (ys.every((y) => y == 0)) return const []; // la recta es el mismo eje
  final tolerance = step / 4;
  final roots = <double>[];
  void add(double x) {
    if (roots.isEmpty || (x - roots.last).abs() > tolerance) roots.add(x.abs() < 1e-10 ? 0 : x);
  }

  for (var k = 0; k <= samples; k++) {
    final y = ys[k];
    if (y == 0) {
      add(xAt(k));
    } else if (k < samples && y.isFinite && ys[k + 1].isFinite && y * ys[k + 1] < 0) {
      // El signo cambia: es raíz si la curva llega a cero, no si salta (1/x).
      var lo = xAt(k), hi = xAt(k + 1);
      final startsPositive = y > 0;
      for (var i = 0; i < 60; i++) {
        final mid = (lo + hi) / 2;
        if (f(mid) > 0 == startsPositive) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      final x = (lo + hi) / 2;
      if (f(x).abs() < 1e-6) add(x);
    } else if (k > 0 && k < samples && y.isFinite && _touchesZero(f, ys, k, xAt(k - 1), xAt(k + 1))) {
      // Toca el eje sin cruzarlo (y = x²) entre dos muestras.
      add(_lowestPoint(f, xAt(k - 1), xAt(k + 1)));
    }
  }
  return roots;
}

bool _touchesZero(double Function(double) f, List<double> ys, int k, double lo, double hi) {
  final y = ys[k].abs(), before = ys[k - 1], after = ys[k + 1];
  if (!before.isFinite || !after.isFinite || before * ys[k] <= 0 || after * ys[k] <= 0) return false;
  if (y > before.abs() || y > after.abs()) return false;
  return f(_lowestPoint(f, lo, hi)).abs() < 1e-9;
}

/// Donde |f| es menor entre [lo] y [hi] (búsqueda ternaria).
double _lowestPoint(double Function(double) f, double lo, double hi) {
  for (var i = 0; i < 60; i++) {
    final a = lo + (hi - lo) / 3, b = hi - (hi - lo) / 3;
    if (f(a).abs() < f(b).abs()) {
      hi = b;
    } else {
      lo = a;
    }
  }
  return (lo + hi) / 2;
}

/// La fórmula dicha en palabras, para escucharla.
String spokenFormula(String source) {
  var s = source;
  const words = {
    'arcsen': ' arco seno de ',
    'arcsin': ' arco seno de ',
    'asen': ' arco seno de ',
    'asin': ' arco seno de ',
    'arccos': ' arco coseno de ',
    'acos': ' arco coseno de ',
    'arctan': ' arco tangente de ',
    'atan': ' arco tangente de ',
    'sen': ' seno de ',
    'sin': ' seno de ',
    'cos': ' coseno de ',
    'tan': ' tangente de ',
    'tg': ' tangente de ',
    'ln': ' logaritmo natural de ',
    'log': ' logaritmo de ',
    'exp': ' e elevado a ',
    'abs': ' valor absoluto de ',
    '^2': ' al cuadrado ',
    '^3': ' al cubo ',
    '^': ' elevado a ',
    '√': ' raíz de ',
    'π': ' pi ',
    '*': ' por ',
    '/': ' entre ',
    '+': ' más ',
    '-': ' menos ',
    '%': ' por ciento ',
    '!': ' factorial ',
    '(': ' ',
    ')': ' ',
    '.': ',',
  };
  for (final e in words.entries) {
    s = s.replaceAll(e.key, e.value);
  }
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Lo que se dice de una curva: dónde corta los ejes en lo que se ve.
String describeFormula(MathFormula formula, double minX, double maxX) {
  String say(double v) => formatNumber(v).replaceAll('−', 'menos ').replaceAll('× 10^', 'por diez a la ');
  final out = StringBuffer('y igual a ${spokenFormula(formula.source)}.');
  final atZero = formula.at(0);
  out.write(atZero.isFinite ? ' Corta el eje y en ${say(atZero)}.' : ' No corta el eje y.');
  final roots = formulaRoots(formula.at, minX, maxX);
  const maxSaid = 6;
  if (roots.isEmpty) {
    out.write(' No corta el eje x en lo que se ve.');
  } else {
    final said = roots.take(maxSaid).map(say).join('; ');
    out.write(' Corta el eje x en $said${roots.length > maxSaid ? ' y en otros puntos' : ''}.');
  }
  return out.toString();
}
