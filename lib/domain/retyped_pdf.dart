import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'retype_ink.dart';
import 'scanned_pdf.dart';

/// Una palabra en la hoja, a [x] puntos del borde.
typedef FlowWord = ({String text, double x, bool bold});

/// Una firma o un sello en la hoja, en puntos.
typedef FlowMark = ({Uint8List jpeg, double x, double y, double width, double height});

/// Un renglón de la hoja nueva, a [y] puntos de arriba: palabras, o lo que no es
/// texto, que ocupa su propio lugar.
typedef FlowLine = ({double y, List<FlowWord> words, List<FlowMark> marks});

/// Firmas y sellos que van a la misma altura, antes del párrafo número [before].
typedef MarkRow = ({int before, double height, List<({Uint8List jpeg, double x, double width, double height})> marks});

/// Un párrafo: sus palabras y dónde empieza su primer renglón y los demás.
typedef Paragraph = ({
  List<({String text, bool bold})> words,
  double firstIndent,
  double restIndent,
  bool spaced,
  bool justify,
  double top,
});

const _margin = 72.0; // una pulgada
const _fontSize = 12.0;
const _leading = 1.35;

/// Como separación entre párrafos, en renglones.
const _paragraphGap = 0.6;

/// Dos renglones alineados a la misma sangría, como fracción del ancho del
/// texto: una hoja arrugada corre cada renglón un poco.
const _sameIndent = 0.018;

/// Un renglón llega al borde derecho salvo esta fracción: si no llega, ahí
/// terminaba el párrafo.
const _reachesRight = 0.035;

/// Dos pedazos de un renglón se pisan a lo sumo esta fracción de su ancho.
const _sideBySide = 0.1;

/// Más separación que esto, en renglones, ya es un párrafo aparte.
const _sameParagraph = 1.45;

/// Rearma el texto leído en párrafos, como lo escribió el autor: los cortes de
/// renglón de la hoja vieja desaparecen; las sangrías y las viñetas se mantienen.
/// [bold]: qué palabras de cada renglón iban en negrita, medido en la foto.
List<Paragraph> paragraphsFrom(List<ScannedLine> scanned, {List<List<bool>?>? bold}) {
  final merged = _rows(scanned, bold);
  if (merged.isEmpty) return const [];
  final rows = [for (final r in merged) r.line];
  final blockLeft = rows.map((r) => r.left).reduce(math.min);
  final blockRight = rows.map((r) => r.left + r.width).reduce(math.max);
  final blockWidth = math.max(blockRight - blockLeft, 1e-6);
  final indents = _sameBulletIndent(rows, _indents(rows, blockLeft, blockWidth));
  final right = _justifiedRight(rows, blockWidth);
  // El paso normal es de los chicos: con pocos renglones, los saltos pesan mucho.
  // Por el centro: en una hoja torcida las cajas son altas y el borde de arriba engaña.
  double middle(ScannedLine row) => row.top + row.height / 2;
  final pitches = [for (var i = 1; i < rows.length; i++) middle(rows[i]) - middle(rows[i - 1])]..sort();
  final pitch = pitches.isEmpty ? 1.0 : math.max(pitches[pitches.length ~/ 3], 1e-6);

  final out = <Paragraph>[];
  var words = <({String text, bool bold})>[];
  var first = 0.0, rest = 0.0, top = 0.0, spaced = false, heading = false, count = 0;
  void close() {
    if (words.isEmpty) return;
    out.add((words: words, firstIndent: first, restIndent: rest, spaced: spaced, justify: !heading, top: top));
    words = [];
  }

  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final text = row.text;
    final isBullet = text.startsWith('» ');
    final isHeading = _isHeading(text) && row.width < 0.6 * blockWidth;
    final gap = i == 0 ? 0.0 : (middle(row) - middle(rows[i - 1])) / pitch;
    final previousEnded = i > 0 && rows[i - 1].left + rows[i - 1].width < right - _reachesRight * blockWidth;
    final startsNew =
        i == 0 || gap > _sameParagraph || previousEnded || isBullet || isHeading || heading || indents[i] < rest;
    if (startsNew) {
      close();
      first = indents[i];
      rest = indents[i];
      top = row.top;
      spaced = gap > _sameParagraph;
      heading = isHeading;
      count = 0;
    } else if (count == 1) {
      rest = indents[i];
    }
    final flags = merged[i].bold;
    // Sin medida, solo los títulos.
    words.addAll([for (final (at, w) in text.split(' ').indexed) (text: w, bold: flags?[at] ?? isHeading)]);
    count++;
  }
  close();
  return out;
}

