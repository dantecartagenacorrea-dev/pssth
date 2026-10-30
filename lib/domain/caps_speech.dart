/// Cómo se dicen las mayúsculas: un título en mayúsculas ("KAUTILYA,
/// FILÓSOFO") se lee como palabras con entonación de título (cerrado con
/// punto), no plano ni deletreado. Una palabra en mayúsculas dentro de una
/// frase se dice como palabra. Las siglas cortas (ONU, PDF) y los números
/// romanos (III) se dejan como están. Solo cambian mayúsculas y el punto
/// final: las posiciones de las letras no se mueven.
String speakableCaps(String text) {
  final letters = RegExp(r'\p{L}', unicode: true);
  final lower = RegExp(r'\p{Ll}', unicode: true);
  final isTitle = letters.hasMatch(text) && !lower.hasMatch(text);
  final out = text.replaceAllMapped(RegExp(r'\p{Lu}[\p{Lu}\p{M}]*', unicode: true), (m) {
    final w = m[0]!;
    if (w.length == 1 || _roman.hasMatch(w)) return w;
    if (!isTitle && (w.length <= 3 || !_vowel.hasMatch(w))) return w; // sigla
    return w[0] + w.substring(1).toLowerCase();
  });
  if (!isTitle) return out;
  final trimmed = out.trimRight();
  return RegExp(r'[.!?…:;]$').hasMatch(trimmed) ? out : '$trimmed.';
}

final _roman = RegExp(r'^[IVXLCDM]+$');
final _vowel = RegExp(r'[AEIOUÁÉÍÓÚÜ]');

/// ¿Lo que se dice es lo que se ve, salvo mayúsculas y el punto final que
/// agrega [speakableCaps]? Sirve para seguir la palabra que suena.
bool sameSpokenText(String speech, String shown) {
  if (speech == shown) return true;
  final a = speech.toLowerCase(), b = shown.toLowerCase().trimRight();
  return a == b || a == '$b.';
}
