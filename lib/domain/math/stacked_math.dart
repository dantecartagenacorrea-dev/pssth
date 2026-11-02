import 'dart:math' as math;

import '../scanned_pdf.dart' show ScannedLine;

/// Una fracción de libro se lee como renglones sueltos («3 1», «+ =», «4 2»).
/// Con dónde está cada renglón se arma la cuenta: «3/4 + 1/2 =». null si la
/// foto no es eso.
String? stackedMath(List<ScannedLine> lines) {
  final tokens = <_Token>[
    for (final line in lines)
      if (line.text.trim().isNotEmpty) ..._split(line),
  ];
  if (tokens.isEmpty || tokens.any((t) => !RegExp(r'^(\d+|[-−–—_+×÷*=()xX])$').hasMatch(t.text))) return null;

  final rows = _rows(tokens);
  if (rows.length < 2 || rows.length > 3) return null;
  final top = rows.first, bottom = rows.last;
  if (top.length != bottom.length || !top.every(_isNumber) || !bottom.every(_isNumber)) return null;

  final parts = <({double x, String text})>[
    for (var i = 0; i < top.length; i++) (x: (top[i].x + bottom[i].x) / 2, text: '${top[i].text}/${bottom[i].text}'),
  ];
  final near = _charWidth(tokens) * 1.5;
  if (rows.length == 3) {
    for (final t in rows[1]) {
      // La raya de la fracción a veces se lee como un guion: no es una resta.
      final isBar =
          RegExp(r'^[-−–—_]$').hasMatch(t.text) && parts.any((p) => (p.x - t.x).abs() < near && p.text.contains('/'));
      if (!isBar) parts.add((x: t.x, text: t.text));
    }
  }
  parts.sort((a, b) => a.x.compareTo(b.x));
  final needsParens = parts.any((p) => _breaksFractions(p.text));
  return parts.map((p) => needsParens && p.text.contains('/') ? '(${p.text})' : p.text).join(' ');
}

/// Una fracción ya leída y dónde está, en fracciones de la imagen.
typedef ReadFraction = ({String text, double left, double right, double top, double bottom});

/// Junta las fracciones leídas con los signos que hay entre ellas ([lines]: lo
/// que el lector vio en la foto). null si falta un signo entre dos fracciones:
/// sin saber cuál es, no se puede hacer la cuenta.
String? assembleFractions(List<ReadFraction> fractions, List<ScannedLine> lines) {
  if (fractions.isEmpty) return null;
  final top = fractions.map((f) => f.top).reduce(math.min);
  final bottom = fractions.map((f) => f.bottom).reduce(math.max);
  final parts = <({double x, String text})>[
    for (final f in fractions) (x: (f.left + f.right) / 2, text: f.text),
    for (final line in lines)
      if (line.text.trim().isNotEmpty)
        for (final t in _split(line))
          if (t.y >= top && t.y <= bottom && RegExp(r'^(\d+|[-−–+×÷*=()xX:])$').hasMatch(t.text))
            if (!fractions.any((f) => t.x >= f.left && t.x <= f.right)) (x: t.x, text: t.text),
  ]..sort((a, b) => a.x.compareTo(b.x));
  for (var i = 1; i < parts.length; i++) {
    if (parts[i - 1].text.contains('/') && parts[i].text.contains('/')) return null;
  }
  final needsParens = parts.any((p) => _breaksFractions(p.text));
  return parts.map((p) => needsParens && p.text.contains('/') ? '(${p.text})' : p.text).join(' ');
}

/// 1/2 ÷ 3/4 y 2/3 × 3/5 son dos fracciones, no una cuenta de izquierda a derecha.
bool _breaksFractions(String sign) => const {'÷', ':', '×', '*', 'x', 'X'}.contains(sign);

class _Token {
  const _Token(this.text, this.x, this.y, this.height);
  final String text;
  final double x, y, height;
}

bool _isNumber(_Token t) => RegExp(r'^\d+$').hasMatch(t.text);

/// Cada número o signo de un renglón, con su lugar aproximado.
List<_Token> _split(ScannedLine line) {
  final text = line.text.trim();
  final y = line.top + line.height / 2;
  final out = <_Token>[];
  for (final m in RegExp(r'\d+|\S').allMatches(text)) {
    final middle = (m.start + m.end) / 2 / math.max(text.length, 1);
    out.add(_Token(m[0]!, line.left + line.width * middle, y, line.height));
  }
  return out;
}

/// Agrupa por altura, de arriba abajo, y cada fila de izquierda a derecha.
List<List<_Token>> _rows(List<_Token> tokens) {
  final sorted = [...tokens]..sort((a, b) => a.y.compareTo(b.y));
  final rows = <List<_Token>>[];
  for (final t in sorted) {
    if (rows.isNotEmpty && (t.y - rows.last.first.y).abs() < t.height * 0.5) {
      rows.last.add(t);
    } else {
      rows.add([t]);
    }
  }
  for (final row in rows) {
    row.sort((a, b) => a.x.compareTo(b.x));
  }
  return rows;
}

double _charWidth(List<_Token> tokens) => tokens.map((t) => t.height).reduce(math.max) * 0.6;
