import 'expr.dart';
import 'graph.dart';
import 'rational.dart';

/// Un paso de la solución: qué se hace, cómo queda y, si se tiene, cómo
/// queda en notación matemática ([tex], LaTeX) para dibujarlo bonito.
class MathStep {
  const MathStep({required this.note, required this.math, this.tex});
  final String note;
  final String math;
  final String? tex;

  /// LaTeX del paso (el propio o traducido del texto).
  String get latex => tex ?? texFromDisplay(math);
}

/// La solución completa: tipo de ejercicio, pasos y respuesta final.
class MathSolution {
  const MathSolution({
    required this.kind,
    required this.steps,
    required this.answer,
    this.answerTex,
    this.graph,
    this.isSystem = false,
  });
  final String kind;
  final List<MathStep> steps;
  final String answer;
  final String? answerTex;

  /// Para dibujar junto a la solución (parábola o rectas), si corresponde.
  final MathGraph? graph;

  /// Es un sistema: se puede resolver por otro método.
  final bool isSystem;

  MathSolution withGraph(MathGraph g) =>
      MathSolution(kind: kind, steps: steps, answer: answer, answerTex: answerTex, graph: g, isSystem: isSystem);

  /// El ejercicio como se planteó (primer paso), en LaTeX.
  String get problemLatex => steps.first.latex;

  /// La respuesta en LaTeX, o null si es una frase (sin solución, etc.).
  String? get answerLatex => answerTex ?? (RegExp(r'[a-záéíóúñ]{3,}', caseSensitive: false).hasMatch(answer) ? null : texFromDisplay(answer));

  /// Para escuchar los pasos con la voz de la app.
  List<String> spoken() => [
        kind,
        for (final s in steps) '${s.note} ${_speakable(s.math)}',
        'Respuesta: ${_speakable(answer)}',
      ];
}

/// De lo que se leyó en una foto, solo las líneas que son matemáticas (una
/// cuenta o una ecuación que se entiende), sin títulos, enunciados ni
/// enlaces. Vacío si no hay ninguna.
List<String> mathLinesIn(String ocrText) => [
      for (final raw in ocrText.split('\n'))
        if (_looksLikeMath(raw)) raw.trim(),
    ];

bool _looksLikeMath(String raw) {
  final line = raw.trim();
  if (line.isEmpty || line.contains('/') && RegExp(r'[a-z]{3,}/', caseSensitive: false).hasMatch(line)) return false;
  final norm = normalizeMath(line);
  if (!RegExp(r'\d').hasMatch(norm) && !norm.contains('x')) return false;
  if (!RegExp(r'[-+*/^=√%]').hasMatch(norm) && !RegExp(r'\d[xy]').hasMatch(norm)) return false;
  try {
    for (final side in norm.split('=')) {
      if (side.isEmpty) return false;
      parseExpr(side);
    }
    return true;
  } on MathError {
    return false;
  }
}

/// Lo que la app entendió de [input], en LaTeX, para mostrarlo bien escrito
/// antes de resolver (null si todavía no se entiende).
String? previewLatex(String input) {
  final lines = input.split(RegExp(r'[\n;]')).map(normalizeMath).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty || lines.length > 2) return null;
  try {
    final tex = [
      for (final l in lines) l.split('=').map((side) => side.isEmpty ? throw const MathError('') : texExpr(parseExpr(side))).join(' = '),
    ];
    return tex.length == 1 ? tex.single : r'\begin{cases} ' '${tex[0]}' r' \\ ' '${tex[1]}' r' \end{cases}';
  } on MathError {
    return null;
  }
}

