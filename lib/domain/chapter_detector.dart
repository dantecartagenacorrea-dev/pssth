class Chapter {
  const Chapter({required this.title, required this.pageIndex});
  final String title;
  final int pageIndex;
}

/// Encabezado explícito de capítulo/sección (también lo usa el chunker).
final chapterHeadingPattern = RegExp(
  r'^(?:cap[íi]tulo|chapter|parte|part|secci[óo]n|libro|anexo|t[ií]tulo)\s+(?:\d{1,3}|[ivxlcdm]{1,8})\b.{0,60}$',
  caseSensitive: false,
);
final _tocLine = RegExp(r'(?:\.{2,}|\s{2,})\s*\d{1,4}$');

/// Detecta capítulos solo cuando hay evidencia clara (encabezados explícitos
/// cerca del inicio de página). Con menos de 2, no inventa índice.
List<Chapter> detectChapters(List<String> pages) {
  final found = <Chapter>[];
  int? lastNumber;
  for (var i = 0; i < pages.length; i++) {
    final lines = pages[i]
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .take(8)
        .toList();
    for (var k = 0; k < lines.length && k < 5; k++) {
      final line = lines[k];
      if (line.length > 80) continue;
      if (_tocLine.hasMatch(line)) continue; // línea de tabla de contenido
      if (chapterHeadingPattern.hasMatch(line)) {
        found.add(Chapter(title: line, pageIndex: i));
        break;
      }
      final numbered = _numberedHeading(lines, k, lastNumber);
      if (numbered != null) {
        lastNumber = numbered.$2;
        found.add(Chapter(title: numbered.$1, pageIndex: i));
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

/// "LEY Nº 12", "REGLA 3", "Principio 4"… (el número puede ir en el renglón
/// siguiente o faltar: entonces es el que sigue al anterior).
final _numberedWord = RegExp(
  r'''^(ley|regla|principio|lecci[óo]n|tema|paso|clave|secreto|h[áa]bito|estrategia|mandamiento|norma|unidad|m[óo]dulo)\s*(?:n\s*[º°o"'”]?\.?\s*)?(\d{1,3})?$''',
  caseSensitive: false,
);

/// Palabras que abren el desarrollo después del título (no son título).
const _afterTitle = {'criterio', 'juicio', 'introducción', 'introduccion', 'resumen', 'objetivo', 'objetivos'};

/// Encabezado numerado en [lines] a partir de [k]: ("Ley 12 · Título", 12).
(String, int)? _numberedHeading(List<String> lines, int k, int? lastNumber) {
  final m = _numberedWord.firstMatch(lines[k].replaceAll('�', 'º'));
  if (m == null) return null;
  var next = k + 1;
  var number = int.tryParse(m[2] ?? '');
  if (number == null && next < lines.length) {
    final raw = lines[next].replaceAll(' ', '');
    number = int.tryParse(raw);
    if (number != null) {
      next++;
    } else if (raw.length <= 3 && RegExp(r'\d').hasMatch(raw)) {
      next++; // número mal leído ("s3"): se salta y se deduce del anterior
    }
  }
  number ??= lastNumber == null ? null : lastNumber + 1;
  if (number == null) return null;
  // Título: renglones en mayúsculas que siguen (hasta 4).
  final title = <String>[];
  while (next < lines.length && title.length < 4) {
    final l = lines[next];
    final caps = RegExp(r'\p{Lu}', unicode: true).hasMatch(l) && !RegExp(r'\p{Ll}', unicode: true).hasMatch(l);
    if (!caps || l.length > 60 || _afterTitle.contains(l.toLowerCase().replaceAll(' ', ''))) break;
    title.add(l);
    next++;
  }
  final word = m[1]!;
  final label = '${word[0].toUpperCase()}${word.substring(1).toLowerCase()} $number';
  if (title.isEmpty) return (label, number);
  final t = title.join(' ').toLowerCase();
  return ('$label · ${t[0].toUpperCase()}${t.substring(1)}', number);
}
