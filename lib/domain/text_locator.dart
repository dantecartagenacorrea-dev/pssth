/// Dónde está, dentro del texto original de una página, la frase que se lee.
/// La frase viene limpia (sin pies de página, con las palabras cortadas
/// unidas, otros espacios), así que se comparan solo letras y números en
/// minúscula. Devuelve el rango en [page] (fin exclusivo) o null.
({int start, int end})? locateSnippet(String page, String snippet) {
  final (norm, map) = _normalize(page);
  final (needle, _) = _normalize(snippet);
  if (needle.isEmpty || norm.isEmpty) return null;
  var at = norm.indexOf(needle);
  var endNorm = at < 0 ? -1 : at + needle.length;
  if (at < 0) {
    // La limpieza cambió algo en medio (un pie de página entre dos renglones):
    // se ubican el comienzo y el final por separado.
    // Trozos de un tercio de la frase (entre 10 y 24 letras): más largos
    // podrían cruzar justo el pie que se quitó.
    final piece = (needle.length ~/ 3).clamp(10, 24);
    if (needle.length < piece * 2) return null;
    at = norm.indexOf(needle.substring(0, piece));
    if (at < 0) return null;
    final tail = needle.substring(needle.length - piece);
    final tailAt = norm.indexOf(tail, at + piece);
    // El final tiene que quedar cerca: no más de la mitad más larga.
    if (tailAt < 0 || tailAt + piece - at > needle.length * 1.5) return null;
    endNorm = tailAt + piece;
  }
  return (start: map[at], end: map[endNorm - 1] + 1);
}

final _keep = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Solo letras y números en minúscula, con la posición de cada uno en el
/// texto original.
(String, List<int>) _normalize(String s) {
  final b = StringBuffer();
  final map = <int>[];
  final runes = s.runes.toList();
  var offset = 0;
  for (final r in runes) {
    final ch = String.fromCharCode(r);
    if (_keep.hasMatch(ch)) {
      final lower = ch.toLowerCase();
      b.write(lower);
      for (var i = 0; i < lower.length; i++) {
        map.add(offset);
      }
    }
    offset += ch.length;
  }
  return (b.toString(), map);
}

/// Junta los recuadros de cada letra en uno por renglón (para resaltar una
/// frase sin parpadeo letra por letra). Los recuadros vienen en orden de
/// lectura, con y creciendo hacia abajo.
List<({double left, double top, double right, double bottom})> mergeLines(
  Iterable<({double left, double top, double right, double bottom})> chars,
) {
  final out = <({double left, double top, double right, double bottom})>[];
  for (final c in chars) {
    if (c.right <= c.left || c.bottom <= c.top) continue; // espacios sin tamaño
    if (out.isNotEmpty) {
      final last = out.last;
      final overlap = (c.bottom < last.bottom ? c.bottom : last.bottom) - (c.top > last.top ? c.top : last.top);
      final h = c.bottom - c.top;
      // Mismo renglón: se superponen en alto al menos la mitad.
      if (overlap > h * 0.5 && c.left >= last.left - h) {
        out[out.length - 1] = (
          left: c.left < last.left ? c.left : last.left,
          top: c.top < last.top ? c.top : last.top,
          right: c.right > last.right ? c.right : last.right,
          bottom: c.bottom > last.bottom ? c.bottom : last.bottom,
        );
        continue;
      }
    }
    out.add(c);
  }
  return out;
}