/// Resuelve un ejercicio de colegio: una cuenta, una ecuación (1.º o 2.º
/// grado, regla de tres) o un sistema de dos ecuaciones (una por línea o
/// separadas por ";"). Lanza [MathError] si no lo entiende.
MathSolution solveMath(String input, {SystemMethod method = SystemMethod.sustitucion}) {
  final lines = input.split(RegExp(r'[\n;]')).map(normalizeMath).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) throw const MathError('Escribe un ejercicio.');
  if (lines.length == 2 && lines.every((l) => l.contains('='))) return _system(lines[0], lines[1], method);
  if (lines.length > 1) throw const MathError('Escribe un ejercicio por vez (o dos ecuaciones para un sistema).');
  final line = lines.single;
  final sides = line.split('=');
  if (sides.length == 1) return _arithmetic(parseExpr(line));
  if (sides.length != 2 || sides.any((s) => s.isEmpty)) throw const MathError('Una ecuación lleva un solo "=" con algo a cada lado.');
  return _equation(parseExpr(sides[0]), parseExpr(sides[1]));
}

// ---------------------------------------------------------------- cuentas

MathSolution _arithmetic(Expr e) {
  const maxSteps = 40;
  final steps = <MathStep>[MathStep(note: 'Ejercicio:', math: showExpr(e), tex: texExpr(e))];
  var cur = e;
  var i = 0;
  while (true) {
    final next = reduceOnce(cur);
    if (next == null) break;
    if (++i > maxSteps) throw const MathError('La cuenta es demasiado larga para mostrarla paso a paso.');
    steps.add(MathStep(note: _whatChanged(cur), math: showExpr(next), tex: texExpr(next)));
    cur = next;
  }
  final (answer, answerTex) = switch (cur) {
    Num(:final value) when !value.isInteger => (
        '${value.toString()} = ${value.toDecimal()}',
        '${texRational(value)} = ${texDecimal(value.toDouble())}',
      ),
    _ => (showExpr(cur), texExpr(cur)),
  };
  return MathSolution(
    kind: 'Cuenta paso a paso, respetando el orden de las operaciones.',
    steps: steps,
    answer: answer,
    answerTex: answerTex,
  );
}

/// Qué operación se hace sobre [before] en el siguiente paso.
String _whatChanged(Expr before) {
  final op = _firstOp(before);
  return switch (op) {
    '^' => 'Resolvemos la potencia:',
    '*' => 'Multiplicamos:',
    '/' => 'Dividimos:',
    '+' => 'Sumamos:',
    '-' => 'Restamos:',
    '√' => 'Calculamos la raíz:',
    '%' => 'Pasamos el porcentaje a fracción:',
    _ => 'Simplificamos:',
  };
}

/// La operación que [reduceOnce] hace primero.
String? _firstOp(Expr e) => switch (e) {
      Num() || Approx() || Var() => null,
      Neg(:final child) => isNumber(child) ? 'signo' : _firstOp(child),
      Pct(:final child) => isNumber(child) ? '%' : _firstOp(child),
      Sqrt(:final child) => isNumber(child) ? '√' : _firstOp(child),
      Bin(:final op, :final left, :final right) =>
        isNumber(left) && isNumber(right) ? op : (!isNumber(left) ? _firstOp(left) : _firstOp(right)),
    };

// ---------------------------------------------------------------- polinomios

/// Suma de términos c·x^a·y^b con grado total hasta 2 (lo del colegio).
class _Poly {
  _Poly(Map<(int, int), Rational> terms) : terms = {for (final e in terms.entries) if (!e.value.isZero) e.key: e.value};
  _Poly.constant(Rational c) : this({(0, 0): c});
  final Map<(int, int), Rational> terms;

  Rational coef(int a, int b) => terms[(a, b)] ?? Rational.zero;
  int get degree => terms.keys.fold(0, (m, k) => k.$1 + k.$2 > m ? k.$1 + k.$2 : m);
  bool get isConstant => terms.keys.every((k) => k == (0, 0));
  bool uses(String v) => terms.keys.any((k) => v == 'x' ? k.$1 > 0 : k.$2 > 0);

  _Poly operator +(_Poly o) {
    final r = Map.of(terms);
    o.terms.forEach((k, v) => r[k] = (r[k] ?? Rational.zero) + v);
    return _Poly(r);
  }

  _Poly operator -() => _Poly({for (final e in terms.entries) e.key: -e.value});
  _Poly operator -(_Poly o) => this + -o;

