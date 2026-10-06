class Chapter {
  const Chapter({required this.title, required this.pageIndex});
  final String title;
  final int pageIndex;
}

final _heading = RegExp(
  r'^(?:cap[íi]tulo|chapter|parte|part|secci[óo]n|libro|anexo|t[ií]tulo)\s+(?:\d{1,3}|[ivxlcdm]{1,8})\b.{0,60}$',
  caseSensitive: false,
);
final _tocLine = RegExp(r'(?:\.{2,}|\s{2,})\s*\d{1,4}$');

/// Detecta capítulos solo cuando hay evidencia clara (encabezados explícitos
/// cerca del inicio de página). Con menos de 2, no inventa índice.
List<Chapter> detectChapters(List<String> pages) {
  final found = <Chapter>[];
  for (var i = 0; i < pages.length; i++) {
    final lines = pages[i]
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .take(5);
    for (final line in lines) {
      if (line.length > 80) continue;
      if (_tocLine.hasMatch(line)) continue; // línea de tabla de contenido
      if (_heading.hasMatch(line)) {
        found.add(Chapter(title: line, pageIndex: i));
        break;
      }
    }
  }
  // Un mismo título repetido en muchas páginas es un encabezado, no un capítulo.
  final counts = <String, int>{};
  for (final c in found) {
    counts[c.title.toLowerCase()] = (counts[c.title.toLowerCase()] ?? 0) + 1;
  }
  final unique = found.where((c) => counts[c.title.toLowerCase()] == 1).toList();
  return unique.length >= 2 ? unique : const [];
}