/// Acomoda los párrafos en hojas: renglones rectos, márgenes parejos y texto
/// justificado. [measure] da el ancho de un texto con letra de tamaño 1.
List<List<FlowLine>> layoutParagraphs(
  List<Paragraph> paragraphs, {
  required double Function(String text, bool bold) measure,
  PdfPageFormat format = PdfPageFormat.letter,
  List<MarkRow> marks = const [],
}) {
  final contentWidth = format.width - 2 * _margin;
  final step = _fontSize * _leading;
  final bottom = format.height - _margin;
  final pages = <List<FlowLine>>[];
  var page = <FlowLine>[];
  var y = _margin;

  double widthOf(({String text, bool bold}) w) => measure(w.text, w.bold) * _fontSize;
  final space = measure(' ', false) * _fontSize;

  void put(List<({String text, bool bold})> line, double indent, bool justify) {
    if (y + step > bottom) {
      pages.add(page);
      page = [];
      y = _margin;
    }
    final total = line.fold<double>(0, (sum, w) => sum + widthOf(w));
    final room = contentWidth - indent * contentWidth;
    final gaps = line.length - 1;
    final gap = justify && gaps > 0 ? (room - total) / gaps : space;
    var x = _margin + indent * contentWidth;
    final words = <FlowWord>[];
    for (final w in line) {
      words.add((text: w.text, x: x, bold: w.bold));
      x += widthOf(w) + gap;
    }
    page.add((y: y, words: words, marks: const []));
    y += step;
  }

  void putMarks(MarkRow row) {
    final tall = row.height + step * _paragraphGap;
    if (y + tall > bottom && page.isNotEmpty) {
      pages.add(page);
      page = [];
      y = _margin;
    }
    page.add((
      y: y,
      words: const [],
      marks: [for (final m in row.marks) (jpeg: m.jpeg, x: m.x, y: y, width: m.width, height: m.height)],
    ));
    y += tall;
  }

  for (final (index, p) in paragraphs.indexed) {
    marks.where((row) => row.before == index).forEach(putMarks);
    if (p.spaced && page.isNotEmpty) y += step * _paragraphGap;
    var line = <({String text, bool bold})>[];
    var width = 0.0;
    var indent = p.firstIndent;
    for (final w in p.words) {
      final room = contentWidth - indent * contentWidth;
      final wordWidth = widthOf(w);
      final next = line.isEmpty ? wordWidth : width + space + wordWidth;
      if (next > room && line.isNotEmpty) {
        put(line, indent, p.justify);
        line = [];
        width = 0;
        indent = p.restIndent;
      }
      width = line.isEmpty ? wordWidth : width + space + wordWidth;
      line.add(w);
    }
    if (line.isNotEmpty) put(line, indent, false);
  }
  marks.where((row) => row.before >= paragraphs.length).forEach(putMarks);
  if (page.isNotEmpty) pages.add(page);
  return pages;
}

/// Ubica las firmas y los sellos de una hoja entre sus párrafos, con el tamaño y
/// la sangría que tenían respecto del texto. [offset]: párrafos de las hojas anteriores.
List<MarkRow> markRowsFrom(
  List<PageMark> marks,
  List<Paragraph> paragraphs,
  List<ScannedLine> lines,
  int pageWidth, {
  required int pageHeight,
  int offset = 0,
  PdfPageFormat format = PdfPageFormat.letter,
}) {
  if (marks.isEmpty || lines.isEmpty) return const [];
  final contentWidth = format.width - 2 * _margin;
  final blockLeft = lines.map((l) => l.left).reduce(math.min);
  final blockRight = lines.map((l) => l.left + l.width).reduce(math.max);
  final blockWidth = math.max(blockRight - blockLeft, 1e-6);
  final maxHeight = (format.height - 2 * _margin) / 2;
  final out = <MarkRow>[];
  final sorted = [...marks]..sort((a, b) => a.top.compareTo(b.top));
  var i = 0;
  while (i < sorted.length) {
    final group = [sorted[i]];
    var end = sorted[i].top + sorted[i].boxHeight;
    for (i++; i < sorted.length && sorted[i].top < end; i++) {
      group.add(sorted[i]);
      end = math.max(end, sorted[i].top + sorted[i].boxHeight);
    }
    final placed = <({Uint8List jpeg, double x, double width, double height})>[];
    for (final m in group) {
      final ratio = (m.boxHeight * pageHeight) / (m.boxWidth * pageWidth);
      var width = math.min(contentWidth, m.boxWidth / blockWidth * contentWidth);
      if (width * ratio > maxHeight) width = maxHeight / ratio;
      final x = _margin + (m.left - blockLeft) / blockWidth * contentWidth;
      placed.add((
        jpeg: m.jpeg,
        x: x.clamp(_margin, _margin + contentWidth - width),
        width: width,
        height: width * ratio,
      ));
    }
    final before = paragraphs.indexWhere((p) => p.top > group.first.top);
    out.add((
      before: offset + (before < 0 ? paragraphs.length : before),
      height: placed.map((m) => m.height).reduce(math.max),
      marks: placed,
    ));
  }
  return out;
}