  _Poly operator *(_Poly o) {
    final r = <(int, int), Rational>{};
    for (final a in terms.entries) {
      for (final b in o.terms.entries) {
        final k = (a.key.$1 + b.key.$1, a.key.$2 + b.key.$2);
        if (k.$1 + k.$2 > 2) throw const MathError('Esa ecuación es de grado mayor que 2: está fuera de lo que resuelvo por ahora.');
        r[k] = (r[k] ?? Rational.zero) + a.value * b.value;
      }
    }
    return _Poly(r);
  }

  _Poly scale(Rational c) => _Poly({for (final e in terms.entries) e.key: e.value * c});

  /// Como se ve: 3x² − 2x + 5 (orden: x², xy, y², x, y, número).
  String show() {
    const order = [(2, 0), (1, 1), (0, 2), (1, 0), (0, 1), (0, 0)];
    final buf = StringBuffer();
    for (final k in order) {
      final c = terms[k];
      if (c == null) continue;
      final name = switch (k) {
        (2, 0) => 'x²',
        (1, 1) => 'xy',
        (0, 2) => 'y²',
        (1, 0) => 'x',
        (0, 1) => 'y',
        _ => '',
      };
      final a = c.abs();
      final body = name.isEmpty ? a.toString() : a == Rational.one ? name : a.isInteger ? '$a$name' : '($a)$name';
      if (buf.isEmpty) {
        buf.write(c.isNegative ? '−$body' : body);
      } else {
        buf.write(c.isNegative ? ' − $body' : ' + $body');
      }
    }
    return buf.isEmpty ? '0' : buf.toString();
  }
}

_Poly _toPoly(Expr e) => switch (e) {
      Num(:final value) => _Poly.constant(value),
      Approx() => throw const MathError('En una ecuación usa números exactos (sin raíces que no den exacto).'),
      Var(name: 'x') => _Poly({(1, 0): Rational.one}),
      Var() => _Poly({(0, 1): Rational.one}),
      Neg(:final child) => -_toPoly(child),
      Pct(:final child) => _toPoly(child).scale(Rational.of(1, 100)),
      Sqrt(:final child) => switch (_toPoly(child)) {
          final p when p.isConstant => switch (sqrtValue(p.coef(0, 0))) {
              Num(:final value) => _Poly.constant(value),
              _ => throw const MathError('En una ecuación usa números exactos (sin raíces que no den exacto).'),
            },
          _ => throw const MathError('Las ecuaciones con la incógnita dentro de una raíz están fuera de lo que resuelvo por ahora.'),
        },
      Bin(op: '+', :final left, :final right) => _toPoly(left) + _toPoly(right),
      Bin(op: '-', :final left, :final right) => _toPoly(left) - _toPoly(right),
      Bin(op: '*', :final left, :final right) => _toPoly(left) * _toPoly(right),
      Bin(op: '/', :final left, :final right) => switch (_toPoly(right)) {
          final d when d.isConstant => _toPoly(left).scale(Rational.one / d.coef(0, 0)),
          _ => throw const _VarInDenominator(),
        },
      Bin(op: '^', :final left, :final right) => _power(_toPoly(left), _toPoly(right)),
      Bin() => throw const MathError('No entiendo esa operación.'),
    };

_Poly _power(_Poly base, _Poly exp) {
  final e = exp.isConstant ? exp.coef(0, 0) : null;
  if (e == null || !e.isInteger || e.isNegative) {
    if (base.isConstant && e != null) {
      final v = reduceOnce(Bin('^', Num(base.coef(0, 0)), Num(e)));
      if (v is Num) return _Poly.constant(v.value);
    }
    throw const MathError('Esa potencia está fuera de lo que resuelvo por ahora.');
  }
  var r = _Poly.constant(Rational.one);
  for (var i = 0; i < e.num.toInt(); i++) {
    r = r * base;
  }
  return r;
}

class _VarInDenominator implements Exception {
  const _VarInDenominator();
}

// ---------------------------------------------------------------- ecuaciones

