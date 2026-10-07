import 'language_detector.dart';

/// Idioma por fragmento con histéresis: un fragmento corto o dudoso hereda el
/// idioma anterior, así una palabra o frase extranjera suelta no cambia la voz.
/// [detect] puede ser el detector nativo (NaturalLanguage) o el heurístico.
List<String> segmentLanguages(
  List<String> chunks, {
  required String documentLanguage,
  String? Function(String text)? detect,
  int minWords = 8,
}) {
  final detector = detect ?? detectLanguageHeuristic;
  final out = <String>[];
  var current = documentLanguage;
  for (final chunk in chunks) {
    final words = RegExp(r'\p{L}+', unicode: true).allMatches(chunk).length;
    if (words >= minWords) {
      final lang = detector(chunk);
      if (lang != null) current = lang;
    }
    out.add(current);
  }
  return out;
}
