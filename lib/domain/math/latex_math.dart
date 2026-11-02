import 'rational.dart' show MathError;

/// Lo que el modelo de fórmulas produce (números de su vocabulario) en texto
/// LaTeX: «\frac { 3 } { 4 }».
String decodeFormulaTokens(List<int> ids, List<String> vocabulary) {
  final out = StringBuffer();
  for (final id in ids) {
    if (id < 5 || id >= vocabulary.length) continue; // <pad>, <s>, </s>, <unk>, <mask>
    out.write(vocabulary[id]);
  }
  return out.toString().replaceAll('Ġ', ' ').replaceAll('Ċ', ' ').trim();
}

/// El vocabulario ordenado por número, a partir del «model.vocab» de tokenizer.json.
List<String> vocabularyFrom(Map<String, dynamic> vocab) {
  final size = vocab.values.cast<int>().fold<int>(0, (m, v) => v >= m ? v + 1 : m);
  final out = List<String>.filled(size, '');
  vocab.forEach((token, id) => out[id as int] = token);
  return out;
}

/// Un número solo, leído por el modelo: «\\mathbf { 2 5 }», «\\bf { S O }». null
/// si no es solo un número.
String? numberFromLatex(String latex) {
  const swaps = {'O': '0', 'o': '0', 'l': '1', 'I': '1', '|': '1', 'S': '5', 's': '5', 'Z': '2', 'z': '2'};
  final bare = latex.replaceAll(RegExp(r'\\[a-zA-Z]+'), '').replaceAll(RegExp(r'[\s{}^_~]'), '');
  final digits = bare.split('').map((c) => swaps[c] ?? c).join();
  return RegExp(r'^\d{1,6}$').hasMatch(digits) ? digits : null;
}

/// LaTeX en el texto que entiende la calculadora: \frac{3}{4} + 1 → 3/4+1. null
/// si trae algo que no se sabe hacer: mejor no resolver que resolver otra cosa.
String? latexToPlain(String latex) {
  try {
    final plain = _Latex(latex).sequence().trim();
    if (plain.isEmpty) return null;
    // Los paréntesis de las fracciones solo hacen falta si hay ×, ÷ o potencias.
    return plain.contains(RegExp(r'[×÷^]'))
        ? plain
        : plain.replaceAllMapped(RegExp(r'\((\d+)/(\d+)\)'), (m) => '${m[1]}/${m[2]}');
  } on MathError {
    return null;
  }
}

class _Latex {
  _Latex(this.s);
  final String s;
  int pos = 0;

  static const _unknown = MathError('LaTeX desconocido');
  static const _wrappers = {
    'operatorname',
    'mathrm',
    'mathbf',
    'mathit',
    'mathsf',
    'text',
    'textbf',
    'boldsymbol',
    'bm',
  };
  static const _spaces = {'quad', 'qquad', 'left', 'right', 'displaystyle', 'textstyle', 'limits'};
  static const _signs = {'times': '×', 'cdot': '×', 'ast': '×', 'div': '÷', 'pi': 'π', 'lbrack': '(', 'rbrack': ')'};
  static const _functions = {
    'sin': 'sen',
    'sen': 'sen',
    'cos': 'cos',
    'tan': 'tan',
    'tg': 'tan',
    'ln': 'ln',
    'log': 'log',
  };

  bool get _atEnd => pos >= s.length;

  void _skipSpaces() {
    while (!_atEnd && s[pos] == ' ') {
      pos++;
    }
  }

  /// Lee hasta el final o hasta la llave que cierra el grupo actual.
  String sequence() {
    final out = StringBuffer();
    while (true) {
      _skipSpaces();
      if (_atEnd) return out.toString();
      final c = s[pos];
      if (c == '}') return out.toString();
      if (c == '{') {
        out.write(_group());
      } else if (c == '\\') {
        final piece = _command(out.toString());
        if (piece.replaces) out.clear();
        out.write(piece.text);
      } else if (c == '^') {
        pos++;
        final exponent = _argument();
        out.write(RegExp(r'^[\w.]+$').hasMatch(exponent) ? '^$exponent' : '^($exponent)');
      } else if (c == '~') {
        pos++;
      } else if (RegExp(r'[0-9a-zA-Z+\-=()/,.|*%:]').hasMatch(c)) {
        out.write(c);
        pos++;
      } else {
        throw _unknown;
      }
    }
  }

