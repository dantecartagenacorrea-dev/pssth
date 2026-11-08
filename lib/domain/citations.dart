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

/// Direcciones web y correos, que la voz leería letra por letra
/// ("https://www.ejemplo.com/ruta", "www.ejemplo.org", "ejemplo.com.bo",
/// "nombre@correo.com"). El punto que cierra la frase se conserva.
String withoutLinks(String text) {
  final out = text.replaceAllMapped(_link, (m) => _trailing.firstMatch(m[0]!)?[0] ?? '');
  if (out == text) return text;
  return out
      .replaceAll(RegExp(r'\s?\(\s*\)'), '')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAllMapped(RegExp(r'\s+([.,;:!?)])'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'([:,;])([.!?])'), (m) => m[2]!)
      .trim();
}

final _link = RegExp(
  r'\s?(?:'
  r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+'
  r'|(?:https?://|www\.)[^\s<>"«»]+'
  r'|\b[\w-]+(?:\.[\w-]+)*\.(?:com|org|net|edu|gob|gov|info|io|bo|es|mx|ar|cl|pe|co|ec|uy|py|ve)(?:\.[a-z]{2})?\b(?:/[^\s<>"«»]*)?'
  r')',
  caseSensitive: false,
);

/// Puntuación pegada al final de un enlace que en realidad es de la frase.
final _trailing = RegExp(r'[.,;:!?)\]]+$');
