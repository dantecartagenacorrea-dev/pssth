// En la máquina macOS de GitHub las pruebas no encuentran la biblioteca
// PDFium (en el iPhone sí viene dentro de la app).
@TestOn('!mac-os')
library;

import 'dart:io';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/pdf_editor.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

/// PDF de prueba con una palabra por página ("Uno", "Dos"…).
Future<File> samplePdf(Directory dir, List<String> words, {String name = 'muestra.pdf'}) async {
  final doc = pw.Document();
  for (final w in words) {
    doc.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text(w, style: const pw.TextStyle(fontSize: 40)))));
  }
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(await doc.save());
  return file;
}

/// Abre los bytes guardados y devuelve el texto y el giro de cada página.
Future<List<({String text, PdfPageRotation rotation})>> reread(Directory dir, List<int> bytes) async {
  final file = File('${dir.path}/salida_${DateTime.now().microsecondsSinceEpoch}.pdf');
  await file.writeAsBytes(bytes);
  final doc = await PdfDocument.openFile(file.path);
  try {
    return [
      for (final p in doc.pages) (text: (await p.loadText())?.fullText.trim() ?? '', rotation: p.rotation),
    ];
  } finally {
    await doc.dispose();
  }
}

void main() {
  late Directory dir;
  setUpAll(() async => pdfrxInitialize());
  setUp(() => dir = Directory.systemTemp.createTempSync('editar_pdf'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows suelta los archivos un poco después.
    }
  });

  test('organiza páginas: gira, quita, mueve y une otro PDF sin tocar el original', () async {
    final src = await samplePdf(dir, ['Uno', 'Dos', 'Tres']);
    final original = src.readAsBytesSync();
    final other = await samplePdf(dir, ['Cuatro'], name: 'otro.pdf');
    final ed = await PdfEditor.openFile(src.path);
    expect(ed.signed, isFalse);
    await ed.rotate(0);
    await ed.removePage(1); // "Dos"
    await ed.movePage(1, 0); // "Tres" primero
    await ed.appendFile(other.path);
    final pages = await reread(dir, await ed.save());
    await ed.dispose();
    expect(pages.map((p) => p.text), ['Tres', 'Uno', 'Cuatro']);
    expect(pages[1].rotation, PdfPageRotation.clockwise90);
    expect(pages[0].rotation, PdfPageRotation.none);
    expect(src.readAsBytesSync(), original);
  });

  test('corta páginas de un documento y las pega en otro', () async {
    final a = await samplePdf(dir, ['Uno', 'Dos', 'Tres'], name: 'a.pdf');
    final b = await samplePdf(dir, ['Alfa', 'Beta'], name: 'b.pdf');
    final original = a.readAsBytesSync();
    final ea = await PdfEditor.openFile(a.path);
    expect(ea.locked, isFalse);
    final clip = await ea.cutPages([2, 0], dir); // Tres y Uno
    expect(PageClip.current.value, same(clip));
    expect((await reread(dir, await ea.save())).map((p) => p.text), ['Dos']);
    await ea.dispose();

    final eb = await PdfEditor.openFile(b.path);
    await eb.pastePages(clip, at: 1); // entre Alfa y Beta, en su orden
    expect((await reread(dir, await eb.save())).map((p) => p.text), ['Alfa', 'Uno', 'Tres', 'Beta']);
    await eb.dispose();
    expect(a.readAsBytesSync(), original);
  });

  test('copia y pega en el mismo documento; quita y gira varias', () async {
    final src = await samplePdf(dir, ['Uno', 'Dos', 'Tres']);
    final ed = await PdfEditor.openFile(src.path);
    final clip = await ed.copyPages([1], dir);
    await ed.pastePages(clip); // al final
    await ed.rotatePages([0, 3]);
    await ed.removePages([2]);
    final pages = await reread(dir, await ed.save());
    await ed.dispose();
    expect(pages.map((p) => p.text), ['Uno', 'Dos', 'Dos']);
    expect(pages.map((p) => p.rotation), [
      PdfPageRotation.clockwise90,
      PdfPageRotation.none,
      PdfPageRotation.clockwise90,
    ]);
  });

  test('no deja cortar todas las páginas', () async {
    final src = await samplePdf(dir, ['Uno', 'Dos']);
    final ed = await PdfEditor.openFile(src.path);
    await expectLater(ed.cutPages([0, 1], dir), throwsStateError);
    await ed.removePages([0, 1]);
    expect(ed.pageCount, 2);
    await ed.dispose();
  });

  test('deshace el orden de las páginas', () async {
    final src = await samplePdf(dir, ['Uno', 'Dos']);
    final ed = await PdfEditor.openFile(src.path);
    await ed.movePage(0, 1);
    await ed.removePage(0);
    expect(ed.pageCount, 1);
    await ed.undo();
    await ed.undo();
    expect(ed.canUndo, isFalse);
    final pages = await reread(dir, await ed.save());
    await ed.dispose();
    expect(pages.map((p) => p.text), ['Uno', 'Dos']);
  });

  test('escribe y corrige texto que después se puede leer', () async {
    final src = await samplePdf(dir, ['Uno', 'Dos']);
    final ed = await PdfEditor.openFile(src.path);
    await ed.addText(0, const Offset(0.1, 0.1), 'Revisado por Dante\nsegunda línea ñandú', size: 14);
    await ed.correct(1, const Rect.fromLTWH(0.3, 0.45, 0.4, 0.1), 'Corregido');
    final pages = await reread(dir, await ed.save());
    await ed.dispose();
    expect(pages[0].text, contains('Revisado por Dante'));
    expect(pages[0].text, contains('segunda línea ñandú'));
    expect(pages[1].text, contains('Corregido'));
  });

  test('anota y deshace lo último', () async {
    final src = await samplePdf(dir, ['Uno']);
    final ed = await PdfEditor.openFile(src.path);
    await ed.highlight(0, const Rect.fromLTWH(0.3, 0.4, 0.4, 0.1));
    await ed.ink(0, [
      [const Offset(0.1, 0.8), const Offset(0.3, 0.85), const Offset(0.5, 0.8)],
    ]);
    await ed.note(0, const Offset(0.9, 0.1), 'Repasar');
    await ed.addText(0, const Offset(0.1, 0.1), 'Borrar esto');
    await ed.undo(); // el texto
    await ed.undo(); // la nota
    final bytes = await ed.save();
    await ed.dispose();
    final pages = await reread(dir, bytes);
    expect(pages.single.text, isNot(contains('Borrar esto')));
    final file = File('${dir.path}/anotado.pdf')..writeAsBytesSync(bytes);
    final again = await PdfDocument.openFile(file.path);
    // Quedan el resaltado y el trazo (la nota se deshizo).
    final kinds = await PdfEditor.annotationKinds(again, 0);
    await again.dispose();
    expect(kinds, ['highlight', 'ink']);
  });
}
