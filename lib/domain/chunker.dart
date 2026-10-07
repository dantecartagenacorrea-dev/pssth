import 'chapter_detector.dart';

const int kMaxChunkLength = 400;

/// Una línea corta en mayúsculas sin puntuación final (un título como
/// "EN EL CAMPO") se aísla como párrafo propio para que la voz haga pausa.
String _separateHeadings(String text) {
  final out = <String>[];
  for (final line in text.split('\n')) {
    final l = line.trim();
    final isCaps = l.isNotEmpty &&
        l.length <= 60 &&
        RegExp(r'\p{Lu}', unicode: true).hasMatch(l) &&
        !RegExp(r'\p{Ll}', unicode: true).hasMatch(l) &&
        !RegExp(r'[.;:,]$').hasMatch(l);
    final isHeading = isCaps || (l.length <= 80 && chapterHeadingPattern.hasMatch(l));
    out.add(isHeading ? '\n$l\n' : line);
  }
  return out.join('\n');
}

/// Abreviaturas tras las cuales un punto no termina la frase.
const Set<String> _abreviaturas = {
  'art', 'arts', 'inc', 'núm', 'num', 'nro', 'no', 'dr', 'dra', 'sr', 'sra',
  'srta', 'lic', 'ing', 'd.s', 'r.a', 'd', 's', 'r', 'a', 'pág', 'pag', 'cap',
  'ed', 'vol', 'etc', 'ej', 'p', 'pp', 'ud', 'uds', 'mr', 'mrs', 'ms', 'st',
  'vs', 'av', 'tel', 'ref', 'ltda', 'cía', 'cia', 'srl', 's.r.l', 's.a',
};

/// Divide un párrafo en frases sin cortar tras abreviaturas conocidas
/// ni tras un número suelto ("1." o "2.5.").
List<String> splitSentences(String paragraph) {
  final out = <String>[];
  final buf = StringBuffer();
  final parts = paragraph.split(RegExp(r'(?<=[.!?…])\s+'));
  for (final part in parts) {
    final piece = part.trim();
    if (piece.isEmpty) continue;
    buf.write(buf.isEmpty ? piece : ' $piece');
    final text = buf.toString();
    if (!text.endsWith('.')) {
      out.add(text);
      buf.clear();
      continue;
    }
    final m = RegExp(r'([^\s]+)\.$').firstMatch(text);
    final last = (m?.group(1) ?? '').toLowerCase();
    final esAbreviatura = _abreviaturas.contains(last) ||
        last.contains('·') ||
        RegExp(r'^[\d.]+$').hasMatch(last) ||
        RegExp(r'^[a-záéíóúñ]$').hasMatch(last);
    if (!esAbreviatura) {
      out.add(text);
      buf.clear();
    }
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}

/// Divide el texto de una página en bloques aptos para TTS.
List<String> splitPageText(String pageText, {int maxLength = kMaxChunkLength}) {
  final cleaned = pageText.replaceAll('\r\n', '\n').trim();
  if (cleaned.isEmpty) {
    return const [];
  }

  final paragraphs = _separateHeadings(cleaned)
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

  final sentences = splitSentences(paragraph);

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
    var cut = _clauseCut(remaining, maxLength);
    if (cut <= 0) {
      cut = remaining.lastIndexOf(' ', maxLength);
    }
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

/// Último límite de cláusula (`, ; :` seguido de espacio) en la segunda mitad
/// de la ventana, para no cortar a mitad de una idea. Devuelve -1 si no hay.
int _clauseCut(String text, int maxLength) {
  final end = maxLength < text.length ? maxLength : text.length - 1;
  for (var i = end; i >= maxLength ~/ 2; i--) {
    final c = text[i - 1];
    if ((c == ',' || c == ';' || c == ':') && text[i] == ' ') {
      return i;
    }
  }
  return -1;
}
