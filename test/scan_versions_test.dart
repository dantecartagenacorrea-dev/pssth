import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lector_pdf/data/library_store.dart';
import 'package:lector_pdf/data/scan_version_builder.dart';
import 'package:lector_pdf/domain/library_entry.dart';
import 'package:lector_pdf/domain/retyped_pdf.dart';
import 'package:lector_pdf/domain/scan_filters.dart';
import 'package:lector_pdf/domain/scanned_pdf.dart';
import 'package:lector_pdf/domain/text_chunk.dart';
import 'package:lector_pdf/ui/scan_versions_screen.dart';

LibraryEntry _entry({String kind = 'pdf', bool scanned = false, String? original, String? clean}) => LibraryEntry(
  id: '1',
  name: 'hoja.pdf',
  storedPath: 'guardado',
  pageCount: 2,
  totalChunks: 0,
  kind: kind,
  scanned: scanned,
  originalPath: original,
  cleanPath: clean,
);

TextChunk _chunk(int page, int index, String text) =>
    TextChunk(documentId: '1', pageIndex: page, chunkIndex: index, text: text);

void main() {
  group('vistas de cada documento', () {
    test('un PDF importado: su original y en limpio', () {
      expect(_entry().scanVersions, [ScanVersion.original, ScanVersion.clean]);
      expect(_entry().versionPath(ScanVersion.original), 'guardado');
      expect(_entry().versionPath(ScanVersion.clean), isNull);
    });

    test('una foto importada: las tres', () {
      expect(_entry(kind: 'image').scanVersions, ScanVersion.values);
      expect(_entry(kind: 'image').versionPath(ScanVersion.scanned), isNull);
    });

    test('un escaneo nuevo las tres; uno anterior no ofrece el original', () {
      expect(_entry(scanned: true, original: 'o').scanVersions, ScanVersion.values);
      expect(_entry(scanned: true).scanVersions, [ScanVersion.scanned, ScanVersion.clean]);
      expect(_entry(scanned: true).versionPath(ScanVersion.scanned), 'guardado');
    });

    test('un texto no tiene vistas', () {
      expect(_entry(kind: 'txt').scanVersions, isEmpty);
    });

    test('se recuerdan al volver a abrir la biblioteca', () {
      final entry = _entry(kind: 'image', original: 'o', clean: 'c')..scanCopyPath = 'e';
      final back = LibraryEntry.fromJson(entry.toJson());
      expect(back.originalPath, 'o');
      expect(back.cleanPath, 'c');
      expect(back.scanCopyPath, 'e');
    });
  });

  group('guardado', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('versiones'));
    tearDown(() => dir.delete(recursive: true));

    test('quedan al lado del documento y se borran con él', () async {
      final store = LibraryStore();
      await store.initAt(dir);
      final entry = await store.importFile(originalName: 'a.pdf', bytes: [1, 2], scanned: true);
      await store.attachScanVersions(entry, original: [3], clean: [4]);
      expect(await File(entry.originalPath!).readAsBytes(), [3]);
      expect(await File(entry.cleanPath!).readAsBytes(), [4]);

      final again = LibraryStore();
      await again.initAt(dir);
      expect(again.data.entries.single.scanVersions, hasLength(3));

      await again.remove(entry.id);
      expect(dir.listSync().whereType<File>().where((f) => f.path.contains(entry.id)), isEmpty);
    });

    test('la foto original se achica, también si es PNG', () async {
      final path = '${dir.path}/foto.png';
      await File(path).writeAsBytes(Uint8List.fromList(img.encodePng(img.Image(width: 4000, height: 3000))));
      final page = await originalScanPage(path);
      expect((page.width, page.height), (2200, 1650));
    });

    ScanVersionBuilder builder(
      LibraryStore store, {
      List<TextChunk> chunks = const [],
      int pages = 1,
      List<ScannedLine> lines = const [],
    }) => ScanVersionBuilder(
      store: store,
      recognize: (_) async => lines,
      chunks: () => chunks,
      pageCount: () => pages,
      openPages: (_) => throw const FileSystemException('sin renderizador'),
    );

    Future<(LibraryStore, LibraryEntry)> imported(String name, List<int> bytes) async {
      final store = LibraryStore();
      await store.initAt(dir);
      return (store, await store.importFile(originalName: name, bytes: bytes));
    }

    test('«En limpio» de un PDF sale del texto leído y queda guardado', () async {
      final (store, entry) = await imported('a.pdf', [1]);
      final b = builder(store, chunks: [_chunk(0, 0, 'Hola mundo.')].map((c) => TextChunk(
        documentId: entry.id, pageIndex: c.pageIndex, chunkIndex: c.chunkIndex, text: c.text,
      )).toList());
      final path = await b.prepare(entry, ScanVersion.clean);
      expect(path, entry.cleanPath);
      expect(await File(path).length(), greaterThan(100));
    });

    test('si falta leer páginas, muestra lo que hay sin guardarlo como final', () async {
      final (store, entry) = await imported('a.pdf', [1]);
      final b = builder(store, pages: 5, chunks: [
        TextChunk(documentId: entry.id, pageIndex: 0, chunkIndex: 0, text: 'Hola.'),
      ]);
      final path = await b.prepare(entry, ScanVersion.clean);
      expect(await File(path).exists(), isTrue);
      expect(entry.cleanPath, isNull);
    });

    test('sin texto leído no inventa una versión', () async {
      final (store, entry) = await imported('a.pdf', [1]);
      await expectLater(builder(store).prepare(entry, ScanVersion.clean), throwsFormatException);
      expect(entry.cleanPath, isNull);
    });

    test('una foto da su copia escaneada y su transcripción, sin dejar temporales', () async {
      final photo = img.Image(width: 300, height: 400);
      img.fill(photo, color: img.ColorRgb8(255, 255, 255));
      final (store, entry) = await imported('foto.jpg', img.encodeJpg(photo));
      final b = builder(store, lines: const [(text: 'Nombre', left: 0.1, top: 0.1, width: 0.3, height: 0.05)]);
      expect(await File(await b.prepare(entry, ScanVersion.scanned)).exists(), isTrue);
      expect(await File(await b.prepare(entry, ScanVersion.clean)).exists(), isTrue);
      expect(entry.scanCopyPath, isNotNull);
      expect(entry.cleanPath, isNotNull);
      expect(dir.listSync().where((f) => f.path.contains('temporal')), isEmpty);
    });

    test('la hoja se recorta alrededor del texto, sin la mesa', () {
      final box = sheetAround(const [
        (text: 'Primera línea', left: 0.3, top: 0.3, width: 0.4, height: 0.02),
        (text: 'Última línea', left: 0.3, top: 0.7, width: 0.4, height: 0.02),
        (text: '.', left: 0.01, top: 0.01, width: 0.01, height: 0.01),
      ])!;
      expect(box.left, closeTo(0.268, 0.001));
      expect(box.top, closeTo(0.267, 0.001));
      expect(box.right, closeTo(0.732, 0.001));
      expect(box.bottom, closeTo(0.753, 0.001));
    });

    test('el recorte incluye las líneas del formulario y no las de la mesa', () {
      const text = [
        (text: 'Primera línea', left: 0.3, top: 0.3, width: 0.4, height: 0.02),
        (text: 'Última línea', left: 0.3, top: 0.7, width: 0.4, height: 0.02),
      ];
      const tableBottom = (x0: 0.25, y0: 0.75, x1: 0.75, y1: 0.75, weight: 0.002);
      const tableSide = (x0: 0.22, y0: 0.3, x1: 0.22, y1: 0.7, weight: 0.002);
      const onTheTable = (x0: 0.8, y0: 0.9, x1: 0.95, y1: 0.9, weight: 0.002);
      const tableTop = (x0: 0.25, y0: 0.28, x1: 0.75, y1: 0.28, weight: 0.002);
      expect(
        sheetAround(text, rules: const [tableSide])!.left,
        closeTo(0.268, 0.001),
        reason: 'una raya vertical suelta es el borde del papel',
      );
      final box = sheetAround(text, rules: const [tableTop, tableBottom, tableSide, onTheTable])!;
      expect(box.left, lessThan(0.22));
      expect(box.bottom, greaterThan(0.75));
      expect(box.right, lessThan(0.8));
      expect(box.bottom, lessThan(0.85));
    });

    test('con muy poco texto no se recorta', () {
      expect(sheetAround(const [(text: 'Nombre', left: 0.1, top: 0.1, width: 0.3, height: 0.05)]), isNull);
      expect(sheetAround(const []), isNull);
    });

    test('al recortar se vuelve a leer: las posiciones son de la hoja', () async {
      final photo = img.Image(width: 1000, height: 1000);
      img.fill(photo, color: img.ColorRgb8(255, 255, 255));
      final (store, entry) = await imported('foto.jpg', img.encodeJpg(photo));
      final sizes = <int>[];
      final b = ScanVersionBuilder(
        store: store,
        chunks: () => const [],
        pageCount: () => 1,
        openPages: (_) => throw const FileSystemException('sin renderizador'),
        recognize: (path) async {
          sizes.add(img.decodeJpg(await File(path).readAsBytes())!.width);
          return const [
            (text: 'Primera línea', left: 0.3, top: 0.3, width: 0.4, height: 0.02),
            (text: 'Última línea', left: 0.3, top: 0.7, width: 0.4, height: 0.02),
          ];
        },
      );
      await b.prepare(entry, ScanVersion.scanned);
      await b.prepare(entry, ScanVersion.clean);
      expect(sizes, [1000, 464], reason: 'dos lecturas, una sola vez aunque se armen dos vistas');
    });

    test('un PDF escaneado se relee página por página y no deja temporales', () async {
      final store = LibraryStore();
      await store.initAt(dir);
      final entry = await store.importFile(originalName: 'e.pdf', bytes: [1], scanned: true);
      final white = img.Image(width: 300, height: 400);
      img.fill(white, color: img.ColorRgb8(255, 255, 255));
      var closed = false, reads = 0;
      final b = ScanVersionBuilder(
        store: store,
        chunks: () => const [],
        pageCount: () => 2,
        recognize: (_) async {
          reads++;
          return const [(text: 'Nombre', left: 0.1, top: 0.1, width: 0.3, height: 0.05)];
        },
        openPages: (_) async => (
          count: 2,
          close: () async => closed = true,
          render: (int page, String out) async {
            await File(out).writeAsBytes(img.encodePng(white));
            return out;
          },
        ),
      );
      expect(await File(await b.prepare(entry, ScanVersion.clean)).exists(), isTrue);
      expect(reads, 2);
      expect(closed, isTrue);
      expect(entry.cleanPath, isNotNull);
      expect(dir.listSync().where((f) => f.path.contains('temporal')), isEmpty);
    });

    test('si no se puede releer, usa el texto ya leído', () async {
      final store = LibraryStore();
      await store.initAt(dir);
      final entry = await store.importFile(originalName: 'e.pdf', bytes: [1], scanned: true);
      final b = ScanVersionBuilder(
        store: store,
        chunks: () => [TextChunk(documentId: entry.id, pageIndex: 0, chunkIndex: 0, text: 'Hola.')],
        pageCount: () => 1,
        recognize: (_) async => const [],
        openPages: (_) => throw const FileSystemException('dañado'),
      );
      expect(await File(await b.prepare(entry, ScanVersion.clean)).exists(), isTrue);
      expect(entry.cleanPath, isNotNull);
    });

    test('el texto leído sale completo y en orden en el PDF', () async {
      final pages = pagesFromChunks([_chunk(1, 0, 'Segunda'), _chunk(0, 0, 'Primera'), _chunk(0, 1, '  ')]);
      expect(pages, hasLength(2));
      final raw = latin1.decode(await buildRetypedPdf(pages, compress: false));
      expect(raw.indexOf('Primera'), lessThan(raw.indexOf('Segunda')));
      expect(raw.indexOf('Primera'), greaterThanOrEqualTo(0));
    });
  });

  test('una trama que une las letras con el fondo no se lleva las letras', () async {
    // Letras negras sobre una trama gris que toca el borde, como el muaré de una
    // pantalla fotografiada: antes se iba todo junto.
    const w = 400, h = 300;
    final photo = img.Image(width: w, height: h);
    img.fill(photo, color: img.ColorRgb8(255, 255, 255));
    for (var y = 0; y < h; y += 6) {
      img.drawLine(photo, x1: 0, y1: y, x2: w - 1, y2: y, color: img.ColorRgb8(170, 170, 170));
    }
    img.fillRect(photo, x1: 100, y1: 120, x2: 112, y2: 160, color: img.ColorRgb8(0, 0, 0));
    img.fillRect(photo, x1: 140, y1: 120, x2: 152, y2: 160, color: img.ColorRgb8(0, 0, 0));
    final out = await applyScanFilter(Uint8List.fromList(img.encodeJpg(photo, quality: 95)), ScanFilter.limpio);
    final clean = img.decodeJpg(out.jpeg)!;
    final sx = clean.width / w, sy = clean.height / h;
    expect(clean.getPixel((106 * sx).round(), (140 * sy).round()).luminance, lessThan(100));
    expect(clean.getPixel((146 * sx).round(), (140 * sy).round()).luminance, lessThan(100));
  });

  group('pantalla', () {
    final closed = <String>[];
    setUp(closed.clear);

    Future<ScanDocument> open(String path) async => (
      pageCount: path == 'o' ? 1 : 2,
      page: (int i) => Text('$path-$i'),
      close: () async => closed.add(path),
    );

    Future<String> paths(ScanVersion v) async => switch (v) {
      ScanVersion.original => 'o',
      ScanVersion.scanned => 'escaneado',
      ScanVersion.clean => 'c',
    };

    testWidgets('al cambiar de vista sigue en la misma página y cierra la anterior', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScanVersionsScreen(
            entry: _entry(scanned: true, original: 'o'),
            initial: ScanVersion.scanned,
            initialPage: 1,
            open: open,
            prepare: paths,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('escaneado-1'), findsOneWidget);

      await tester.tap(find.text('En limpio'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('c-1'), findsOneWidget);
      expect(closed, ['escaneado']);
    });

    testWidgets('si la otra vista tiene menos páginas, va a la última', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScanVersionsScreen(
            entry: _entry(scanned: true, original: 'o'),
            initial: ScanVersion.scanned,
            initialPage: 1,
            open: open,
            prepare: paths,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Original'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('o-0'), findsOneWidget);
      expect(find.text('Página 1 de 1'), findsOneWidget);
    });

    testWidgets('un PDF sin páginas avisa, no se comparte y se cierra', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScanVersionsScreen(
            entry: _entry(),
            initial: ScanVersion.original,
            prepare: paths,
            open: (path) async => (pageCount: 0, page: (int i) => const SizedBox(), close: () async => closed.add(path)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('No se pudo abrir esta versión.'), findsOneWidget);
      expect(closed, ['o']);
      expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    });

    testWidgets('si no se puede armar, avisa y se puede cambiar a otra', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScanVersionsScreen(
            entry: _entry(),
            initial: ScanVersion.clean,
            open: open,
            prepare: (v) => v == ScanVersion.clean ? Future.error(const FormatException('no')) : paths(v),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('No se pudo abrir esta versión.'), findsOneWidget);
      await tester.tap(find.text('Original'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('o-0'), findsOneWidget);
    });
  });
}
