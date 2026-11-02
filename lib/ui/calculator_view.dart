import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../domain/math/expr.dart' show texRational;
import '../domain/math/formula.dart';
import '../domain/math/rational.dart';
import '../domain/math/solver.dart' show previewLatex;

/// Calculadora científica: se escribe con sus propias teclas, muestra el
/// resultado mientras se escribe y guarda las últimas cuentas para reusarlas.
class CalculatorView extends StatefulWidget {
  const CalculatorView({super.key});

  @override
  State<CalculatorView> createState() => _CalculatorViewState();
}

/// Una tecla: lo que muestra, lo que escribe y cómo la nombra el lector de
/// pantalla (si no se entiende con lo que muestra).
typedef _Key = ({String label, String insert, String? spoken});

class _CalculatorViewState extends State<CalculatorView> {
  static const _maxHistory = 20;
  static const _operators = {'+', '−', '×', '÷', '/', '^', '%', '!'};
  static final _lastToken = RegExp(r'(arcsen\(|arccos\(|arctan\(|sen\(|cos\(|tan\(|ln\(|log\(|√\(|Ans)$');

  final _text = TextEditingController();
  final _history = <({String expression, String result})>[];
  bool _degrees = true;
  bool _inverse = false;
  double _ans = 0;
  Rational? _ansExact;
  bool _ansIsFraction = false;
  String? _error;

  /// Lo que se pidió con la tecla de cambiar; null: según cómo se escribió.
  bool? _fractionChoice;

  /// Recién se dio «=»: un número empieza otra cuenta; un operador sigue con
  /// el resultado.
  bool _answered = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _insert(String value) {
    setState(() {
      _error = null;
      _fractionChoice = null;
      var text = _text.text;
      var sel = _text.selection;
      if (_answered) {
        text = _operators.contains(value) ? 'Ans' : '';
        sel = TextSelection.collapsed(offset: text.length);
        _answered = false;
      }
      final start = sel.isValid ? sel.start : text.length;
      final end = sel.isValid ? sel.end : text.length;
      _text.value = TextEditingValue(
        text: text.replaceRange(start, end, value),
        selection: TextSelection.collapsed(offset: start + value.length),
      );
      _inverse = false;
    });
  }

  void _delete() {
    setState(() {
      _error = null;
      _fractionChoice = null;
      _answered = false;
      final sel = _text.selection;
      final text = _text.text;
      final start = sel.isValid ? sel.start : text.length;
      final end = sel.isValid ? sel.end : text.length;
      if (start != end) {
        _setText(text.replaceRange(start, end, ''), start);
        return;
      }
      if (start == 0) return;
      // «sen(» se borra entero, no letra por letra.
      final before = text.substring(0, start);
      final size = _lastToken.firstMatch(before)?[0]?.length ?? 1;
      _setText(text.replaceRange(start - size, start, ''), start - size);
    });
  }

  void _setText(String text, int cursor) {
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }

  void _clear() => setState(() {
    _text.clear();
    _error = null;
    _fractionChoice = null;
    _answered = false;
  });

  /// Con «/» se trabaja en fracciones; con «÷» o una coma, en decimales. La
  /// tecla de cambiar manda sobre esto.
  bool get _wantsFraction {
    if (_fractionChoice case final choice?) return choice;
    final text = _text.text;
    if (text.contains(',')) return false;
    return text.contains('/') || (text.contains('Ans') && _ansIsFraction);
  }

  /// La fracción para mostrar: nada si es entera o demasiado larga para leerla.
  Rational? _fractionFor(double value, Rational? exact) {
    final r = exact ?? nearFraction(value);
    const maxDigits = 12;
    if (r == null || r.isInteger) return null;
    return r.num.abs().toString().length > maxDigits || r.den.toString().length > maxDigits ? null : r;
  }

