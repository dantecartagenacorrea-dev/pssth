import 'dart:convert';

import 'package:archive/archive.dart';

import '../domain/chapter_detector.dart';
import '../domain/html_text.dart' show decodeHtmlEntities;
import '../domain/text_paginator.dart';

class EpubBook {
  EpubBook({required this.pages, required this.chapters});
  final List<String> pages;
  final List<Chapter> chapters;
}

class EpubException implements Exception {
  EpubException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Lector EPUB local (zip + XHTML). Sin red ni DRM: un EPUB protegido
/// produce texto ilegible y se rechaza con un mensaje claro.
EpubBook readEpub(List<int> bytes, {int pageChars = 3000}) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw EpubException('El archivo EPUB está dañado o no es válido.');
  }
  final files = <String, ArchiveFile>{
    for (final f in zip.files)
      if (f.isFile) f.name: f,
  };

  String read(String name) {
    final f = files[name];
    if (f == null) throw EpubException('EPUB incompleto: falta $name.');
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  if (files.containsKey('META-INF/encryption.xml') &&
      read('META-INF/encryption.xml').contains('http://www.w3.org/2001/04/xmlenc#')) {
    throw EpubException('Este EPUB está protegido y no se puede leer.');
  }

  final container = read('META-INF/container.xml');
  final opfPath = RegExp(r'full-path="([^"]+)"').firstMatch(container)?[1];
  if (opfPath == null) throw EpubException('EPUB sin índice de contenido.');
  final opf = read(opfPath);
  final base = opfPath.contains('/') ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1) : '';

  final manifest = <String, String>{};
  for (final m in RegExp(r'<item\b[^>]*>', caseSensitive: false).allMatches(opf)) {
    final tag = m[0]!;
    final id = _attr(tag, 'id');
    final href = _attr(tag, 'href');
    if (id != null && href != null) manifest[id] = Uri.decodeFull(href);
  }
  final spine = [
    for (final m in RegExp(r'<itemref\b[^>]*>', caseSensitive: false).allMatches(opf))
      if (_attr(m[0]!, 'idref') != null) _attr(m[0]!, 'idref')!,
  ];
  if (spine.isEmpty) throw EpubException('EPUB sin contenido legible.');

  final pages = <String>[];
  final chapters = <Chapter>[];
  for (final id in spine) {
    final href = manifest[id];
    if (href == null) continue;
    final path = _normalize('$base$href');
    final f = files[path];
    if (f == null) continue;
    final html = utf8.decode(f.content as List<int>, allowMalformed: true);
    final text = htmlToText(html);
    if (text.replaceAll(RegExp(r'\s'), '').length < 40) continue; // portada, vacíos
    final title = _firstHeading(html);
    final parts = paginateText(text, pageChars: pageChars);
    if (title != null) {
      chapters.add(Chapter(title: title, pageIndex: pages.length));
    }
    pages.addAll(parts);
  }
  if (pages.isEmpty) throw EpubException('El EPUB no contiene texto.');
  return EpubBook(pages: pages, chapters: chapters.length >= 2 ? chapters : const []);
}

String? _attr(String tag, String name) {
  final m = RegExp('\\b$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')', caseSensitive: false).firstMatch(tag);
  return m?[1] ?? m?[2];
}

String _normalize(String path) {
  final out = <String>[];
  for (final part in path.split('/')) {
    if (part == '..') {
      if (out.isNotEmpty) out.removeLast();
    } else if (part != '.' && part.isNotEmpty) {
      out.add(part);
    }
  }
  return out.join('/');
}

String? _firstHeading(String html) {
  final m = RegExp(r'<h[1-3][^>]*>(.*?)</h[1-3]>', caseSensitive: false, dotAll: true).firstMatch(html);
  if (m == null) return null;
  final t = htmlToText(m[1]!).replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty || t.length > 100 ? null : t;
}

/// Convierte XHTML en texto plano conservando párrafos.
String htmlToText(String html) {
  var t = html
      .replaceAll(RegExp(r'<(script|style|head)\b[^>]*>.*?</\1>', caseSensitive: false, dotAll: true), ' ')
      .replaceAll(RegExp(r'</(p|div|h[1-6]|li|tr|blockquote|section)>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  // El mismo traductor que las páginas web (el propio no sabía &ntilde;).
  t = decodeHtmlEntities(t);
  t = t
      .replaceAll(RegExp(r'[ \t\u00A0]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return t.trim();
}
