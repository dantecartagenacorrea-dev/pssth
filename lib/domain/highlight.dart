/// Frase subrayada mientras se escucha, con una nota opcional.
class Highlight {
  const Highlight({
    required this.id,
    required this.documentId,
    required this.pageIndex,
    required this.chunkIndex,
    required this.text,
    required this.note,
    required this.createdIso,
  });

  final String id;
  final String documentId;
  final int pageIndex;
  final int chunkIndex;

  /// La frase tal como se ve en la lectura.
  final String text;

  /// Lo que escribió la persona ('' si solo subrayó).
  final String note;
  final String createdIso;

  Highlight withNote(String value) => Highlight(
    id: id,
    documentId: documentId,
    pageIndex: pageIndex,
    chunkIndex: chunkIndex,
    text: text,
    note: value,
    createdIso: createdIso,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'documentId': documentId,
    'pageIndex': pageIndex,
    'chunkIndex': chunkIndex,
    'text': text,
    'note': note,
    'createdIso': createdIso,
  };

  factory Highlight.fromJson(Map<String, dynamic> j) => Highlight(
    id: j['id'] as String? ?? '',
    documentId: j['documentId'] as String? ?? '',
    pageIndex: (j['pageIndex'] as num?)?.toInt() ?? 0,
    chunkIndex: (j['chunkIndex'] as num?)?.toInt() ?? 0,
    text: j['text'] as String? ?? '',
    note: j['note'] as String? ?? '',
    createdIso: j['createdIso'] as String? ?? '',
  );
}

/// Las notas de un documento como texto para guardar o compartir.
String highlightsAsText(String title, List<Highlight> list) {
  final b = StringBuffer('Notas de "$title"\n');
  for (final h in list) {
    b.write('\n— Página ${h.pageIndex + 1}\n${h.text}\n');
    if (h.note.trim().isNotEmpty) b.write('Nota: ${h.note.trim()}\n');
  }
  return b.toString();
}
