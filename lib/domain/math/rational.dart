/// Número racional exacto (fracción irreducible con denominador positivo):
/// las cuentas del colegio dan resultados exactos, sin errores de redondeo.
class Rational implements Comparable<Rational> {
  factory Rational(BigInt num, [BigInt? den]) {
    var d = den ?? BigInt.one;
    if (d == BigInt.zero) throw const MathError('No se puede dividir entre cero.');
    var n = num;
    if (d.isNegative) {
      n = -n;
      d = -d;
    }
    final g = n.gcd(d);
    return g > BigInt.one ? Rational._(n ~/ g, d ~/ g) : Rational._(n, d);
  }

  const Rational._(this.num, this.den);

  factory Rational.of(int n, [int d = 1]) => Rational(BigInt.from(n), BigInt.from(d));

  /// "2.5", "2,5", "-3", "0.125" → exacto.
  factory Rational.parse(String s) {
    final t = s.replaceAll(',', '.');
    final dot = t.indexOf('.');
    if (dot < 0) return Rational(BigInt.parse(t));
    final decimals = t.length - dot - 1;
    final digits = t.replaceFirst('.', '');
    return Rational(BigInt.parse(digits.isEmpty || digits == '-' ? '0' : digits), BigInt.from(10).pow(decimals));
  }

  static final zero = Rational._(BigInt.zero, BigInt.one);
  static final one = Rational._(BigInt.one, BigInt.one);

  final BigInt num;
  final BigInt den;

  bool get isZero => num == BigInt.zero;
  bool get isInteger => den == BigInt.one;
  bool get isNegative => num.isNegative;
  double toDouble() => num / den;

  Rational operator +(Rational o) => Rational(num * o.den + o.num * den, den * o.den);
  Rational operator -(Rational o) => Rational(num * o.den - o.num * den, den * o.den);
  Rational operator *(Rational o) => Rational(num * o.num, den * o.den);
  Rational operator /(Rational o) {
    if (o.isZero) throw const MathError('No se puede dividir entre cero.');
    return Rational(num * o.den, den * o.num);
  }

  Rational operator -() => Rational._(-num, den);
  Rational abs() => isNegative ? -this : this;

  /// Potencia con exponente entero (negativo = inverso).
  Rational pow(int e) {
    if (e < 0) return Rational.one / pow(-e);
    if (e > 64) throw const MathError('El exponente es demasiado grande.');
    return Rational(num.pow(e), den.pow(e));
  }

  /// Raíz cuadrada exacta si es un cuadrado perfecto; si no, null.
  Rational? sqrtExact() {
    if (isNegative) return null;
    final n = _isqrt(num), d = _isqrt(den);
    return n * n == num && d * d == den ? Rational(n, d) : null;
  }

  @override
  bool operator ==(Object other) => other is Rational && other.num == num && other.den == den;

  @override
  int get hashCode => Object.hash(num, den);

  @override
  int compareTo(Rational other) => (num * other.den).compareTo(other.num * den);

  /// "3", "-3/4".
  @override
  String toString() => isInteger ? '$num' : '$num/$den';

  /// Aproximación decimal legible: "0,75", "3,1623".
  String toDecimal([int places = 4]) => formatDecimal(toDouble(), places);
}

/// Error de la cuenta en palabras del estudiante.
class MathError implements Exception {
  const MathError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Número decimal con coma y sin ceros de más: 0,75 · 3,1623 · 2.
String formatDecimal(double v, [int places = 4]) {
  if (v.isNaN || v.isInfinite) return '$v';
  var s = v.toStringAsFixed(places);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  if (s == '-0') s = '0';
  return s.replaceAll('.', ',');
}

BigInt _isqrt(BigInt n) {
  if (n < BigInt.two) return n;
  var x = BigInt.from(1) << ((n.bitLength + 1) ~/ 2);
  while (true) {
    final y = (x + n ~/ x) >> 1;
    if (y >= x) return x;
    x = y;
  }
}

/// √n con n entero positivo como k·√m (√72 = 6·√2). Devuelve (k, m).
(BigInt, BigInt) simplifySqrt(BigInt n) {
  var k = BigInt.one;
  var m = n;
  var f = BigInt.two;
  while (f * f <= m) {
    final sq = f * f;
    while (m % sq == BigInt.zero) {
      m = m ~/ sq;
      k *= f;
    }
    f += BigInt.one;
    if (f > BigInt.from(100000)) break;
  }
  return (k, m);
}