/// Arma el documento recién impreso: el texto corre de una hoja a la otra. Una
/// página en la que no se leyó nada va con su foto, en su lugar: nunca se pierde.
/// [ink]: las negritas y las firmas y sellos de cada página.
Future<Uint8List> buildRetypedPdf(List<ScannedPage> pages, {String? title, bool compress = true, List<PageInk>? ink}) {
  final doc = pw.Document(title: title, creator: 'PSSTH!', compress: compress);
  final regular = PdfFont.helvetica(doc.document);
  final bold = PdfFont.helveticaBold(doc.document);
  double measure(String text, bool isBold) => (isBold ? bold : regular).stringMetrics(text).advanceWidth;
  const format = PdfPageFormat.letter;

  void addText(List<Paragraph> paragraphs, List<MarkRow> marks) {
    for (final lines in layoutParagraphs(paragraphs, measure: measure, format: format, marks: marks)) {
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Stack(
            children: [
              for (final line in lines)
                for (final m in line.marks)
                  pw.Positioned(
                    left: m.x,
                    top: m.y,
                    child: pw.Image(pw.MemoryImage(m.jpeg), width: m.width, height: m.height),
                  ),
              pw.CustomPaint(
                size: PdfPoint(format.width, format.height),
                painter: (canvas, size) {
                  canvas.setFillColor(PdfColors.black);
                  for (final line in lines) {
                    for (final w in line.words) {
                      canvas.drawString(w.bold ? bold : regular, _fontSize, w.text, w.x, size.y - line.y - _fontSize);
                    }
                  }
                },
              ),
            ],
          ),
        ),
      );
    }
  }

  var pending = <Paragraph>[];
  var pendingMarks = <MarkRow>[];
  for (final (index, page) in pages.indexed) {
    final found = ink == null || index >= ink.length ? null : ink[index];
    final lines = _writable(page.lines);
    final paragraphs = paragraphsFrom(lines, bold: found?.bold);
    if (paragraphs.isNotEmpty) {
      pendingMarks.addAll(
        markRowsFrom(
          found?.marks ?? const [],
          paragraphs,
          lines,
          page.width,
          pageHeight: page.height,
          offset: pending.length,
          format: format,
        ),
      );
      pending.addAll(paragraphs);
      continue;
    }
    addText(pending, pendingMarks);
    pending = [];
    pendingMarks = [];
    final fit = math.min(format.width / page.width, format.height / page.height);
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Center(
          child: pw.Image(pw.MemoryImage(page.jpeg), width: page.width * fit, height: page.height * fit),
        ),
      ),
    );
  }
  addText(pending, pendingMarks);
  return doc.save();
}

List<ScannedLine> _writable(List<ScannedLine> lines) => [
  for (final l in lines) (text: latin1Safe(l.text), left: l.left, top: l.top, width: l.width, height: l.height),
];

