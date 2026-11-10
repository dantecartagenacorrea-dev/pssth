import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lector_pdf/domain/scan_filters.dart';
import 'package:lector_pdf/domain/scanned_pdf.dart';
import 'package:lector_pdf/domain/spanish_words.dart';
import 'package:lector_pdf/ui/scan_review_screen.dart';

void main() {
  testWidgets('agrega páginas y entrega el tamaño de hoja elegido', (tester) async {
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('revisar'));
    addTearDown(() => tester.runAsync(() => dir!.delete(recursive: true)));
    final paths = ['${dir!.path}/a.jpg', '${dir.path}/b.jpg'];
    for (final p in paths) {
      await tester.runAsync(
        () => File(p).writeAsBytes(Uint8List.fromList(img.encodeJpg(img.Image(width: 200, height: 300)))),
      );
    }
    ScanReview? review;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              review = await Navigator.of(context).push<ScanReview>(
                MaterialPageRoute(
                  builder: (_) => ScanReviewScreen(
                    paths: [paths.first],
                    recognize: (_) async => const <ScannedLine>[],
                    addPages: () async => [paths.last],
                  ),
                ),
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    for (final label in ['Limpio', 'Mejorar', 'B&N', 'Escala de grises', 'Original']) {
      expect(find.text(label), findsOneWidget, reason: 'cada filtro con su miniatura');
    }
    await tester.tap(find.byTooltip('Agregar páginas'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Página 2 de 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Tamaño y calidad del PDF'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Oficio'));
    await tester.pump();
    await tester.tap(find.text('Liviana'));
    await tester.pump();
    Navigator.of(tester.element(find.text('Oficio'))).pop();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('Listo'));
    for (var i = 0; i < 10 && review == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(review!.paths, paths);
    expect(review!.options.paper, ScanPaper.oficio);
  });

  testWidgets('lo leído sin IA sale revisado con el diccionario', (tester) async {
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('revisar'));
    addTearDown(() => tester.runAsync(() => dir!.delete(recursive: true)));
    final path = '${dir!.path}/hoja.jpg';
    await tester.runAsync(
      () => File(path).writeAsBytes(Uint8List.fromList(img.encodeJpg(img.Image(width: 200, height: 300)))),
    );
    final words = SpanishWords.build(['fue', 'a', 'pedir', 'el', 'auxilio']);
    await tester.pumpWidget(
      MaterialApp(
        home: ScanReviewScreen(
          paths: [path],
          recognize: (_) async => const <ScannedLine>[
            (text: 'fue a pecir el auxilio', left: 0.1, top: 0.2, width: 0.5, height: 0.05),
          ],
          loadWords: () async => words,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Transcribir'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'fue a pedir el auxilio');
    expect(find.textContaining('Hay 1 renglón dudoso'), findsOneWidget);
  });

  testWidgets('al escanear transcribe todas las páginas sin tener que mirarlas', (tester) async {
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('revisar'));
    addTearDown(() => tester.runAsync(() => dir!.delete(recursive: true)));
    final paths = ['${dir!.path}/a.jpg', '${dir.path}/b.jpg', '${dir.path}/c.jpg'];
    for (final p in paths) {
      await tester.runAsync(
        () => File(p).writeAsBytes(Uint8List.fromList(img.encodeJpg(img.Image(width: 200, height: 300)))),
      );
    }
    final read = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ScanReviewScreen(
          paths: paths,
          transcribe: true,
          recognize: (path) async {
            read.add(path);
            return const <ScannedLine>[(text: 'hola', left: 0.1, top: 0.2, width: 0.5, height: 0.05)];
          },
        ),
      ),
    );
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(read, paths);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Transcribir')).selected, isTrue);
  });

  testWidgets('«Transcribir» deja corregir lo leído y lo entrega con sus páginas', (tester) async {
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('revisar'));
    addTearDown(() => tester.runAsync(() => dir!.delete(recursive: true)));
    final path = '${dir!.path}/hoja.jpg';
    await tester.runAsync(
      () => File(path).writeAsBytes(Uint8List.fromList(img.encodeJpg(img.Image(width: 200, height: 300)))),
    );

    // Leer el archivo y limpiar la foto son trabajos reales, por tandas.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    ScanReview? review;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              review = await Navigator.of(context).push<ScanReview>(
                MaterialPageRoute(
                  builder: (_) => ScanReviewScreen(
                    paths: [path],
                    recognize: (_) async => const <ScannedLine>[
                      (text: 'segundo', left: 0.1, top: 0.5, width: 0.5, height: 0.05),
                      (text: 'C.l. 123', left: 0.1, top: 0.2, width: 0.5, height: 0.05),
                    ],
                  ),
                ),
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Transcribir'));
    await tester.pump();
    await settle();
    expect(find.textContaining('La calidad depende de la foto'), findsOneWidget);
    expect(find.textContaining('Leído sin IA'), findsOneWidget);
    // De arriba abajo, aunque el lector los entregue en otro orden.
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    expect(tester.widget<TextField>(fields.first).controller!.text, 'C.l. 123');

    await tester.enterText(fields.first, 'C.I. 123');
    await tester.tap(find.byIcon(CupertinoIcons.checkmark));
    await settle();

    expect(review, isNotNull);
    expect(review!.pages, hasLength(1));
    expect(review!.retyped!.single.map((l) => l.text), ['C.I. 123', 'segundo']);
    expect(review!.retyped!.single.first.top, 0.2, reason: 'el lugar no cambia al corregir');
  });

  /// Una tabla de líneas grises finas, como la de un formulario impreso.
  Uint8List grayTable() {
    final page = img.Image(width: 1000, height: 1400);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));
    final gray = img.ColorRgb8(150, 150, 150);
    for (var y = 300; y <= 900; y += 150) {
      img.fillRect(page, x1: 100, y1: y, x2: 900, y2: y + 1, color: gray);
    }
    for (var x = 100; x <= 900; x += 200) {
      img.fillRect(page, x1: x, y1: 300, x2: x + 1, y2: 900, color: gray);
    }
    return Uint8List.fromList(img.encodeJpg(page, quality: 95));
  }

  test('borrar solo la tabla de una hoja llena de texto también cuenta como pérdida', () async {
    final page = img.Image(width: 1000, height: 1400);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));
    final text = img.ColorRgb8(0, 0, 0);
    for (var y = 200; y < 1200; y += 24) {
      for (var x = 120; x < 880; x += 14) {
        img.fillRect(page, x1: x, y1: y, x2: x + 8, y2: y + 12, color: text);
      }
    }
    final noTable = Uint8List.fromList(img.encodeJpg(page, quality: 95));
    final gray = img.ColorRgb8(150, 150, 150);
    img.fillRect(page, x1: 100, y1: 180, x2: 900, y2: 181, color: gray);
    img.fillRect(page, x1: 100, y1: 1210, x2: 900, y2: 1211, color: gray);
    img.fillRect(page, x1: 100, y1: 180, x2: 101, y2: 1210, color: gray);
    img.fillRect(page, x1: 899, y1: 180, x2: 900, y2: 1210, color: gray);
    final withTable = Uint8List.fromList(img.encodeJpg(page, quality: 95));
    expect(await contentKept(withTable, noTable), lessThan(minContentKept));
    expect(await contentKept(withTable, withTable), 1.0);
  });

  test('se mide cuánto de la hoja conserva un filtro', () async {
    final table = grayTable();
    expect(await contentKept(table, table), 1.0);
    expect(await contentKept(table, (await applyScanFilter(table, ScanFilter.grises)).jpeg), greaterThan(0.9));
    final blank = Uint8List.fromList(img.encodeJpg(img.Image(width: 1000, height: 1400)..clear(img.ColorRgb8(255, 255, 255))));
    expect(await contentKept(table, blank), lessThan(0.1));
  });

  testWidgets('un filtro que borraría parte de la hoja queda apagado y dice por qué', (tester) async {
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('revisar'));
    addTearDown(() => tester.runAsync(() => dir!.delete(recursive: true)));
    final path = '${dir!.path}/tabla.jpg';
    await tester.runAsync(() => File(path).writeAsBytes(grayTable()));
    final kept = await tester.runAsync(() async {
      final photo = await File(path).readAsBytes();
      return {
        for (final f in ScanFilter.values) f: await contentKept(photo, (await applyScanFilter(photo, f)).jpeg),
      };
    });
    final losing = [for (final f in ScanFilter.values) if (kept![f]! < 0.9) f];
    expect(losing, isNotEmpty, reason: 'la tabla gris tiene que hacer fallar a algún filtro: $kept');

    await tester.pumpWidget(
      MaterialApp(home: ScanReviewScreen(paths: [path], recognize: (_) async => const <ScannedLine>[])),
    );
    for (var i = 0; i < 40 && find.text('Borra datos').evaluate().length < losing.length; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Borra datos'), findsNWidgets(losing.length));
    expect(find.text('Original'), findsOneWidget, reason: 'el original nunca se apaga');
  });

  group('herramientas de página', () {
    late Directory dir;
    late List<String> paths;

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<ScanReview?> Function() open(WidgetTester tester) {
      ScanReview? result;
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      return () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<ScanReview>(
                    MaterialPageRoute(
                      builder: (_) => ScanReviewScreen(paths: paths, recognize: (_) async => const <ScannedLine>[]),
                    ),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('abrir'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await settle(tester);
        return result;
      };
    }

    Future<void> prepare(WidgetTester tester, int count) async {
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('paginas');
        paths = [];
        for (var i = 0; i < count; i++) {
          final path = '${dir.path}/p$i.jpg';
          await File(path).writeAsBytes(img.encodeJpg(img.Image(width: 200, height: 300)));
          paths.add(path);
        }
      });
      addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));
    }

    testWidgets('quitar una página, y deshacerlo', (tester) async {
      await prepare(tester, 2);
      await open(tester)();
      expect(find.text('Página 1 de 2'), findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.trash));
      await tester.pump();
      await settle(tester);
      expect(find.text('Página 1 de 2'), findsNothing);
      await tester.tap(find.text('Deshacer'));
      await tester.pump();
      await settle(tester);
      expect(find.textContaining('de 2'), findsOneWidget);
    });

    testWidgets('el aviso con botón se quita solo y no tapa la pantalla', (tester) async {
      await prepare(tester, 2);
      await open(tester)();
      await tester.tap(find.byIcon(CupertinoIcons.trash));
      await tester.pump();
      await settle(tester);
      expect(find.text('Página quitada.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Página quitada.'), findsNothing);
    });

    testWidgets('con una sola página no se puede quitar', (tester) async {
      await prepare(tester, 1);
      await open(tester)();
      final trash = tester.widget<IconButton>(find.widgetWithIcon(IconButton, CupertinoIcons.trash));
      expect(trash.onPressed, isNull);
    });

    testWidgets('girar da vuelta la foto de esa página', (tester) async {
      await prepare(tester, 1);
      await open(tester)();
      await tester.tap(find.byIcon(CupertinoIcons.rotate_right));
      await tester.pump();
      await settle(tester);
      final rotated = await tester.runAsync(() async => img.decodeJpg(await File(paths.single).readAsBytes()));
      expect((rotated!.width, rotated.height), (300, 200));
    });

    testWidgets('arrastrar una miniatura cambia el orden', (tester) async {
      await prepare(tester, 3);
      await open(tester)();
      final thumb = find.byKey(ValueKey('mini-${paths[0]}'));
      final second = find.byKey(ValueKey('mini-${paths[1]}'));
      expect(tester.getTopLeft(thumb).dx, lessThan(tester.getTopLeft(second).dx));
      final gesture = await tester.startGesture(tester.getCenter(thumb));
      await tester.pump(const Duration(seconds: 1));
      await gesture.moveBy(const Offset(120, 0));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveBy(const Offset(120, 0));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(tester.getTopLeft(thumb).dx, greaterThan(tester.getTopLeft(second).dx));
    });
  });
}
