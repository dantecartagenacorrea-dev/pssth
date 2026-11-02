import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lector_pdf/domain/scanned_pdf.dart';
import 'package:lector_pdf/ui/scan_review_screen.dart';

void main() {
  testWidgets('«Como nuevo» deja corregir lo leído y lo entrega con sus páginas', (tester) async {
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

    await tester.tap(find.text('Como nuevo'));
    await tester.pump();
    await settle();
    expect(find.textContaining('La calidad depende de la foto'), findsOneWidget);
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
