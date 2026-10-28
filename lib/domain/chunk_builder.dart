import 'dart:isolate';

import 'chunker.dart';
import 'text_chunk.dart';
import 'text_normalizer.dart';
import '../services/transcript_cleaner.dart';

/// Convierte textos de página (ya limpios) en bloques para TTS.
List<TextChunk> buildChunks({
  required String documentId,
  required List<String> pages,
  required TextNormalizer normalizer,
  String Function(String)? clean,
}) {
  final chunks = <TextChunk>[];
  clean ??= TranscriptCleaner.instance.cleanerFor(pages.join('\n'));
  for (var i = 0; i < pages.length; i++) {
    final parts = splitPageText(clean(pages[i]));
    for (var c = 0; c < parts.length; c++) {
      chunks.add(
        TextChunk(
          documentId: documentId,
          pageIndex: i,
          chunkIndex: c,
          text: parts[c],
          speech: normalizer.normalize(parts[c]),
        ),
      );
    }
  }
  return chunks;
}

/// Igual que [buildChunks] pero en segundo plano, para no trabar la pantalla
/// con documentos largos. La limpieza se prepara aquí (usa lo aprendido, que
/// solo está en este hilo) y el trabajo pesado corre en otro.
Future<List<TextChunk>> buildChunksInBackground({
  required String documentId,
  required List<String> pages,
  required TextNormalizer normalizer,
}) {
  final clean = TranscriptCleaner.instance.cleanerFor(pages.join('\n'));
  return Isolate.run(() => buildChunks(documentId: documentId, pages: pages, normalizer: normalizer, clean: clean));
}

/// Una página se considera sin texto utilizable (candidata a OCR)
/// si tiene menos de [minChars] caracteres no blancos.
bool pageNeedsOcr(String pageText, {int minChars = 20}) =>
    pageText.replaceAll(RegExp(r'\s'), '').length < minChars;
