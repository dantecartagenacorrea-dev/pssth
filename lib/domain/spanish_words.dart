import 'dart:typed_data';

import 'scanned_pdf.dart' show ScannedLine;

/// Cuántas posiciones marca cada palabra en la lista: una palabra inventada pasa por
/// buena menos de 1 vez en 10.000.
const _hashes = 14;
const _bitsPerWord = 20;

/// Las palabras del español, sin tildes, en poco lugar y sin descomprimir nada: la
/// lista entera son 8 MB y en la tablet ocuparía mucho más en memoria.
class SpanishWords {
  SpanishWords(this.bytes);

  factory SpanishWords.build(Iterable<String> words) {
    final unique = words.toSet();
    final out = SpanishWords(Uint8List((unique.length * _bitsPerWord / 8).ceil() + 1));
    for (final word in unique) {
      for (final at in out._positions(word)) {
        out.bytes[at >> 3] |= 1 << (at & 7);
      }
    }
    return out;
  }

  final Uint8List bytes;

  bool contains(String word) => _positions(word).every((at) => bytes[at >> 3] & (1 << (at & 7)) != 0);

  Iterable<int> _positions(String word) sync* {
    final first = _hash(word, 0x811c9dc5);
    final step = _hash(word, 0x5bd1e995) | 1;
    final size = bytes.length * 8;
    for (var i = 0; i < _hashes; i++) {
      yield (first + i * step) % size;
    }
  }

  static int _hash(String word, int seed) {
    var h = seed;
    for (final unit in word.codeUnits) {
      h = ((h ^ unit) * 16777619) & 0xffffffff;
    }
    return h;
  }
}

/// Con menos de esta parte de palabras conocidas, la hoja no está en español: no se toca.
const _minKnownShare = 0.6;

/// Lo que leyó el lector común sin IA, revisado contra el diccionario. Arregla una palabra
/// solo si hay una única palabra posible con un error típico de lectura, y entonces el
/// renglón queda en [doubts] para mirarlo; lo que no se puede arreglar también. Los nombres
/// y las siglas no están en ningún diccionario: esos no se revisan. Una palabra mal leída
/// que forma otra palabra válida («de a policía») no se puede ver desde aquí.
({List<ScannedLine> lines, Set<int> doubts}) checkSpelling(List<ScannedLine> lines, SpanishWords words) {
  var known = 0, checked = 0;
  final out = <ScannedLine>[];
  final doubts = <int>{};
  for (final (i, line) in lines.indexed) {
    final cut = i > 0 && lines[i - 1].text.trimRight().endsWith('-');
    var doubtful = false;
    var isFirst = true;
    final source = _tidyPunctuation(line.text);
    final text = source.replaceAllMapped(_token, (m) {
      final first = isFirst;
      isFirst = false;
      final word = m[0]!;
      final after = source.substring(m.end);
      if (!_isCheckable(word, after) || (first && cut)) return word;
      checked++;
      final plain = plainWord(word);
      if (words.contains(plain)) {
        known++;
        return _tidy(word, first);
      }
      doubtful = true;
      final fixed = _onlyChoice(_candidates(plain).where(words.contains).toSet());
      if (fixed == null) return word;
      return first && _isUpper(word[0]) ? fixed[0].toUpperCase() + fixed.substring(1) : fixed;
    });
    if (doubtful) doubts.add(i);
    out.add((text: text, left: line.left, top: line.top, width: line.width, height: line.height));
  }
  if (checked == 0 || known / checked < _minKnownShare) return (lines: lines, doubts: const {});
  return (lines: out, doubts: doubts);
}

/// Una sola palabra posible, o una sola de las de todos los días: «gue» también podría
/// ser otra, pero es «que».
String? _onlyChoice(Set<String> found) {
  if (found.length == 1) return found.single;
  final common = found.where(_everyday.contains);
  return common.length == 1 ? common.single : null;
}

const _everyday = {
  'a',
  'al',
  'con',
  'de',
  'del',
  'el',
  'en',
  'es',
  'fue',
  'la',
  'las',
  'lo',
  'los',
  'mi',
  'no',
  'para',
  'por',
  'que',
  'se',
  'su',
  'una',
  'y',
};

/// Lo que una arruga o el lector agregan: «otros,entre», «, ,», «OTROSI'2°», «Art 285», «sustraer-las».
String _tidyPunctuation(String text) => text
    .replaceAllMapped(_commaInside, (m) => '${m[1]}, ')
    .replaceAll(_doubleComma, ',')
    .replaceAllMapped(_markBeforeNumber, (m) => '${m[1]} ')
    .replaceAllMapped(_articleNoDot, (m) => '${m[1]}. ')
    .replaceAllMapped(_dashBeforeSmallWord, (m) => '${m[1]} ${m[2]}');

