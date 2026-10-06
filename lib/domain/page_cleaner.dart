import 'dart:math' as math;

/// Limpieza de texto extraído de PDF: encabezados/pies repetidos,
/// números de página y palabras partidas por guion de fin de línea.
/// Ante la duda conserva el texto original.
class PageCleaner {
  static final _pageNumber = RegExp(
    r'^(?:p[áa]gina|p[áa]g\.?|page|p\.)?\s*\d{1,4}(?:\s*(?:/|de|of)\s*\d{1,4})?$',
    caseSensitive: false,
  );
  static final _digits = RegExp(r'\d+');
  static final _hyphenBreak = RegExp(r'(\p{L})-\n(\p{Ll})', unicode: true);

  static const int _edge = 2; // líneas candidatas arriba y abajo
  static const int _minPagesForRepeat = 4;

  static List<String> clean(List<String> pages) {
    final lines = pages.map(_toLines).toList();

    // Cuenta en cuántas páginas aparece cada línea candidata (en los bordes).
    final repeated = <String>{};
    if (pages.length >= _minPagesForRepeat) {
      final counts = <String, int>{};
      for (final pl in lines) {
        for (final k in _edgeKeys(pl).toSet()) {
          counts[k] = (counts[k] ?? 0) + 1;
        }
      }
      final threshold = math.max(3, (pages.length * 0.4).ceil());
      counts.forEach((k, v) {
        if (k.isNotEmpty && v >= threshold) repeated.add(k);
      });
    }

    final out = <String>[];
    for (final pl in lines) {
      final kept = <String>[];
      for (var i = 0; i < pl.length; i++) {
        final nearEdge = i < _edge || i >= pl.length - _edge;
        final line = pl[i];
        if (nearEdge) {
          if (_pageNumber.hasMatch(line)) continue;
          if (repeated.contains(_key(line))) continue;
        }
        kept.add(line);
      }
      out.add(kept.join('\n').replaceAllMapped(
            _hyphenBreak,
            (m) => '${m[1]}${m[2]}',
          ));
    }
    return out;
  }

  static List<String> _toLines(String page) => page
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  static String _key(String line) =>
      line.toLowerCase().replaceAll(_digits, '#');

  static Iterable<String> _edgeKeys(List<String> pl) sync* {
    for (var i = 0; i < pl.length; i++) {
      if (i < _edge || i >= pl.length - _edge) {
        yield _key(pl[i]);
      }
    }
  }
}