MathSolution _equation(Expr l, Expr r) {
  final steps = <MathStep>[MathStep(note: 'Ecuación:', math: '${showExpr(l)} = ${showExpr(r)}', tex: '${texExpr(l)} = ${texExpr(r)}')];
  _Poly left, right;
  try {
    left = _toPoly(l);
    right = _toPoly(r);
  } on _VarInDenominator {
    // a/b = c/x: se multiplica en cruz (regla de tres).
    final (nl, dl) = _fraction(l);
    final (nr, dr) = _fraction(r);
    final a = Bin('*', nl, dr), b = Bin('*', nr, dl);
    steps.add(MathStep(note: 'La incógnita está en un denominador: multiplicamos en cruz.', math: '${showExpr(a)} = ${showExpr(b)}', tex: '${texExpr(a)} = ${texExpr(b)}'));
    try {
      left = _toPoly(a);
      right = _toPoly(b);
    } on _VarInDenominator {
      throw const MathError('Esa ecuación con fracciones está fuera de lo que resuelvo por ahora.');
    }
  }
  if (left.uses('y') || right.uses('y')) {
    throw const MathError('Con x e y hacen falta dos ecuaciones: escribe una por línea.');
  }
  final all = left - right;
  if (all.degree <= 1) return _linear(steps, left, right, all);
  return _quadratic(steps, left, right, all).withGraph(_parabola(all));
}

(Expr, Expr) _fraction(Expr e) => e is Bin && e.op == '/' ? (e.left, e.right) : (e, Num(Rational.one));

MathSolution _linear(List<MathStep> steps, _Poly left, _Poly right, _Poly all) {
  if (!_same(left, right, steps)) {
    steps.add(MathStep(note: 'Quitamos paréntesis y juntamos términos semejantes:', math: '${left.show()} = ${right.show()}'));
  }
  final a = all.coef(1, 0), b = all.coef(0, 0);
  final xs = _Poly({(1, 0): left.coef(1, 0) - right.coef(1, 0)});
  final nums = _Poly.constant(right.coef(0, 0) - left.coef(0, 0));
  steps.add(MathStep(note: 'Pasamos los términos con x a la izquierda y los números a la derecha (cambian de signo al pasar):', math: '${xs.show()} = ${nums.show()}'));
  if (a.isZero) {
    final answer = b.isZero ? 'Se cumple para cualquier valor de x (infinitas soluciones).' : 'No tiene solución: queda ${nums.show()} = 0, que es falso.';
    return MathSolution(kind: 'Ecuación de primer grado.', steps: steps, answer: answer);
  }
  final x = -b / a;
  if (a != Rational.one) steps.add(MathStep(note: 'Dividimos ambos lados entre $a:', math: 'x = ${nums.show()} ÷ $a'));
  steps.add(MathStep(note: 'Resultado:', math: 'x = $x'));
  final check = _eval(left, x, Rational.zero);
  steps.add(MathStep(note: 'Comprobación: reemplazamos x = $x y ambos lados valen', math: '$check'));
  return MathSolution(kind: 'Ecuación de primer grado.', steps: steps, answer: _withDecimal('x', x));
}

