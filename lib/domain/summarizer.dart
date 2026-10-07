import 'dart:math' as math;

import 'chunker.dart' show splitSentences;

/// Resumen extractivo local: elige las frases más representativas del propio
/// texto (sin IA, sin red, sin inventar contenido) y las devuelve en su orden
/// original. Determinista y apto para documentos largos.
List<String> summarizeExtractive(
  String text, {
  double ratio = 0.1,
  int minSentences = 3,
  int maxSentences = 12,
}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) return const [];

  final sentences = splitSentences(flat).where((s) {
    final w = _wordCount(s);
    return w >= 5 && w <= 70;
  }).toList();
  if (sentences.length <= minSentences) return sentences;

  final tokens = [for (final s in sentences) _contentWords(s)];

  final freq = <String, int>{};
  for (final ws in tokens) {
    for (final w in ws.toSet()) {
      freq[w] = (freq[w] ?? 0) + 1;
    }
  }
  // Una palabra en casi todas las frases no distingue; una única vez tampoco.
  final n = sentences.length;
  final weight = <String, double>{
    for (final e in freq.entries)
      if (e.value >= 2 && e.value <= n * 0.5) e.key: e.value.toDouble(),
  };

  final scores = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final uniq = tokens[i].toSet();
    if (uniq.isEmpty) continue;
    var sum = 0.0;
    for (final w in uniq) {
      sum += weight[w] ?? 0;
    }
    var score = sum / _pow06(uniq.length);
    if (i < n * 0.1) score *= 1.15; // el inicio suele presentar el tema
    scores[i] = score;
  }

  final target = (n * ratio).round().clamp(minSentences, maxSentences);
  final order = List<int>.generate(n, (i) => i)
    ..sort((a, b) {
      final c = scores[b].compareTo(scores[a]);
      return c != 0 ? c : a.compareTo(b);
    });

  final chosen = <int>[];
  for (final i in order) {
    if (chosen.length >= target) break;
    if (scores[i] <= 0) break;
    final set = tokens[i].toSet();
    final redundant = chosen.any((j) => _jaccard(set, tokens[j].toSet()) > 0.5);
    if (!redundant) chosen.add(i);
  }
  chosen.sort();
  return [for (final i in chosen) sentences[i]];
}

int _wordCount(String s) => RegExp(r'\p{L}+', unicode: true).allMatches(s).length;

double _pow06(int n) => math.pow(n, 0.6).toDouble();

double _jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final inter = a.intersection(b).length;
  return inter / (a.length + b.length - inter);
}

List<String> _contentWords(String s) => RegExp(r'\p{L}{3,}', unicode: true)
    .allMatches(s.toLowerCase())
    .map((m) => m[0]!)
    .where((w) => !_stop.contains(w))
    .toList();

const _stop = {
  // español
  'que', 'los', 'las', 'del', 'por', 'con', 'para', 'una', 'uno', 'unos', 'unas',
  'como', 'más', 'pero', 'sus', 'este', 'esta', 'esto', 'estos', 'estas', 'son',
  'entre', 'sin', 'sobre', 'también', 'fue', 'han', 'ser', 'está', 'están',
  'cuando', 'donde', 'muy', 'ese', 'esa', 'eso', 'hay', 'todo', 'todos', 'todas',
  'les', 'nos', 'ante', 'bajo', 'hasta', 'desde', 'cada', 'otro', 'otra', 'otros',
  'puede', 'pueden', 'tiene', 'tienen', 'así', 'aunque', 'porque', 'según',
  // inglés
  'the', 'and', 'that', 'for', 'with', 'was', 'are', 'this', 'from', 'have',
  'not', 'but', 'they', 'which', 'you', 'were', 'has', 'their', 'been', 'will',
  'would', 'there', 'what', 'when', 'where', 'who', 'its', 'also', 'than',
  // portugués / francés frecuentes
  'não', 'uma', 'são', 'com', 'dos', 'das', 'des', 'est', 'pour', 'dans',
  'qui', 'par', 'sur', 'pas', 'avec',
};
