import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

/// Renderiza páginas de un PDF a PNG para enviarlas al OCR.
class PdfPageRenderer {
  PdfPageRenderer._(this._doc);
  final PdfDocument _doc;

  static Future<PdfPageRenderer> open(String path) async {
    await pdfrxFlutterInitialize();
    final doc = await PdfDocument.openFile(path);
    return PdfPageRenderer._(doc);
  }

  Future<String> renderToPng(
    int pageIndex,
    String outPath, {
    double longSide = 2200,
  }) async {
    final page = _doc.pages[pageIndex];
    final scale = longSide / math.max(page.width, page.height);
    final w = (page.width * scale).round();
    final h = (page.height * scale).round();
    final img = await page.render(
      fullWidth: w.toDouble(),
      fullHeight: h.toDouble(),
    );
    if (img == null) {
      throw StateError('No se pudo renderizar la página ${pageIndex + 1}.');
    }
    try {
      final uiImage = await img.createImage();
      final data = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      uiImage.dispose();
      if (data == null) {
        throw StateError('No se pudo codificar la página ${pageIndex + 1}.');
      }
      await File(outPath).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    } finally {
      img.dispose();
    }
    return outPath;
  }

  Future<void> close() => _doc.dispose();
}
