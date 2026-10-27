/// Estima qué palabra suena en un audio sin marcas de tiempo (voz natural):
/// reparte la duración según el largo de cada palabra y deja más tiempo tras
/// comas y puntos, donde la voz hace pausa.
library;

final _word = RegExp(r'\S+');
final _pause = RegExp(r'[.,;:!?…]$');

/// Inicio y fin (en caracteres) de cada palabra de [text].
List<(int, int)> wordSpans(String text) =>
    [for (final m in _word.allMatches(text)) (m.start, m.end)];

/// Palabra que suena cuando ya pasó la fracción [fraction] (0–1) de la voz.
(int, int)? wordAtFraction(String text, double fraction) {
  final spans = wordSpans(text);
  if (spans.isEmpty) return null;
  final weights = [
    for (final (s, e) in spans) (e - s) + 1 + (_pause.hasMatch(text.substring(s, e)) ? 4 : 0),
  ];
  final total = weights.fold<int>(0, (a, b) => a + b);
  final target = fraction.clamp(0.0, 1.0) * total;
  var acc = 0;
  for (var i = 0; i < spans.length; i++) {
    acc += weights[i];
    if (target < acc) return spans[i];
  }
  return spans.last;
}

/// Tramo del audio con voz (sin el silencio del principio y del final), en
/// índices de [envelope]; null si todo es silencio.
(int, int)? voicedRange(List<double> envelope, {double threshold = 0.08}) {
  final first = envelope.indexWhere((v) => v > threshold);
  if (first < 0) return null;
  final last = envelope.lastIndexWhere((v) => v > threshold);
  return (first, last);
}