  /// Cambia entre fracción y decimal lo que está en pantalla.
  void _toggleFraction() {
    setState(() {
      _error = null;
      _fractionChoice = !_wantsFraction;
      if (_answered && _history.isNotEmpty) {
        final fraction = _fractionChoice! ? _fractionFor(_ans, _ansExact) : null;
        final result = fraction?.toString() ?? formatNumber(_ans);
        _history[0] = (expression: _history[0].expression, result: result.replaceAll('-', '−'));
        _text.text = result.contains('×') ? 'Ans' : result.replaceAll('−', '-');
        _text.selection = TextSelection.collapsed(offset: _text.text.length);
      }
    });
  }

  /// El número mixto se escribe como 2 1/3: un espacio tras la parte entera.
  void _insertMixed() {
    if (_answered || !RegExp(r'\d$').hasMatch(_text.text)) return;
    _insert(' ');
  }

  double _evaluate() {
    final formula = parseFormula(_text.text, degrees: _degrees, ans: _ans);
    if (formula.usesX) throw const MathError('Aquí no se usa x: para eso están Resolver y Graficar.');
    return formula.at();
  }

  void _equals() {
    final typed = _text.text;
    if (typed.trim().isEmpty) return;
    // En las últimas cuentas se ve completa: «sen(30» fue «sen(30)».
    final open = '('.allMatches(typed).length - ')'.allMatches(typed).length;
    final expression = typed + ')' * (open > 0 ? open : 0);
    setState(() {
      try {
        final value = _evaluate();
        if (value.isNaN) {
          _error = 'Esa cuenta no tiene resultado.';
        } else if (value.isInfinite) {
          _error = 'El resultado es infinito o demasiado grande.';
        } else {
          final exact = exactValue(typed, ans: _ansExact);
          final fraction = _wantsFraction ? _fractionFor(value, exact) : null;
          final result = fraction?.toString().replaceAll('-', '−') ?? formatNumber(value);
          _ans = value;
          _ansExact = exact ?? (_wantsFraction ? nearFraction(value) : null);
          _ansIsFraction = fraction != null;
          _history.insert(0, (expression: expression, result: result));
          if (_history.length > _maxHistory) _history.removeLast();
          _text.text = result.contains('×') ? 'Ans' : result.replaceAll('−', '-');
          _text.selection = TextSelection.collapsed(offset: _text.text.length);
          _answered = true;
          _error = null;
        }
      } on MathError catch (e) {
        _error = e.message;
      }
    });
  }

  /// El resultado que se ve: mientras se escribe (nada si la cuenta aún no
  /// está completa) o el de la última cuenta.
  ({double value, Rational? exact})? get _shown {
    if (_answered) return (value: _ans, exact: _ansExact);
    if (_text.text.trim().isEmpty) return null;
    try {
      final value = _evaluate();
      return value.isFinite ? (value: value, exact: exactValue(_text.text, ans: _ansExact)) : null;
    } on MathError {
      return null;
    }
  }

  List<List<_Key>> get _scientific {
    _Key fn(String label, String spoken) => (label: label, insert: '$label(', spoken: spoken);
    return [
      [
        if (_inverse) ...[
          fn('arcsen', 'arco seno'),
          fn('arccos', 'arco coseno'),
          fn('arctan', 'arco tangente'),
        ] else ...[
          fn('sen', 'seno'),
          fn('cos', 'coseno'),
          fn('tan', 'tangente'),
        ],
        (label: '^', insert: '^', spoken: 'elevado a'),
      ],
      [
        if (_inverse) ...[
          (label: 'eˣ', insert: 'e^', spoken: 'e elevado a'),
          (label: '10ˣ', insert: '10^', spoken: 'diez elevado a'),
        ] else ...[
          fn('ln', 'logaritmo natural'),
          fn('log', 'logaritmo'),
        ],
        (label: '√', insert: '√(', spoken: 'raíz cuadrada'),
        (label: 'x²', insert: '^2', spoken: 'al cuadrado'),
      ],
      [
        (label: 'π', insert: 'π', spoken: 'pi'),
        (label: 'e', insert: 'e', spoken: null),
        (label: '%', insert: '%', spoken: 'por ciento'),
        (label: '!', insert: '!', spoken: 'factorial'),
      ],
    ];
  }

