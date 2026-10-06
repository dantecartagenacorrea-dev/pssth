/// Detección de idioma ligera y local (respaldo cuando el sistema no la ofrece).
/// Devuelve un código ISO 639-1 ('es', 'en', 'pt', 'fr') o null si no hay confianza.
String? detectLanguageHeuristic(String text) {
  final words = RegExp(r'[a-záéíóúñüàâçèêëîïôùûœãõ]+', unicode: true)
      .allMatches(text.toLowerCase())
      .map((m) => m[0]!)
      .take(400)
      .toList();
  if (words.length < 8) return null;

  int score(Set<String> stop) => words.where(stop.contains).length;

  final scores = <String, int>{
    'es': score(_es),
    'en': score(_en),
    'pt': score(_pt),
    'fr': score(_fr),
  };
  final ranked = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final best = ranked[0];
  final second = ranked[1];
  if (best.value < 3) return null;
  if (best.value < second.value * 1.3) return null;
  return best.key;
}

const _es = {
  'el', 'la', 'los', 'las', 'de', 'del', 'que', 'y', 'en', 'un', 'una', 'es',
  'por', 'con', 'para', 'se', 'su', 'al', 'lo', 'como', 'más', 'pero', 'sus',
  'este', 'esta', 'son', 'entre', 'sin', 'sobre', 'también', 'fue', 'ha',
};
const _en = {
  'the', 'of', 'and', 'to', 'in', 'is', 'that', 'for', 'it', 'as', 'with',
  'was', 'on', 'are', 'by', 'this', 'be', 'at', 'or', 'from', 'an', 'have',
  'not', 'but', 'they', 'which', 'you', 'were', 'has', 'their',
};
const _pt = {
  'o', 'a', 'os', 'as', 'de', 'do', 'da', 'dos', 'das', 'que', 'e', 'em',
  'um', 'uma', 'para', 'com', 'não', 'por', 'mais', 'se', 'na', 'no', 'são',
  'ao', 'como', 'mas', 'foi', 'ele', 'ela', 'você',
};
const _fr = {
  'le', 'la', 'les', 'de', 'des', 'du', 'et', 'en', 'un', 'une', 'est', 'que',
  'pour', 'dans', 'qui', 'par', 'sur', 'pas', 'au', 'avec', 'ce', 'il', 'sont',
  'plus', 'ou', 'mais', 'nous', 'vous', 'être',
};
