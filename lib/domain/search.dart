import 'text_chunk.dart';

const _from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
const _to = 'aaaaaeeeeiiiiooooouuuunc';

/// Minúsculas y sin acentos, para búsquedas tolerantes.
String foldText(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    final i = _from.indexOf(ch);
    b.write(i >= 0 ? _to[i] : ch);
  }
  return b.toString();
}

/// Índices de los bloques que contienen [query] (sin distinguir acentos).
List<int> searchChunks(List<TextChunk> chunks, String query, {int limit = 200}) {
  final q = foldText(query.trim());
  if (q.isEmpty) return const [];
  final out = <int>[];
  for (var i = 0; i < chunks.length; i++) {
    if (foldText(chunks[i].text).contains(q)) {
      out.add(i);
      if (out.length >= limit) break;
    }
  }
  return out;
}
