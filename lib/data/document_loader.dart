import 'dart:io';

import '../domain/chapter_detector.dart';
import '../domain/chunk_builder.dart';
import '../domain/library_entry.dart';
import '../domain/text_paginator.dart';
import '../ocr/ocr_engine.dart';
import 'epub_reader.dart';
import 'ocr_cache.dart';
import 'pdf_page_renderer.dart';
import 'pdf_text_extractor.dart';

class LoadedDocument {
  LoadedDocument({required this.pages, required this.pendingOcr, this.chapters});

  /// Capítulos explícitos (EPUB). Si es null, se detectan desde el texto.
  final List<Chapter>? chapters;

  /// Texto por página (las páginas pendientes de OCR están vacías).
  final List<String> pages;

  /// Páginas sin texto y todavía sin OCR en caché.
  final List<int> pendingOcr;

  int get pageCount => pages.length;
  bool get hasAnyText => pages.any((p) => !pageNeedsOcr(p));
}

typedef OcrPageResult = ({int page, String text});

class DocumentLoader {
  DocumentLoader({required this.cacheDir, required this.ocr})
      : _pdf = PdfTextExtractor(cacheDir: cacheDir);

  final Directory cacheDir;
  final OcrEngine ocr;
  final PdfTextExtractor _pdf;

  File _ocrFile(String id) => File('${cacheDir.path}/$id.ocr.json');

  /// Carga rápida: texto directo + OCR ya cacheado. No ejecuta OCR nuevo.
  Future<LoadedDocument> load(LibraryEntry entry) async {
    final List<String> pages;
    List<Chapter>? chapters;
    switch (entry.kind) {
      case 'epub':
        final book = readEpub(await File(entry.storedPath).readAsBytes());
        pages = book.pages;
        chapters = book.chapters;
      case 'txt':
        pages = paginateText(decodeText(await File(entry.storedPath).readAsBytes()));
      case 'image':
        pages = [''];
      default:
        pages = List<String>.of(
          await _pdf.loadPages(filePath: entry.storedPath, documentId: entry.id),
        );
    }
    final cache = await OcrCache.open(_ocrFile(entry.id));
    final pending = <int>[];
    for (var i = 0; i < pages.length; i++) {
      if (!pageNeedsOcr(pages[i])) continue;
      if (cache.has(i)) {
        pages[i] = cache.get(i)!;
      } else if (entry.kind != 'txt' && entry.kind != 'epub') {
        pending.add(i);
      }
    }
    return LoadedDocument(pages: pages, pendingOcr: pending, chapters: chapters);
  }

  /// OCR progresivo: emite cada página al terminarla y la guarda en caché.
  Stream<OcrPageResult> runOcr(
    LibraryEntry entry,
    LoadedDocument doc, {
    List<String> languages = const [],
  }) async* {
    if (doc.pendingOcr.isEmpty) return;
    if (!await ocr.isAvailable()) throw OcrUnavailable();
    final cache = await OcrCache.open(_ocrFile(entry.id));
    PdfPageRenderer? renderer;
    try {
      for (final i in doc.pendingOcr) {
        String imagePath;
        var temp = false;
        if (entry.kind == 'image') {
          imagePath = entry.storedPath;
        } else {
          renderer ??= await PdfPageRenderer.open(entry.storedPath);
          imagePath = await renderer.renderToPng(
            i,
            '${cacheDir.path}/${entry.id}.p$i.png',
          );
          temp = true;
        }
        String text;
        try {
          text = await ocr.recognize(imagePath, languages: languages);
        } on OcrUnavailable {
          rethrow;
        } catch (_) {
          continue; // una página fallida no detiene el resto ni se cachea
        } finally {
          if (temp) {
            try {
              await File(imagePath).delete();
            } catch (_) {}
          }
        }
        await cache.put(i, text);
        yield (page: i, text: text);
      }
    } finally {
      await renderer?.close();
    }
  }
}
