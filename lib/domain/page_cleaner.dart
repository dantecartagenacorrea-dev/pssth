import 'dart:math' as math;

import 'chapter_detector.dart';

/// Limpieza de texto extraído de PDF: encabezados/pies repetidos,
/// números de página y palabras partidas por guion de fin de línea.
/// Ante la duda conserva el texto original.
class PageCleaner {
  static final _pageNumber = RegExp(
    r'^(?:p[áa]gina|p[áa]g\.?|page|p\.)?\s*\d{1,4}(?:\s*(?:/|de|of)\s*\d{1,4})?$',
    caseSensitive: false,
  );
  static final _digits = RegExp(r'\d+');

  // Pie o encabezado con el número de página y el título en curso ("32 1 LEY
  // N° 1", "LEY N° 1 I 31"). El escaneo escribe distinto el separador en cada
  // página ("I", "1", "ILEY"), así que se comparan solo sus letras. Un año de
  // un rango ("1694-1778") no cuenta como número de página.
  static final _edgeNumber = RegExp(r'^\d{1,4}(?![\d-])|(?<![\d-])\d{1,4}$');
  static final _onlyNumbers = RegExp(r'^\d{1,4}(?:\s+\d{1,4})?$');
  static final _notLetter = RegExp(r'[^\p{L}]', unicode: true);
  static final _separatorEnds = RegExp(r'^[ijl]+|[ijl]+$');
  static const int _maxRunningLine = 40;
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

    final running = _runningTitles(lines);

    final out = <String>[];
    for (final pl in lines) {
      final kept = <String>[];
      for (var i = 0; i < pl.length; i++) {
        final nearEdge = i < _edge || i >= pl.length - _edge;
        final line = _joinSoftHyphens(pl[i], running);
        if (nearEdge) {
          if (_pageNumber.hasMatch(line) || _onlyNumbers.hasMatch(line)) {
            continue;
          }
          if (repeated.contains(_key(line))) continue;
        }
        // El pie a veces queda en medio de la página (orden del escaneo).
        final title = _runningKey(line);
        if (title != null && running.contains(title)) continue;
        kept.add(line);
      }
      out.add(
        kept.join('\n').replaceAllMapped(_hyphenBreak, (m) => '${m[1]}${m[2]}'),
      );
    }
    return out;
  }

  /// PDFium marca con este carácter el guion que corta una palabra al final
  /// del renglón ("igno\u0002rancia"): sin quitarlo la voz la leía partida.
  static const _softHyphen = '\u0002';

  /// Une las palabras cortadas. Si tras el corte quedó pegado el pie de página
  /// ("resigna\u0002LEY N° 19 I 191"), se quita el pie y la palabra sigue en
  /// la página siguiente.
  static String _joinSoftHyphens(String line, Set<String> running) {
    if (!line.contains(_softHyphen)) return line;
    final cut = line.lastIndexOf(_softHyphen);
    final tail = _runningKey(line.substring(cut + 1));
    if (tail != null && running.contains(tail)) {
      return '${line.substring(0, cut).replaceAll(_softHyphen, '')}-';
    }
    return line.replaceAll(_softHyphen, '');
  }

  /// Letras de un renglón del borde que lleva número de página, o null.
  static String? _runningKey(String line) {
    if (line.length > _maxRunningLine || !_edgeNumber.hasMatch(line)) {
      return null;
    }
    if (isChapterHeadingLine(line)) return null; // "LEY N° 22" abre capítulo
    final key = line
        .toLowerCase()
        .replaceAll(_notLetter, '')
        .replaceAll(_separatorEnds, '');
    return key.isEmpty ? null : key;
  }

  /// Títulos en curso que aparecen junto al número de página en 3 o más bordes.
  static Set<String> _runningTitles(List<List<String>> lines) {
    final counts = <String, int>{};
    for (final pl in lines) {
      for (var i = 0; i < pl.length; i++) {
        if (i >= _edge && i < pl.length - _edge) continue;
        final key = _runningKey(pl[i]);
        if (key != null) counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    return {
      for (final e in counts.entries)
        if (e.value >= 3) e.key,
    };
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