MathSolution _quadratic(List<MathStep> steps, _Poly left, _Poly right, _Poly all) {
  final a = all.coef(2, 0), b = all.coef(1, 0), c = all.coef(0, 0);
  steps.add(MathStep(note: 'Pasamos todo a un lado, igualado a cero:', math: '${all.show()} = 0'));
  steps.add(MathStep(note: 'Es de segundo grado con', math: 'a = $a,  b = $b,  c = $c'));
  const kind = 'Ecuación de segundo grado.';
  if (b.isZero) {
    final v = -c / a;
    steps.add(MathStep(note: 'No tiene término con x: despejamos x².', math: 'x² = $v'));
    if (v.isNegative) return MathSolution(kind: kind, steps: steps, answer: 'No tiene solución real (x² no puede ser negativo).');
    final root = sqrtValue(v);
    steps.add(MathStep(note: 'Sacamos raíz cuadrada (dos signos):', math: 'x = ±√$v'));
    return MathSolution(kind: kind, steps: steps, answer: 'x = ±${showExpr(root)}');
  }
  if (c.isZero) {
    final x2 = -b / a;
    steps.add(MathStep(note: 'No tiene número suelto: sacamos x de factor común.', math: 'x(${_Poly({(1, 0): a, (0, 0): b}).show()}) = 0'));
    steps.add(MathStep(note: 'Un producto es cero si alguno de sus factores es cero:', math: 'x = 0   o   x = $x2'));
    return MathSolution(kind: kind, steps: steps, answer: 'x₁ = 0,  x₂ = $x2');
  }
  final disc = b * b - Rational.of(4) * a * c;
  steps.add(MathStep(note: 'Calculamos el discriminante:', math: 'Δ = b² − 4ac = ($b)² − 4 × ($a) × ($c) = $disc'));
  if (disc.isNegative) return MathSolution(kind: kind, steps: steps, answer: 'No tiene solución real (el discriminante es negativo).');
  steps.add(MathStep(note: 'Usamos la fórmula general:', math: 'x = (−b ± √Δ) ÷ 2a = (${-b} ± √$disc) ÷ ${Rational.of(2) * a}'));
  if (disc.isZero) {
    final x = -b / (Rational.of(2) * a);
    return MathSolution(kind: kind, steps: steps, answer: 'Una sola solución (doble): ${_withDecimal('x', x)}');
  }
  final exact = disc.sqrtExact();
  if (exact != null) {
    final x1 = (-b + exact) / (Rational.of(2) * a), x2 = (-b - exact) / (Rational.of(2) * a);
    steps.add(MathStep(note: '√Δ es exacta:', math: '√$disc = $exact'));
    return MathSolution(kind: kind, steps: steps, answer: 'x₁ = $x1,  x₂ = $x2');
  }
  final root = disc.toDouble();
  final x1 = (-b.toDouble() + _sqrt(root)) / (2 * a.toDouble()), x2 = (-b.toDouble() - _sqrt(root)) / (2 * a.toDouble());
  var radical = '√$disc';
  if (disc.isInteger) {
    final (k, m) = simplifySqrt(disc.num);
    if (k > BigInt.one) {
      radical = '$k√$m';
      steps.add(MathStep(note: 'Simplificamos la raíz:', math: '√$disc = $radical'));
    }
  }
  return MathSolution(
    kind: kind,
    steps: steps,
    answer: 'x = (${-b} ± $radical) ÷ ${Rational.of(2) * a};  x₁ ≈ ${formatDecimal(x1)},  x₂ ≈ ${formatDecimal(x2)}',
  );
}

// ---------------------------------------------------------------- sistemas

