/// Citas y notas que no se leen en voz alta si se pide (como hace Speechify):
/// referencias entre corchetes ("[12]", "[3, 4]", "[Pérez 2019]") y entre
/// paréntesis las que llevan un año ("(Pérez, 2019)", "(ver Smith et al.,
/// 2020, p. 4)"). Los paréntesis comunes ("(o sea, el rey)") se leen.
String withoutCitations(String text) {
  final out = text.replaceAll(_brackets, '').replaceAll(_yearParens, '');
  if (out == text) return text;
  return out.replaceAll(RegExp(r'[ \t]{2,}'), ' ').replaceAllMapped(RegExp(r'\s+([.,;:!?])'), (m) => m[1]!).trim();
}

/// Entre corchetes, cortos (una cita, no un párrafo).
final _brackets = RegExp(r'\s?\[[^\[\]\n]{1,40}\]');

/// Entre paréntesis, cortos y con un año (1500-2099, con letra opcional: 2019a).
final _yearParens = RegExp(r'\s?\((?=[^()\n]{0,80}\b(?:1[5-9]|20)\d{2}[a-z]?\b)[^()\n]{1,80}\)');
