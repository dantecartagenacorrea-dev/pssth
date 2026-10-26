import 'language_detector.dart';

/// Idioma por fragmento con histéresis: un fragmento corto o dudoso hereda el
/// idioma anterior, así una palabra o frase extranjera suelta no cambia la voz.
/// [detect] puede ser el detector nativo (NaturalLanguage) o el heurístico.
/// Con [allowed] solo se cambia a idiomas que tienen voz instalada: un
/// fragmento mal reconocido (p. ej. texto de OCR) no salta a una voz extraña.
/// Salir del idioma del documento exige un bloque largo ([minWords]); volver a
/// él basta con uno corriente ([minWordsBack]).
List<String> segmentLanguages(
  List<String> chunks, {
  required String documentLanguage,
  String? Function(String text)? detect,
  Set<String>? allowed,
  int minWords = 20,
  int minWordsBack = 8,
}) {
  final detector = detect ?? detectLanguageHeuristic;
  final out = <String>[];
  var current = documentLanguage;
  for (final chunk in chunks) {
    final words = RegExp(r'\p{L}+', unicode: true).allMatches(chunk).length;
    if (words >= minWordsBack) {
      final lang = detector(chunk);
      if (lang == documentLanguage) {
        current = documentLanguage;
      } else if (lang != null &&
          words >= minWords &&
          (allowed == null || allowed.isEmpty || allowed.contains(lang))) {
        current = lang;
      }
    }
    out.add(current);
  }
  return out;
}

/// Idioma con el que se lee el documento: el detectado si hay voz para él; si
/// no (detector equivocado o idioma sin voz), español, o el primero disponible.
String chooseDocumentLanguage(String? detected, {required Set<String> available}) {
  if (available.isEmpty) return detected ?? 'es';
  if (detected != null && available.contains(detected)) return detected;
  if (available.contains('es')) return 'es';
  return (available.toList()..sort()).first;
}