  static const List<List<_Key>> _numbers = [
    [
      (label: '7', insert: '7', spoken: null),
      (label: '8', insert: '8', spoken: null),
      (label: '9', insert: '9', spoken: null),
      (label: '÷', insert: '÷', spoken: 'entre'),
    ],
    [
      (label: '4', insert: '4', spoken: null),
      (label: '5', insert: '5', spoken: null),
      (label: '6', insert: '6', spoken: null),
      (label: '×', insert: '×', spoken: 'por'),
    ],
    [
      (label: '1', insert: '1', spoken: null),
      (label: '2', insert: '2', spoken: null),
      (label: '3', insert: '3', spoken: null),
      (label: '−', insert: '−', spoken: 'menos'),
    ],
    [
      (label: '0', insert: '0', spoken: null),
      (label: ',', insert: ',', spoken: 'coma'),
      (label: 'Ans', insert: 'Ans', spoken: 'el último resultado'),
      (label: '+', insert: '+', spoken: 'más'),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > c.maxHeight * 1.1;
        final scientific = Column(
          children: [
            _row([
              _KeyButton(
                label: _degrees ? 'Grados' : 'Radianes',
                spoken: _degrees ? 'En grados. Cambiar a radianes' : 'En radianes. Cambiar a grados',
                tone: _Tone.function,
                onTap: () => setState(() => _degrees = !_degrees),
              ),
              _KeyButton(
                label: 'Inv',
                spoken: 'Funciones inversas',
                tone: _inverse ? _Tone.accent : _Tone.function,
                onTap: () => setState(() => _inverse = !_inverse),
              ),
              _KeyButton(label: '(', tone: _Tone.function, onTap: () => _insert('(')),
              _KeyButton(label: ')', tone: _Tone.function, onTap: () => _insert(')')),
            ]),
            for (final row in _scientific) _keys(row, _Tone.function),
            _row([
              _KeyButton(label: 'a/b', spoken: 'Fracción', tone: _Tone.function, onTap: () => _insert('/')),
              _KeyButton(label: 'a b/c', spoken: 'Número mixto', tone: _Tone.function, onTap: _insertMixed),
              _KeyButton(
                label: _wantsFraction ? 'Ver decimal' : 'Ver fracción',
                tone: _Tone.function,
                flex: 2,
                onTap: _toggleFraction,
              ),
            ]),
          ],
        );
        final numbers = Column(
          children: [
            for (final row in _numbers) _keys(row, _Tone.number),
            _row([
              _KeyButton(label: 'AC', spoken: 'Borrar todo', tone: _Tone.function, onTap: _clear),
              _KeyButton(icon: CupertinoIcons.delete_left, spoken: 'Borrar', tone: _Tone.function, onTap: _delete),
              _KeyButton(label: '=', spoken: 'Igual', tone: _Tone.accent, flex: 2, onTap: _equals),
            ]),
          ],
        );
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 1000 : 620),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                children: [
                  Expanded(flex: wide ? 4 : 2, child: _display(context)),
                  const SizedBox(height: 8),
                  Expanded(
                    flex: 7,
                    child: wide
                        ? Row(
                            children: [
                              Expanded(child: scientific),
                              const SizedBox(width: 12),
                              Expanded(child: numbers),
                            ],
                          )
                        : Column(
                            children: [
                              Expanded(child: scientific),
                              const SizedBox(height: 8),
                              Expanded(child: numbers),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _keys(List<_Key> row, _Tone tone) => _row([
    for (final k in row)
      _KeyButton(
        label: k.label,
        spoken: k.spoken,
        tone: _operators.contains(k.insert) && tone == _Tone.number ? _Tone.function : tone,
        onTap: () => _insert(k.insert),
      ),
  ]);

  Widget _row(List<Widget> keys) => Expanded(child: Row(children: keys));

  static const _resultHeight = 54.0;

  /// El resultado: con fracciones, apiladas como en el cuaderno, con su número
  /// mixto y su decimal; si no, el número y ya.
  Widget _resultLine(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final dim = scheme.onSurface.withValues(alpha: 0.7);
    Widget text(String s, TextStyle? style) => Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(s, textAlign: TextAlign.end, maxLines: 2, overflow: TextOverflow.ellipsis, style: style),
      ),
    );

    final error = _error;
    if (error != null) return text(error, t.bodyMedium?.copyWith(color: scheme.error));
    final shown = _shown;
    if (shown == null) return text(' ', t.titleMedium);
    final fraction = _wantsFraction ? _fractionFor(shown.value, shown.exact) : null;
    if (fraction == null) {
      final isWhole = (shown.exact ?? nearFraction(shown.value))?.isInteger ?? false;
      final note = _fractionChoice == true && !isWhole ? '  (no es una fracción exacta)' : '';
      return text('= ${formatNumber(shown.value)}$note', t.titleMedium?.copyWith(color: dim));
    }
    final parts = mixedParts(fraction);
    final sign = fraction.isNegative ? '-' : '';
    final mixed = parts == null ? '' : '= $sign${parts.$1}${texRational(parts.$2)}';
    final typed = _answered ? null : previewLatex(expandMixedNumbers(_text.text));
    final rounded = formatDecimal(shown.value, 6);
    // 7/2 es 3,5 justo; 5/6 solo se acerca a 0,833333.
    final isExact = (double.parse(rounded.replaceAll(',', '.')) - shown.value).abs() < 1e-12;
    final decimal = '${isExact ? '=' : r'\approx'} ${rounded.replaceAll(',', '{,}')}';
    final tex = '${typed ?? ''} = ${texRational(fraction)} $mixed $decimal';
    final say = '${fraction.isNegative ? 'menos ' : ''}${fraction.num.abs()} sobre ${fraction.den}';
    return Semantics(
      liveRegion: true,
      label: '= $say',
      excludeSemantics: true,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Math.tex(
              tex,
              textStyle: TextStyle(fontSize: 22, color: scheme.onSurface),
              onErrorFallback: (_) => Text('= $fraction', style: t.titleMedium),
            ),
          ),
        ),
      ),
    );
  }