MathSolution _system(String first, String second, SystemMethod method) {
  final eqs = [first, second].map((line) {
    final sides = line.split('=');
    if (sides.length != 2 || sides.any((s) => s.isEmpty)) throw const MathError('Cada ecuación lleva un solo "=".');
    try {
      final p = _toPoly(parseExpr(sides[0])) - _toPoly(parseExpr(sides[1]));
      if (p.degree > 1) throw const MathError('Resuelvo sistemas de primer grado (sin x² ni xy).');
      return p;
    } on _VarInDenominator {
      throw const MathError('En un sistema no puede haber incógnitas en un denominador.');
    }
  }).toList();
  final [a1, b1, c1] = [eqs[0].coef(1, 0), eqs[0].coef(0, 1), -eqs[0].coef(0, 0)];
  final [a2, b2, c2] = [eqs[1].coef(1, 0), eqs[1].coef(0, 1), -eqs[1].coef(0, 0)];
  String eq(Rational a, Rational b, Rational c) => '${_Poly({(1, 0): a, (0, 1): b}).show()} = $c';
  final steps = <MathStep>[
    MathStep(
      note: 'Ordenamos las dos ecuaciones:',
      math: '${eq(a1, b1, c1)}   ;   ${eq(a2, b2, c2)}',
      tex: r'\begin{cases} ' '${texFromDisplay(eq(a1, b1, c1))}' r' \\ ' '${texFromDisplay(eq(a2, b2, c2))}' r' \end{cases}',
    ),
  ];
  final kind = 'Sistema de dos ecuaciones, por ${method.label}.';
  final lines = [_line(a1, b1, c1, '1.ª'), _line(a2, b2, c2, '2.ª')];
  final det = a1 * b2 - a2 * b1;
  if (det.isZero) {
    final same = a1 * c2 == a2 * c1 && b1 * c2 == b2 * c1;
    return MathSolution(
      kind: kind,
      steps: steps,
      answer: same ? 'Las dos ecuaciones son la misma recta: infinitas soluciones.' : 'Las rectas son paralelas: el sistema no tiene solución.',
      graph: MathGraph(curves: lines, points: const []),
      isSystem: true,
    );
  }
  final dx = c1 * b2 - c2 * b1, dy = a1 * c2 - a2 * c1;
  final x = dx / det, y = dy / det;
  if (method == SystemMethod.cramer) {
    steps.addAll([
      MathStep(note: 'Determinante del sistema:', math: 'Δ = $a1 × $b2 − ($a2) × ($b1) = $det'),
      MathStep(note: 'Determinante de x (los resultados en la columna de x):', math: 'Δx = $c1 × $b2 − ($c2) × ($b1) = $dx'),
      MathStep(note: 'Determinante de y (los resultados en la columna de y):', math: 'Δy = $a1 × $c2 − ($a2) × ($c1) = $dy'),
      MathStep(note: 'Dividimos cada uno entre Δ:', math: 'x = $dx ÷ $det = $x   ;   y = $dy ÷ $det = $y'),
    ]);
  } else if (a1.isZero || a2.isZero) {
    // Una ecuación no tiene x: da y directo, en cualquier método.
    final (bb, cc) = a1.isZero ? (b1, c1) : (b2, c2);
    steps.add(MathStep(note: 'La ${a1.isZero ? 'primera' : 'segunda'} ecuación no tiene x: despejamos y de ella.', math: 'y = $cc ÷ $bb = $y'));
    steps.add(MathStep(note: 'Reemplazamos y = $y en la otra y despejamos x:', math: 'x = $x'));
  } else {
    // x despejada de cada ecuación: x = p − q·y.
    _Poly xOf(Rational a, Rational b, Rational c) => _Poly({(0, 0): c / a, (0, 1): -b / a});
    final x1 = xOf(a1, b1, c1), x2 = xOf(a2, b2, c2);
    switch (method) {
      case SystemMethod.sustitucion:
        steps.add(MathStep(note: 'Despejamos x de la primera ecuación:', math: 'x = ${x1.show()}'));
        final ky = b2 + a2 * x1.coef(0, 1), m = a2 * x1.coef(0, 0);
        steps.add(MathStep(note: 'Sustituimos esa x en la segunda ecuación:', math: '$a2(${x1.show()}) + ${_Poly({(0, 1): b2}).show()} = $c2'));
        steps.add(MathStep(note: 'Quitamos el paréntesis y agrupamos:', math: '${_Poly({(0, 1): ky, (0, 0): m}).show()} = $c2'));
        steps.add(MathStep(note: 'Despejamos y:', math: 'y = ${c2 - m} ÷ $ky = $y'));
        steps.add(MathStep(note: 'Reemplazamos y = $y en x = ${x1.show()}:', math: 'x = $x'));
      case SystemMethod.igualacion:
        steps.add(MathStep(note: 'Despejamos x de las dos ecuaciones:', math: 'x = ${x1.show()}   ;   x = ${x2.show()}'));
        steps.add(MathStep(note: 'Como las dos valen x, las igualamos:', math: '${x1.show()} = ${x2.show()}'));
        final ky = x1.coef(0, 1) - x2.coef(0, 1), m = x2.coef(0, 0) - x1.coef(0, 0);
        steps.add(MathStep(note: 'Pasamos las y a un lado y los números al otro:', math: '${_Poly({(0, 1): ky}).show()} = $m'));
        steps.add(MathStep(note: 'Despejamos y:', math: 'y = $m ÷ $ky = $y'));
        steps.add(MathStep(note: 'Reemplazamos y = $y en x = ${x1.show()}:', math: 'x = $x'));
      case SystemMethod.reduccion || SystemMethod.cramer:
        steps.add(MathStep(
          note: 'Multiplicamos la primera por $a2 y la segunda por $a1 para igualar los términos en x, y restamos:',
          math: '${_Poly({(0, 1): b1 * a2 - b2 * a1}).show()} = ${c1 * a2 - c2 * a1}',
        ));
        steps.add(MathStep(note: 'Despejamos y:', math: 'y = $y'));
        steps.add(MathStep(note: 'Reemplazamos y = $y en la primera y despejamos x:', math: 'x = $x'));
    }
  }
  return MathSolution(
    kind: kind,
    steps: steps,
    answer: '${_withDecimal('x', x)};  ${_withDecimal('y', y)}',
    answerTex: r'(x,\ y) = \left(' '${texRational(x)}' r',\ ' '${texRational(y)}' r'\right)',
    graph: MathGraph(curves: lines, points: [(x: x.toDouble(), y: y.toDouble(), label: '($x, $y)')]),
    isSystem: true,
  );
}

