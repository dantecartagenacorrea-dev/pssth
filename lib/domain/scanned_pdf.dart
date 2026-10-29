import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Una línea reconocida en la foto de una página: su texto y dónde está, en
/// fracciones de la imagen (0–1, origen arriba a la izquierda).
typedef ScannedLine = ({String text, double left, double top, double width, double height});

/// Una página escaneada: la foto (JPEG) y las líneas que se leyeron en ella.
typedef ScannedPage = ({Uint8List jpeg, int width, int height, List<ScannedLine> lines});

/// Ancho de cada página del PDF, en puntos (el de una hoja A4).
/// Hoja carta (21,6 × 27,9 cm), en puntos: cada página escaneada va entera y
/// centrada en una, sin deformarse, lista para imprimir en carta.
const _letter = PdfPageFormat.letter;

/// Arma un PDF con cada foto en una hoja carta y, encima, el texto reconocido
/// invisible en el mismo lugar: se ve la foto, pero el texto se puede buscar,
/// seleccionar y copiar en cualquier visor. [compress] en false solo para
/// pruebas (deja el texto legible en el archivo).
Future<Uint8List> buildScannedPdf(List<ScannedPage> pages, {String? title, bool compress = true}) {
  final doc = pw.Document(title: title, creator: 'PSSTH!', compress: compress);
  for (final page in pages) {
    // Lo más grande que entra en la hoja sin cambiar la proporción.
    final fit = math.min(_letter.width / page.width, _letter.height / page.height);
    final w = page.width * fit, h = page.height * fit;
    final left = (_letter.width - w) / 2, top = (_letter.height - h) / 2;
    final image = pw.MemoryImage(page.jpeg);
    doc.addPage(
      pw.Page(
        pageFormat: _letter,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            pw.Positioned(left: left, top: top, child: pw.Image(image, width: w, height: h, fit: pw.BoxFit.fill)),
            for (final line in page.lines)
              if (line.text.trim().isNotEmpty && line.width > 0 && line.height > 0)
                pw.Positioned(
                  left: left + line.left * w,
                  top: top + line.top * h,
                  // El texto se estira para cubrir la línea de la foto: al
                  // seleccionarlo, el resaltado coincide con lo que se ve.
                  child: pw.SizedBox(
                    width: line.width * w,
                    height: line.height * h,
                    child: pw.FittedBox(
                      fit: pw.BoxFit.fill,
                      child: pw.Text(
                        latin1Safe(line.text),
                        style: const pw.TextStyle(renderingMode: PdfTextRenderingMode.invisible),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

/// La letra estándar del PDF (Helvetica) solo trae los caracteres de Europa
/// occidental: los demás se cambian por su equivalente más cercano.
String latin1Safe(String text) {
  const swaps = {
    '“': '"', '”': '"', '„': '"', '‘': "'", '’': "'", '‚': "'",
    '–': '-', '—': '-', '−': '-', '…': '...', '•': '·', '€': 'EUR',
  };
  final out = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    if (rune < 0x20) {
      out.write(' ');
    } else if (rune <= 0xFF) {
      out.write(ch);
    } else {
      out.write(swaps[ch] ?? '?');
    }
  }
  return out.toString();
}

/// Nombre sugerido para el PDF, con fecha y hora: "Escaneo 2026-10-28 00-45".
String defaultScanName(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'Escaneo ${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}-${two(now.minute)}';
}

/// Nombre de archivo válido a partir de lo que escribió el usuario.
String safePdfFileName(String name, DateTime now) {
  var clean = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
  if (clean.toLowerCase().endsWith('.pdf')) clean = clean.substring(0, clean.length - 4).trim();
  if (clean.isEmpty) clean = defaultScanName(now);
  return '$clean.pdf';
}
