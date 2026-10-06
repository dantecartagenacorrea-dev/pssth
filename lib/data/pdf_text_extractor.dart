import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/app_exception.dart';
import '../domain/chunk_builder.dart';
import '../domain/column_order.dart';
import '../domain/page_cleaner.dart';
import '../domain/text_chunk.dart';
import '../domain/text_normalizer.dart';

const int kExtractionVersion = 2; // 2: orden en columnas

class ExtractedPdf {
  ExtractedPdf({
    required this.pageCount,
    required this.pages,
    required this.chunks,
    required this.scannedPages,
  });

  final int pageCount;

  /// Texto limpio por página (original, sin normalizar para voz).
  final List<String> pages;
  final List<TextChunk> chunks;

  /// Páginas sin texto utilizable (candidatas a OCR).
  final List<int> scannedPages;
  bool get hasText => chunks.isNotEmpty;
}

class PdfTextExtractor {
  PdfTextExtractor({required this.cacheDir});

  final Directory cacheDir;

  File _cacheFile(String documentId) =>
      File('${cacheDir.path}/$documentId.text.json');

  /// Extrae el texto una sola vez y lo guarda en caché local.
  /// Las aperturas siguientes leen la caché y no reprocesan el PDF.
  Future<ExtractedPdf> extract({
    required String filePath,
    required String documentId,
    TextNormalizer? normalizer,
  }) async {
    final norm = normalizer ?? TextNormalizer();
    final pages = await loadPages(filePath: filePath, documentId: documentId);
    final chunks = buildChunks(
      documentId: documentId,
      pages: pages,
      normalizer: norm,
    );
    final scanned = <int>[
      for (var i = 0; i < pages.length; i++)
        if (pageNeedsOcr(pages[i])) i,
    ];
    return ExtractedPdf(
      pageCount: pages.length,
      pages: pages,
      chunks: chunks,
      scannedPages: scanned,
    );
  }

  /// Texto limpio por página, desde la caché si existe.
  Future<List<String>> loadPages({
    required String filePath,
    required String documentId,
  }) async {
    final cached = await _readCache(documentId);
    if (cached != null) return cached;
    final pages = await _extractPages(filePath);
    await _writeCache(documentId, pages);
    return pages;
  }

  Future<List<String>> _extractPages(String filePath) async {
    await pdfrxFlutterInitialize();
    PdfDocument? document;
    try {
      document = await PdfDocument.openFile(
        filePath,
        passwordProvider: () => null,
        firstAttemptByEmptyPassword: true,
      );
      final raw = <String>[];
      for (var i = 0; i < document.pages.length; i++) {
        final page = await document.pages[i].ensureLoaded();
        final text = await page.loadStructuredText();
        raw.add(_pageTextInReadingOrder(page, text));
      }
      return PageCleaner.clean(raw);
    } on PdfPasswordException {
      throw AppException(
        'Este PDF está protegido con contraseña y no se puede leer.',
      );
    } on PdfException {
      throw AppException(
        'No se pudo abrir el PDF. El archivo puede ser inválido o no compatible.',
      );
    } catch (error) {
      if (error is AppException) {
        rethrow;
      }
      throw AppException('No se pudo extraer el texto del PDF.');
    } finally {
      await document?.dispose();
    }
  }

  /// Texto de la página; si hay dos columnas claras, en orden de lectura.
  static String _pageTextInReadingOrder(PdfPage page, PdfPageText text) {
    try {
      final rects = [
        for (final c in text.charRects) CharRect(c.left, c.top, c.right, c.bottom),
      ];
      final boxes = boxesFromChars(text.fullText, rects);
      final ordered = reorderColumns(boxes, page.width);
      if (kDebugMode) {
        final sample = boxes.take(6).map((b) => '"${b.text.length > 12 ? b.text.substring(0, 12) : b.text}"@${b.left.toStringAsFixed(0)},${b.top.toStringAsFixed(0)}-${b.right.toStringAsFixed(0)},${b.bottom.toStringAsFixed(0)}').join(' ');
        debugPrint('[lector] pag ${page.pageNumber} w=${page.width.toStringAsFixed(0)} chars=${text.fullText.length} rects=${rects.length} boxes=${boxes.length} columnas=${ordered != null} $sample');
      }
      return ordered ?? text.fullText;
    } catch (_) {
      return text.fullText;
    }
  }

  Future<List<String>?> _readCache(String documentId) async {
    try {
      final f = _cacheFile(documentId);
      if (!await f.exists()) return null;
      final json = jsonDecode(await f.readAsString());
      if (json is! Map || json['version'] != kExtractionVersion) return null;
      final pages = json['pages'];
      if (pages is! List) return null;
      return pages.map((e) => '$e').toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String documentId, List<String> pages) async {
    try {
      await _cacheFile(documentId).writeAsString(
        jsonEncode({'version': kExtractionVersion, 'pages': pages}),
        flush: true,
      );
    } catch (_) {
      // La caché es opcional: si falla, se reextrae la próxima vez.
    }
  }
}