  String _group() {
    if (s[pos] != '{') throw _unknown;
    pos++;
    final inner = sequence();
    if (_atEnd || s[pos] != '}') throw _unknown;
    pos++;
    return inner;
  }

  /// Lo que sigue a un comando: un grupo, otro comando o un solo carácter.
  String _argument() {
    _skipSpaces();
    if (_atEnd) throw _unknown;
    if (s[pos] == '{') return _group();
    if (s[pos] == '\\') return _command('').text;
    return s[pos++];
  }

  ({String text, bool replaces}) _command(String before) {
    pos++; // la barra
    if (_atEnd) throw _unknown;
    final m = RegExp(r'[a-zA-Z]+').matchAsPrefix(s, pos);
    if (m == null) {
      final c = s[pos++];
      if (c == '%') return (text: '%', replaces: false);
      if (c == '{') return (text: '(', replaces: false);
      if (c == '}') return (text: ')', replaces: false);
      if (const {',', ':', ';', '!', ' '}.contains(c)) return (text: '', replaces: false);
      throw _unknown;
    }
    pos = m.end;
    final name = m[0]!;
    if (_spaces.contains(name)) return (text: '', replaces: false);
    if (_wrappers.contains(name)) return (text: _argument(), replaces: false);
    if (_signs[name] case final sign?) return (text: sign, replaces: false);
    if (_functions[name] case final fn?) return (text: _function(fn), replaces: false);
    if (name == 'sqrt') {
      _skipSpaces();
      if (!_atEnd && s[pos] == '[') throw _unknown; // raíz cúbica y demás
      return (text: '√(${_argument()})', replaces: false);
    }
    if (name == 'frac' || name == 'dfrac' || name == 'tfrac') {
      return _fraction(_argument(), _argument(), before);
    }
    if (name == 'begin') return _array(before);
    throw _unknown;
  }

  String _function(String name) {
    _skipSpaces();
    if (!_atEnd && s[pos] == '(') return name; // el paréntesis viene escrito
    final argument = _argument();
    return '$name($argument)';
  }

  /// Un entero pegado a una fracción es un número mixto: 2 ½ es 2 + ½.
  ({String text, bool replaces}) _fraction(String top, String bottom, String before) {
    String part(String p) => RegExp(r'^[\w.,]+$').hasMatch(p) ? p : '($p)';
    final fraction = '${part(top)}/${part(bottom)}';
    final whole = RegExp(r'^(.*?)(\d+)$').firstMatch(before);
    if (whole != null) return (text: '${whole[1]}(${whole[2]}+$fraction)', replaces: true);
    return (text: '($fraction)', replaces: false);
  }

  /// La fracción que a veces escribe como tabla: {a} \\ \hline {b}.
  ({String text, bool replaces}) _array(String before) {
    if (_group() != 'array') throw _unknown;
    _skipSpaces();
    if (_atEnd || s[pos] != '{') throw _unknown;
    _skipRawGroup();
    final end = s.indexOf(r'\end', pos);
    if (end < 0) throw _unknown;
    final body = s.substring(pos, end);
    pos = end + 4;
    _skipSpaces();
    _skipRawGroup();
    final hasLine = body.contains(r'\hline');
    final rows = [
      for (final row in body.replaceAll(r'\hline', '').split(r'\\'))
        if (row.trim().isNotEmpty) row,
    ];
    final parsed = rows.map((r) => _Latex(r).sequence()).toList();
    if (parsed.length == 1) return (text: parsed.single, replaces: false);
    if (parsed.length == 2 && hasLine) return _fraction(parsed[0], parsed[1], before);
    throw _unknown;
  }

  void _skipRawGroup() {
    if (_atEnd || s[pos] != '{') throw _unknown;
    final close = s.indexOf('}', pos);
    if (close < 0) throw _unknown;
    pos = close + 1;
  }
}
