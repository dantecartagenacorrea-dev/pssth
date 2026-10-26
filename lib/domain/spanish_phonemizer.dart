import 'spanish_numbers.dart';

/// Texto en español -> fonemas IPA al estilo de espeak-ng `es`, que es lo que
/// el modelo Kokoro aprendió. Sustituye a espeak-ng (GPL) desde sherpa-onnx 2.0.
///
/// Devuelve una cadena por frase (el modelo tiene un límite de longitud).
/// [seseo]: z y ce/ci como "s" (latino); false = "θ" (España).
List<String> phonemizeSpanish(String text, {bool seseo = true}) {
  final limpio = _limpiar(numbersToWords(text));
  final out = <String>[];
  for (final m in RegExp(r'[^.!?]+[.!?]*').allMatches(limpio)) {
    final frase = _frase(m[0]!.trim(), seseo);
    if (frase.isNotEmpty) out.add(frase);
  }
  return out;
}

const _vocales = 'aeiouáéíóúü';
const _fuertes = 'aeoáéíóú'; // una débil con tilde se comporta como fuerte (hiato)
const _sinTilde = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};
const _nasales = {'m', 'n', 'ɲ', 'ŋ'};
const _atonas = {
  'el', 'la', 'los', 'las', 'lo', 'un', 'una', 'unos', 'unas', 'de', 'del', 'al', 'a', 'en', 'y', 'e', 'o', 'u',
  'que', 'se', 'me', 'te', 'le', 'les', 'nos', 'os', 'mi', 'mis', 'tu', 'tus', 'su', 'sus', 'con', 'por', 'para',
  'sin', 'si', 'ni', 'pero', 'como', 'cuando', 'donde',
};
// Palabras con x que suena como j.
const _xJota = {'méxico', 'mexico', 'mexicano', 'mexicana', 'mexicanos', 'mexicanas', 'oaxaca', 'texas'};
const _letras = {
  'a': 'a', 'b': 'be', 'c': 'ce', 'd': 'de', 'e': 'e', 'f': 'efe', 'g': 'ge', 'h': 'hache', 'i': 'i', 'j': 'jota',
  'k': 'ka', 'l': 'ele', 'm': 'eme', 'n': 'ene', 'ñ': 'eñe', 'o': 'o', 'p': 'pe', 'q': 'cu', 'r': 'erre', 's': 'ese',
  't': 'te', 'u': 'u', 'v': 've', 'w': 'doble ve', 'x': 'equis', 'y': 'ye', 'z': 'zeta',
};
// Letras de otros idiomas que se leen como su equivalente español.
const _extranjeras = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o', 'ù': 'u', 'û': 'u', 'ç': 's', 'ß': 's',
};

/// Deja solo letras, espacios y la puntuación que el modelo entiende.
String _limpiar(String t) {
  var s = t
      .replaceAll('&', ' y ')
      .replaceAll('%', ' por ciento ')
      .replaceAll('…', '.')
      .replaceAll(RegExp(r'[—–\-/]'), ' ')
      .replaceAll(RegExp(r'[¿¡"“”«»()\[\]{}]'), ' ');
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final low = ch.toLowerCase();
    if (RegExp(r'[a-zñáéíóúü]').hasMatch(low)) {
      b.write(ch);
    } else if (_extranjeras.containsKey(low)) {
      final r = _extranjeras[low]!;
      b.write(ch == low ? r : r.toUpperCase());
    } else if (',;:.!? '.contains(ch)) {
      b.write(ch);
    } else {
      b.write(' ');
    }
  }
  return b.toString();
}

String _frase(String frase, bool seseo) {
  final simbolos = <String>[];
  for (final m in RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+|[,;:.!?]').allMatches(frase)) {
    final t = m[0]!;
    if (',;:.!?'.contains(t)) {
      if (simbolos.isNotEmpty && simbolos.last == ' ') simbolos.removeLast();
      if (simbolos.isNotEmpty && !',;:.!?'.contains(simbolos.last)) simbolos.add(t);
      if (simbolos.isNotEmpty) simbolos.add(' ');
      continue;
    }
    for (final p in _deletrearSiHaceFalta(t)) {
      simbolos
        ..addAll(_palabra(p, seseo))
        ..add(' ');
    }
  }
  while (simbolos.isNotEmpty && simbolos.last == ' ') {
    simbolos.removeLast();
  }
  if (!simbolos.any(_esFonema)) return '';
  return _alofonos(simbolos).join();
}

/// Siglas y palabras sin vocales (SRL, kg) se leen letra por letra.
List<String> _deletrearSiHaceFalta(String w) {
  final low = w.toLowerCase();
  final tieneVocal = low.split('').any(_vocales.contains);
  if (tieneVocal || low == 'y') return [w];
  return [for (final c in low.split('')) ...?_letras[c]?.split(' ')];
}

bool _esFonema(String s) => s != ' ' && s != 'ˈ' && !',;:.!?'.contains(s);

class _Seg {
  _Seg(this.f, this.vocal);
  String f;
  final bool vocal;
}