/// La recta a·x + b·y = c para el gráfico.
MathCurve _line(Rational a, Rational b, Rational c, String label) => b.isZero
    ? MathCurve(verticalX: (c / a).toDouble(), label: label)
    : MathCurve(b: (-a / b).toDouble(), c: (c / b).toDouble(), label: label);

/// Gráfico de y = a·x² + b·x + c con sus raíces y su vértice.
MathGraph _parabola(_Poly all) {
  final a = all.coef(2, 0).toDouble(), b = all.coef(1, 0).toDouble(), c = all.coef(0, 0).toDouble();
  final vx = -b / (2 * a);
  final disc = b * b - 4 * a * c;
  final points = <MathPoint>[(x: vx, y: a * vx * vx + b * vx + c, label: 'vértice')];
  if (disc >= 0) {
    final r = _sqrt(disc);
    for (final x in {(-b + r) / (2 * a), (-b - r) / (2 * a)}) {
      points.add((x: x, y: 0, label: 'x = ${formatDecimal(x, 2)}'));
    }
  }
  return MathGraph(curves: [MathCurve(a: a, b: b, c: c, label: 'y')], points: points);
}

/// Métodos para resolver un sistema de dos ecuaciones.
enum SystemMethod {
  sustitucion('el método de sustitución', 'Sustitución'),
  igualacion('el método de igualación', 'Igualación'),
  reduccion('el método de reducción', 'Reducción'),
  cramer('la regla de Cramer', 'Cramer');

  const SystemMethod(this.label, this.short);
  final String label;
  final String short;
}

// ---------------------------------------------------------------- apoyo

bool _same(_Poly left, _Poly right, List<MathStep> steps) => steps.length == 1 && steps.first.math == '${left.show()} = ${right.show()}';

Rational _eval(_Poly p, Rational x, Rational y) {
  var r = Rational.zero;
  p.terms.forEach((k, c) => r += c * x.pow(k.$1) * y.pow(k.$2));
  return r;
}

String _withDecimal(String name, Rational v) => v.isInteger ? '$name = $v' : '$name = $v ≈ ${v.toDecimal()}';

double _sqrt(double v) {
  var x = v;
  if (x == 0) return 0;
  for (var i = 0; i < 60; i++) {
    x = (x + v / x) / 2;
  }
  return x;
}

/// Pasa los símbolos a palabras para la voz.
String _speakable(String s) => s
    .replaceAll('x²', 'x al cuadrado')
    .replaceAll('y²', 'y al cuadrado')
    .replaceAll('²', ' al cuadrado')
    .replaceAll('±', ' más o menos ')
    .replaceAll('√', ' raíz de ')
    .replaceAll('Δ', ' delta ')
    .replaceAll('≈', ' aproximadamente ')
    .replaceAll('÷', ' entre ')
    .replaceAll('×', ' por ')
    .replaceAll('−', ' menos ')
    .replaceAll('x₁', 'x uno')
    .replaceAll('x₂', 'x dos')
    .replaceAll('=', ' igual a ')
    .replaceAllMapped(RegExp(r'(\d+)/(\d+)'), (m) => '${m[1]} sobre ${m[2]}')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