/// Renglones de arriba abajo, sin vacíos, juntando los pedazos de una misma
/// altura y limpiando los espacios de más. Cada uno con las negritas de sus palabras.
List<({ScannedLine line, List<bool>? bold})> _rows(List<ScannedLine> lines, List<List<bool>?>? bold) {
  final sorted = [
    for (final (i, l) in lines.indexed)
      if (l.text.trim().isNotEmpty) (line: l, bold: bold != null && i < bold.length ? bold[i] : null),
  ]..sort((a, b) => (a.line.top + a.line.height / 2).compareTo(b.line.top + b.line.height / 2));
  final rows = <({ScannedLine line, List<bool>? bold})>[];
  for (final piece in sorted) {
    final l = piece.line;
    final last = rows.isEmpty ? null : rows.last.line;
    final overlap = last == null ? 0.0 : math.min(last.top + last.height, l.top + l.height) - math.max(last.top, l.top);
    // Solo pedazos uno al lado del otro: en una hoja torcida también se pisan las
    // cajas de dos renglones seguidos, y juntarlos desordenaría el texto.
    final sideways = last == null
        ? 0.0
        : math.min(last.left + last.width, l.left + l.width) - math.max(last.left, l.left);
    if (last != null &&
        overlap >= 0.5 * math.min(last.height, l.height) &&
        sideways < _sideBySide * math.min(last.width, l.width)) {
      final lastFirst = last.left <= l.left;
      final (a, b) = lastFirst ? (last, l) : (l, last);
      final (boldA, boldB) = lastFirst ? (rows.last.bold, piece.bold) : (piece.bold, rows.last.bold);
      final right = math.max(a.left + a.width, b.left + b.width);
      rows.last = (
        line: (
          text: '${a.text} ${b.text}',
          left: a.left,
          top: math.min(a.top, b.top),
          width: right - a.left,
          height: math.max(a.height, b.height),
        ),
        bold: boldA == null || boldB == null ? null : [...boldA, ...boldB],
      );
    } else {
      rows.add(piece);
    }
  }
  return [for (final r in rows) _cleanRow(r.line, r.bold)];
}

({ScannedLine line, List<bool>? bold}) _cleanRow(ScannedLine l, List<bool>? bold) {
  final text = _cleanText(l.text);
  return (
    line: (text: text, left: l.left, top: l.top, width: l.width, height: l.height),
    bold: _fitBold(bold, text.split(' ').length),
  );
}

/// Una viñeta pegada se separa al limpiar: es una palabra más, sin negrita.
List<bool>? _fitBold(List<bool>? bold, int words) {
  if (bold == null) return null;
  if (bold.length == words) return bold;
  return bold.length + 1 == words ? [false, ...bold] : null;
}

/// Las viñetas que el lector confunde entre sí quedan todas iguales.
String _cleanText(String text) {
  final clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return clean.replaceFirst(RegExp(r'^[>»·•➢] ?'), '» ');
}

/// La sangría de cada renglón, de 0 a 1 del ancho: las parecidas se igualan.
List<double> _indents(List<ScannedLine> rows, double blockLeft, double blockWidth) {
  final order = List.generate(rows.length, (i) => i)..sort((a, b) => rows[a].left.compareTo(rows[b].left));
  final out = List<double>.filled(rows.length, 0);
  var group = <int>[];
  void close() {
    if (group.isEmpty) return;
    final middle = rows[group[group.length ~/ 2]].left;
    final indent = group.first == order.first ? 0.0 : (middle - blockLeft) / blockWidth;
    for (final i in group) {
      out[i] = indent;
    }
    group = [];
  }

  for (final i in order) {
    if (group.isNotEmpty && rows[i].left - rows[group.last].left > _sameIndent * blockWidth) close();
    group.add(i);
  }
  close();
  return out;
}

/// Todas las viñetas a la misma sangría: si el lector no vio la viñeta, su caja
/// empieza recién en el texto.
List<double> _sameBulletIndent(List<ScannedLine> rows, List<double> indents) {
  final bullets = [
    for (var i = 0; i < rows.length; i++)
      if (rows[i].text.startsWith('» ')) indents[i],
  ];
  if (bullets.isEmpty) return indents;
  final left = bullets.reduce(math.min);
  return [for (var i = 0; i < rows.length; i++) rows[i].text.startsWith('» ') ? left : indents[i]];
}

/// El borde derecho de los renglones largos (donde termina un texto justificado).
double _justifiedRight(List<ScannedLine> rows, double blockWidth) {
  final rights = [
    for (final r in rows)
      if (r.width >= 0.7 * blockWidth) r.left + r.width,
  ]..sort();
  return rights.isEmpty ? double.infinity : rights[rights.length ~/ 2];
}

/// Solo mayúsculas y sin números, como un título (una placa no lo es): el
/// lector no dice cuál texto va en negrita.
bool _isHeading(String text) {
  if (text.contains(RegExp(r'\d'))) return false;
  final letters = text.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ]'), '');
  return letters.length >= 3 && letters == letters.toUpperCase();
}
