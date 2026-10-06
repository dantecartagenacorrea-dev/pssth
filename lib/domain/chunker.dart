const int kMaxChunkLength = 400;

/// Divide el texto de una página en bloques aptos para TTS.
List<String> splitPageText(String pageText, {int maxLength = kMaxChunkLength}) {
  final cleaned = pageText.replaceAll('\r\n', '\n').trim();
  if (cleaned.isEmpty) {
    return const [];
  }

  final paragraphs = cleaned
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((p) => p.isNotEmpty)
      .toList();

  if (paragraphs.isEmpty) {
    return _splitByLength(
      cleaned.replaceAll(RegExp(r'\s+'), ' ').trim(),
      maxLength,
    );
  }

  final chunks = <String>[];
  for (final paragraph in paragraphs) {
    chunks.addAll(_splitParagraph(paragraph, maxLength));
  }
  return chunks;
}

List<String> _splitParagraph(String paragraph, int maxLength) {
  if (paragraph.length <= maxLength) {
    return [paragraph];
  }

  final sentences = paragraph
      .split(RegExp(r'(?<=[.!?…])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  if (sentences.length <= 1) {
    return _splitByLength(paragraph, maxLength);
  }

  final chunks = <String>[];
  final buffer = StringBuffer();
  for (final sentence in sentences) {
    if (sentence.length > maxLength) {
      if (buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
      chunks.addAll(_splitByLength(sentence, maxLength));
      continue;
    }
    final next = buffer.isEmpty ? sentence : '${buffer.toString()} $sentence';
    if (next.length > maxLength && buffer.isNotEmpty) {
      chunks.add(buffer.toString().trim());
      buffer
        ..clear()
        ..write(sentence);
    } else {
      buffer
        ..clear()
        ..write(next);
    }
  }
  if (buffer.isNotEmpty) {
    chunks.add(buffer.toString().trim());
  }
  return chunks;
}

List<String> _splitByLength(String text, int maxLength) {
  if (text.length <= maxLength) {
    return [text];
  }
  final chunks = <String>[];
  var remaining = text;
  while (remaining.length > maxLength) {
    var cut = remaining.lastIndexOf(' ', maxLength);
    if (cut <= 0) {
      cut = maxLength;
    }
    chunks.add(remaining.substring(0, cut).trim());
    remaining = remaining.substring(cut).trim();
  }
  if (remaining.isNotEmpty) {
    chunks.add(remaining);
  }
  return chunks;
}
