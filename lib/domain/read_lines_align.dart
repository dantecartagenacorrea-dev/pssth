import 'scanned_pdf.dart' show ScannedLine;

/// Cuántos renglones del lector común se miran hacia adelante para ubicar uno.
const _lookAhead = 4;
const _sameLine = 0.5;

/// Lo leído por la IA, con el lugar de la hoja que vio el lector común: la IA lee
/// mejor, pero no dice dónde está cada renglón, y hace falta para armar los párrafos
/// y compararlos con la foto. [doubts]: renglones donde los dos lectores no leen las
/// mismas palabras, o sin par: son los que hay que mirar. [guessed]: los sin par, cuyo
/// lugar es solo una estimación.
({List<ScannedLine> lines, Set<int> doubts, Set<int> guessed}) alignReadLines(
  List<String> read,
  List<ScannedLine> scanned,
) {
  final sorted = [...scanned]..sort((a, b) => a.top.compareTo(b.top));
  final lines = <ScannedLine>[];
  final doubts = <int>{};
  final guessed = <int>{};
  var cursor = 0;
  for (final raw in read) {
    final text = raw.trim();
    if (text.isEmpty) continue;
    var best = -1;
    var bestScore = _sameLine;
    for (var j = cursor; j < sorted.length && j < cursor + _lookAhead; j++) {
      final score = lineSimilarity(text, sorted[j].text);
      if (score > bestScore) {
        bestScore = score;
        best = j;
      }
    }
    if (best < 0) {
      doubts.add(lines.length);
      guessed.add(lines.length);
      final last = lines.isEmpty ? null : lines.last;
      final next = cursor < sorted.length ? sorted[cursor] : null;
      final left = last?.left ?? next?.left ?? 0.1;
      final height = last?.height ?? next?.height ?? 0.02;
      lines.add((
        text: text,
        left: left,
        top: last == null ? (next?.top ?? 0.1) : last.top + height,
        width: next?.width ?? last?.width ?? 0.8,
        height: height,
      ));
      continue;
    }
    final at = sorted[best];
    if (!_sameWords(text, at, sorted)) doubts.add(lines.length);
    lines.add((text: text, left: at.left, top: at.top, width: at.width, height: at.height));
    cursor = best + 1;
  }
  return (lines: lines, doubts: doubts, guessed: guessed);
}

/// ¿Dicen lo mismo? El lector común puede partir un renglón en pedazos: también vale
/// si la IA leyó junto lo que él vio lado a lado.
bool _sameWords(String text, ScannedLine at, List<ScannedLine> scanned) {
  if (_readsAlike(text, at.text)) return true;
  final middle = at.top + at.height / 2;
  final row = [
    for (final l in scanned)
      if ((l.top + l.height / 2 - middle).abs() < at.height / 2) l,
  ]..sort((a, b) => a.left.compareTo(b.left));
  return _readsAlike(text, row.map((l) => l.text).join(' '));
}

/// Tildes, espacios, puntuación y mayúsculas los confunde cualquier lector y no cambian
/// la palabra. Lo que sigue siendo distinto hay que mirarlo, salvo los errores típicos
/// del lector común, que señalaban casi todos los renglones sin que la IA cambiara nada.
bool _readsAlike(String read, String seen) {
  final a = _words(read), b = _words(seen);
  if (a.join() == b.join()) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!_wordLooksLike(a[i], b[i])) return false;
  }
  return true;
}

/// La ñ no se quita: «año» no es «ano».
List<String> _words(String text) {
  var plain = text.toLowerCase().replaceAll('|', 'i');
  _withoutMarks.forEach((letter, marked) => plain = plain.replaceAll(RegExp('[$marked]'), letter));
  return plain.split(RegExp(r'[^\p{L}\p{N}]+|[ºª]+', unicode: true)).where((w) => w.isNotEmpty).toList();
}

const _withoutMarks = {'a': 'áàäâãå', 'e': 'éèëêė', 'i': 'íìïî', 'o': 'óòöôõ', 'u': 'úùüû'};

/// ¿Puede el lector común haber visto mal [word]? Confundió letras de trazo parecido,
/// o perdió una de adentro: «contormes», «policla», «feha». Nunca vale para un número,
/// ni si la IA tiene menos letras: entonces fue ella la que sacó algo («OTROS»).
bool _wordLooksLike(String word, String seen) {
  if (word.length == seen.length) {
    for (var i = 0; i < word.length; i++) {
      if (!_sameStroke(word[i], seen[i])) return false;
    }
    return true;
  }
  if (word.length != seen.length + 1 || word.length < _minLostLetter) return false;
  for (var lost = 1; lost < word.length - 1; lost++) {
    if (_isDigit.hasMatch(word[lost])) continue;
    if (_wordLooksLike(word.substring(0, lost) + word.substring(lost + 1), seen)) return true;
  }
  return false;
}

final _isDigit = RegExp(r'\d');
const _minLostLetter = 4;
const _alikeStrokes = {'i': 'l1', 'l': 'i1', 'f': 't', 't': 'f'};

bool _sameStroke(String letter, String seen) => letter == seen || (_alikeStrokes[letter]?.contains(seen) ?? false);

/// De 0 a 1: cuántos pares de letras comparten dos renglones.
double lineSimilarity(String a, String b) {
  Map<String, int> pairs(String s) {
    final t = s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final out = <String, int>{};
    for (var i = 0; i + 1 < t.length; i++) {
      final p = t.substring(i, i + 2);
      out[p] = (out[p] ?? 0) + 1;
    }
    return out;
  }

  final x = pairs(a), y = pairs(b);
  final total = x.values.fold<int>(0, (s, v) => s + v) + y.values.fold<int>(0, (s, v) => s + v);
  if (total == 0) return 0;
  var shared = 0;
  x.forEach((k, v) {
    final other = y[k] ?? 0;
    shared += v < other ? v : other;
  });
  return 2 * shared / total;
}

/// Lo que respondió la IA, en renglones: sin el bloque de código ni los vacíos. Si
/// dice que no ve texto no hay renglones: esa frase no es parte de la hoja.
List<String> linesFromAiText(String text) {
  final lines = [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty && !line.trim().startsWith('```')) line.trim(),
  ];
  return lines.length == 1 && _saysNoText.hasMatch(lines.single) ? const [] : lines;
}

final _saysNoText = RegExp(
  r'^(none\.?|no hay texto.*|no se (ve|lee|encuentra|detecta).*texto.*|.*no (text|contains? (any )?text).*)$',
  caseSensitive: false,
);
