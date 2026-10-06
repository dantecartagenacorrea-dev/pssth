import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/epub_reader.dart';

List<int> buildEpub({bool encrypted = false}) {
  final a = Archive();
  void add(String name, String content) {
    final b = utf8.encode(content);
    a.addFile(ArchiveFile(name, b.length, b));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml',
      '<container><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="x"/></rootfiles></container>');
  if (encrypted) {
    add('META-INF/encryption.xml', '<encryption><EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#"/></encryption>');
  }
  add('OEBPS/content.opf', '''
<package><manifest>
<item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>
<item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>
<item id="c2" href="text/c%202.xhtml" media-type="application/xhtml+xml"/>
</manifest><spine><itemref idref="cover"/><itemref idref="c1"/><itemref idref="c2"/></spine></package>''');
  add('OEBPS/cover.xhtml', '<html><body><img src="x.jpg"/></body></html>');
  add('OEBPS/text/c1.xhtml',
      '<html><head><title>x</title><style>p{}</style></head><body><h1>Capítulo uno</h1><p>Era una noche oscura &amp; tormentosa en la ciudad.</p><p>Segundo p&#225;rrafo del cap&iacute;tulo.</p></body></html>');
  add('OEBPS/text/c 2.xhtml',
      '<html><body><h2>Capítulo dos</h2><p>Llegó la mañana y todo cambió para los protagonistas.</p></body></html>');
  return ZipEncoder().encode(a);
}

void main() {
  test('lee EPUB: orden, capítulos, entidades y omite portada', () {
    final book = readEpub(buildEpub());
    expect(book.pages.length, 2);
    expect(book.pages.first, contains('noche oscura & tormentosa'));
    expect(book.pages.first, contains('párrafo'));
    expect(book.pages.first, isNot(contains('<')));
    expect(book.chapters.map((c) => c.title), ['Capítulo uno', 'Capítulo dos']);
    expect(book.chapters.map((c) => c.pageIndex), [0, 1]);
  });

  test('EPUB protegido se rechaza', () {
    expect(() => readEpub(buildEpub(encrypted: true)), throwsA(isA<EpubException>()));
  });

  test('archivo corrupto se rechaza con mensaje', () {
    expect(() => readEpub([1, 2, 3, 4]), throwsA(isA<EpubException>()));
  });

  test('htmlToText conserva párrafos', () {
    expect(htmlToText('<p>Uno</p><p>Dos&nbsp;tres</p>'), 'Uno\n\nDos tres');
  });
}