  Widget _display(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Las últimas cuentas: tocar una trae su resultado.
        Expanded(
          child: ListView(
            reverse: true,
            padding: EdgeInsets.zero,
            children: [
              for (final h in _history)
                InkWell(
                  onTap: () => _insert(switch (h.result) {
                    final r when r.contains('×') => h.expression,
                    final r when r.contains('/') => '(${r.replaceAll('−', '-')})',
                    final r => r.replaceAll('−', '-'),
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Text(
                      '${h.expression} = ${h.result}',
                      textAlign: TextAlign.end,
                      style: t.bodyMedium?.copyWith(color: scheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        TextField(
          controller: _text,
          readOnly: true, // se escribe con las teclas de aquí, no con las del sistema
          showCursor: true,
          autofocus: true,
          textAlign: TextAlign.end,
          style: t.headlineMedium,
          decoration: const InputDecoration(
            isDense: true,
            hintText: '0',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
        ),
        // Siempre del mismo alto, así las teclas no saltan al escribir.
        SizedBox(height: _resultHeight, child: _resultLine(context)),
      ],
    );
  }
}

enum _Tone { number, function, accent }

class _KeyButton extends StatelessWidget {
  const _KeyButton({this.label, this.icon, this.spoken, required this.tone, this.flex = 1, required this.onTap});

  final String? label;
  final IconData? icon;
  final String? spoken;
  final _Tone tone;
  final int flex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      _Tone.number => (scheme.surfaceContainerHigh, scheme.onSurface),
      _Tone.function => (scheme.surfaceContainerLow, scheme.onSurface),
      _Tone.accent => (scheme.primary, scheme.onPrimary),
    };
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Semantics(
          button: true,
          label: spoken ?? label,
          excludeSemantics: true,
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: icon != null
                        ? Icon(icon, color: foreground, size: 22)
                        : Text(
                            label ?? '',
                            maxLines: 1,
                            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
                            style: TextStyle(color: foreground, fontSize: 20, fontWeight: FontWeight.w500),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