final _commaInside = RegExp(r'(\p{L}{3,}),(?=\p{L})', unicode: true);
final _doubleComma = RegExp(r',\s*,');
final _markBeforeNumber = RegExp(r"(\p{L})'(?=\d)", unicode: true);
final _articleNoDot = RegExp(r'\b([Aa]rt) (?=\d)');
final _dashBeforeSmallWord = RegExp(r'(\p{L}{3,})-(las|los|la|lo|el|de|del|en|con|que|por|y|a)(?=\s|$)', unicode: true);

final _token = RegExp(r'[\p{L}\p{N}|]+', unicode: true);
final _anyLower = RegExp(r'\p{Ll}', unicode: true);
final _digit = RegExp(r'\d');
const _maxAbbreviation = 4;

/// Una sigla, un nombre, un número o «núm.» no se revisan.
bool _isCheckable(String word, String after) {
  if (word.runes.length < 2 || !_anyLower.hasMatch(word)) return false;
  if (_digit.allMatches(word).length > 1) return false;
  if (after.startsWith('.') && word.length <= _maxAbbreviation) return false;
  if (after.trimRight() == '-') return false;
  return !_isProperName(word);
}

bool _isProperName(String word) => _isUpper(word[0]) && word.substring(1) == word.substring(1).toLowerCase();

bool _isUpper(String letter) => letter != letter.toLowerCase();

/// «estoS» es «estos», y una letra con una marca que el español no usa es la de la tilde.
String _tidy(String word, bool first) {
  final out = _ourLetters(word);
  final rest = out.substring(1);
  if (rest == rest.toLowerCase()) return out;
  return first && _isUpper(out[0]) ? out[0] + rest.toLowerCase() : out.toLowerCase();
}

const _foreignMarks = {'á': 'àäâã', 'é': 'èëê', 'í': 'ìïî', 'ó': 'òöôõ', 'ú': 'ùû'};
const _otherAlphabets = {
  'a': 'āą',
  'c': 'ćĉč',
  'e': 'ėęě',
  'g': 'ğ',
  'i': 'ı',
  'l': 'ł',
  'n': 'ńň',
  'o': 'ōő',
  'r': 'ř',
  's': 'şš',
  't': 'ţť',
  'u': 'ūű',
  'z': 'žź',
};
const _withoutTilde = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};

/// En minúsculas y sin tildes, como está la lista. La ñ no se quita: «año» no es «ano».
String plainWord(String word) {
  var out = _ourLetters(word.toLowerCase());
  _withoutTilde.forEach((tilde, plain) => out = out.replaceAll(tilde, plain));
  return out;
}

String _ourLetters(String word) {
  var out = word;
  for (final table in [_foreignMarks, _otherAlphabets]) {
    table.forEach((ours, others) => out = out.replaceAll(RegExp('[$others]'), ours));
  }
  return out;
}

/// Lo que pudo haber sido cada letra que vio el lector común.
const _couldBe = {
  'i': 'l',
  'l': 'it',
  't': 'fl',
  'f': 't',
  'c': 'dse',
  'd': 'c',
  'e': 'c',
  'n': 'mu',
  'm': 'n',
  'u': 'nv',
  'v': 'u',
  'h': 'b',
  'b': 'h',
  's': 'c',
  'g': 'q',
  'q': 'g',
  'o': 'c',
  '|': 'il',
  '0': 'o',
  '1': 'il',
};
const _joined = {'rn': 'm', 'm': 'rn', 'cl': 'd', 'd': 'cl'};
const _oftenLost = 'cilrteu';

/// Una raya de la arruga junto a la palabra se lee como una de estas.
const _strayStart = 'jli|1';
const _minWithStray = 4;

Set<String> _candidates(String word) {
  final out = <String>{if (word.length >= _minWithStray && _strayStart.contains(word[0])) word.substring(1)};
  for (var i = 0; i < word.length; i++) {
    final head = word.substring(0, i);
    for (final other in (_couldBe[word[i]] ?? '').split('')) {
      out.add('$head$other${word.substring(i + 1)}');
    }
    _joined.forEach((seen, real) {
      if (word.startsWith(seen, i)) out.add('$head$real${word.substring(i + seen.length)}');
    });
    if (i > 0 && word[i] == word[i - 1]) out.add('$head${word.substring(i + 1)}');
    if (i > 0 && word.length >= 3) {
      for (final lost in _oftenLost.split('')) {
        out.add('$head$lost${word.substring(i)}');
      }
    }
  }
  return out..remove(word);
}
