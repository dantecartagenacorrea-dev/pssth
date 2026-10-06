import 'dart:convert';

/// Decodifica bytes de un TXT: UTF-8 y, si falla, Latin-1.
String decodeText(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes);
  }
}

/// Agrupa párrafos en "páginas" lógicas (~[pageChars] caracteres) para TXT.
List<String> paginateText(String text, {int pageChars = 3000}) {
  final cleaned = text.replaceAll('\r\n', '\n').trim();
  if (cleaned.isEmpty) return [''];
  final paragraphs = cleaned.split(RegExp(r'\n\s*\n'));
  final pages = <String>[];
  final buf = StringBuffer();
  for (final p in paragraphs) {
    if (buf.length > 0 && buf.length + p.length > pageChars) {
      pages.add(buf.toString().trim());
      buf.clear();
    }
    if (buf.length > 0) buf.write('\n\n');
    buf.write(p);
  }
  if (buf.length > 0) pages.add(buf.toString().trim());
  return pages;
}
