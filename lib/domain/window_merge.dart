/// Trocear un audio largo en ventanas que se solapan y unir lo que escribió cada
/// una sin repetir lo que quedó en dos ventanas.
library;

/// Lo que se reconoció en una ventana: [start] y [end] son los segundos del
/// audio entero; [times], el comienzo de cada pieza dentro de la ventana.
class TimedWindow {
  const TimedWindow({required this.start, required this.end, required this.tokens, required this.times});

  final double start;
  final double end;
  final List<String> tokens;
  final List<double> times;
}

/// Ventanas `(inicio, fin)` que cubren [length] muestras. La última termina en
/// el final y conserva su largo, para no quedarse sin contexto.
List<(int, int)> audioWindows(int length, {required int window, required int overlap}) {
  if (length <= 0) return const [];
  if (length <= window) return [(0, length)];
  final out = <(int, int)>[];
  for (var start = 0; start + window < length; start += window - overlap) {
    out.add((start, start + window));
  }
  out.add((length - window, length));
  return out;
}

/// Une las ventanas. En cada solape manda la ventana donde la palabra queda más
/// lejos del borde, que es donde el reconocedor tiene más contexto: se corta en
/// la mitad del solape, y por palabras enteras para no partir ninguna.
String mergeWindows(List<TimedWindow> windows) {
  final text = StringBuffer();
  for (var i = 0; i < windows.length; i++) {
    final w = windows[i];
    final from = i == 0 ? double.negativeInfinity : (windows[i - 1].end + w.start) / 2;
    final to = i == windows.length - 1 ? double.infinity : (w.end + windows[i + 1].start) / 2;
    var keep = false;
    final count = w.tokens.length < w.times.length ? w.tokens.length : w.times.length;
    for (var t = 0; t < count; t++) {
      final token = w.tokens[t];
      if (t == 0 || token.startsWith(' ')) {
        final at = w.start + w.times[t];
        keep = at >= from && at < to;
        if (keep && text.isNotEmpty && !token.startsWith(' ')) text.write(' ');
      }
      if (keep) text.write(token);
    }
  }
  return text.toString().trim();
}
