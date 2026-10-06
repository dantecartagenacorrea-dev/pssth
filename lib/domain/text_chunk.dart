class TextChunk {
  TextChunk({
    required this.documentId,
    required this.pageIndex,
    required this.chunkIndex,
    required this.text,
    String? speech,
  }) : speech = speech ?? text;

  final String documentId;
  final int pageIndex;
  final int chunkIndex;

  /// Texto original (se muestra, se busca y se exporta).
  final String text;

  /// Texto normalizado solo para la voz.
  final String speech;
}
