import 'chunker.dart';
import 'text_chunk.dart';
import 'text_normalizer.dart';
import '../services/transcript_cleaner.dart';

/// Convierte textos de página (ya limpios) en bloques para TTS.
List<TextChunk> buildChunks({
  required String documentId,
  required List<String> pages,
  required TextNormalizer normalizer,
}) {
  final chunks = <TextChunk>[];
  final cleaner = TranscriptCleaner.instance;
  final context = pages.join('\n');
  for (var i = 0; i < pages.length; i++) {
    final parts = splitPageText(cleaner.clean(pages[i], context: context));
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

/// Una página se considera sin texto utilizable (candidata a OCR)
/// si tiene menos de [minChars] caracteres no blancos.
bool pageNeedsOcr(String pageText, {int minChars = 20}) =>
    pageText.replaceAll(RegExp(r'\s'), '').length < minChars;