List<String> _palabra(String original, bool seseo) {
  final w = original.toLowerCase();
  final seg = _segmentos(w, seseo);
  final nucleos = _nucleos(seg);
  if (nucleos.isEmpty) return [for (final s in seg) s.f];

  int? tonica;
  for (var i = 0; i < nucleos.length; i++) {
    if (nucleos[i].any((x) => 'áéíóú'.contains(seg[x].f))) tonica = i;
  }
  if (tonica == null && !_atonas.contains(w)) {
    tonica = nucleos.length == 1 ? 0 : ('aeiouns'.contains(w[w.length - 1]) ? nucleos.length - 2 : nucleos.length - 1);
  }

  int? marca;
  if (tonica != null) {
    final g = nucleos[tonica];
    final conTilde = g.where((x) => 'áéíóú'.contains(seg[x].f));
    final fuertes = g.where((x) => _fuertes.contains(seg[x].f));
    // Dos débiles juntas (ui, iu): el acento va en la segunda.
    marca = conTilde.isNotEmpty ? conTilde.first : (fuertes.isNotEmpty ? fuertes.first : g.last);
  }
  // Débiles átonas antes de la vocal portadora: semivocales j/w (bien, agua).
  for (final g in nucleos) {
    final centro = g.contains(marca) ? marca! : (g.where((x) => _fuertes.contains(seg[x].f)).firstOrNull ?? g.last);
    for (final x in g) {
      if (x >= centro) break;
      final v = _sinTilde[seg[x].f] ?? seg[x].f;
      if (v == 'i') seg[x].f = 'j';
      if (v == 'u') seg[x].f = 'w';
    }
  }

  final out = <String>[];
  for (var x = 0; x < seg.length; x++) {
    if (x == marca) out.add('ˈ');
    out.add(_sinTilde[seg[x].f] ?? seg[x].f);
  }
  return out;
}

List<_Seg> _segmentos(String w, bool seseo) {
  final s = seseo ? 's' : 'θ';
  final out = <_Seg>[];
  var i = 0;
  String at(int k) => k < w.length ? w[k] : '';
  while (i < w.length) {
    final c = w[i], nx = at(i + 1), nx2 = at(i + 2);
    final suave = 'eiéí'.contains(nx) && nx.isNotEmpty;
    switch (c) {
      case _ when _vocales.contains(c):
        out.add(_Seg(c, true));
      case 'c' when nx == 'h':
        out.add(_Seg('tʃ', false));
        i++;
      case 'l' when nx == 'l':
        out.add(_Seg('ʝ', false)); // yeísmo
        i++;
      case 'r' when nx == 'r':
        out.add(_Seg('r', false));
        i++;
      case 'q':
        out.add(_Seg('k', false));
        if (nx == 'u') i++;
      case 'g' when nx == 'u' && 'eiéí'.contains(nx2) && nx2.isNotEmpty:
        out.add(_Seg('ɡ', false));
        i++;
      case 'c':
        out.add(_Seg(suave ? s : 'k', false));
      case 'g':
        out.add(_Seg(suave ? 'x' : 'ɡ', false));
      case 'z':
        out.add(_Seg(s, false));
      case 'j':
        out.add(_Seg('x', false));
      case 'ñ':
        out.add(_Seg('ɲ', false));
      case 'h':
        break;
      case 'v':
        out.add(_Seg('b', false));
      case 'x':
        if (_xJota.contains(w)) {
          out.add(_Seg('x', false));
        } else {
          out
            ..add(_Seg('k', false))
            ..add(_Seg('s', false));
        }
      case 'y':
        out.add(nx.isEmpty || !_vocales.contains(nx) ? _Seg('i', true) : _Seg('ʝ', false));
      case 'r':
        final fuerte = i == 0 || (out.isNotEmpty && 'nls'.contains(out.last.f));
        out.add(_Seg(fuerte ? 'r' : 'ɾ', false));
      default:
        out.add(_Seg(c, false));
    }
    i++;
  }
  return out;
}

/// Núcleos silábicos: vocales seguidas forman diptongo salvo dos fuertes (hiato).
List<List<int>> _nucleos(List<_Seg> seg) {
  final out = <List<int>>[];
  var k = 0;
  while (k < seg.length) {
    if (seg[k].vocal) {
      final g = [k];
      while (k + 1 < seg.length && seg[k + 1].vocal) {
        if (_fuertes.contains(seg[g.last].f) && _fuertes.contains(seg[k + 1].f)) break;
        g.add(k + 1);
        k++;
      }
      out.add(g);
    }
    k++;
  }
  return out;
}

/// Pronunciación en contexto, como espeak `es`:
/// - n se asimila: m antes de b/p/m, ŋ antes de ɡ/k/x (también entre palabras);
/// - b, d, ɡ son suaves (β, ð, ɣ) salvo al empezar o tras pausa, tras nasal,
///   y d tras l.
List<String> _alofonos(List<String> s) {
  final out = List.of(s);
  String? siguiente(int i) {
    for (var k = i + 1; k < out.length; k++) {
      if (out[k] == ' ' || out[k] == 'ˈ') continue;
      return out[k];
    }
    return null;
  }

  for (var i = 0; i < out.length; i++) {
    if (out[i] != 'n') continue;
    final nx = siguiente(i);
    if (nx == 'b' || nx == 'p' || nx == 'm') out[i] = 'm';
    if (nx == 'ɡ' || nx == 'k' || nx == 'x') out[i] = 'ŋ';
  }
  String? previo; // null = inicio o tras pausa
  for (var i = 0; i < out.length; i++) {
    final t = out[i];
    if (t == ' ' || t == 'ˈ') continue;
    if (',;:.!?'.contains(t)) {
      previo = null;
      continue;
    }
    final fuerte = previo == null || _nasales.contains(previo) || (t == 'd' && previo == 'l');
    if (!fuerte) {
      if (t == 'b') out[i] = 'β';
      if (t == 'd') out[i] = 'ð';
      if (t == 'ɡ') out[i] = 'ɣ';
    }
    previo = t;
  }
  return out;
}
