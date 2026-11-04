import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/playback/tts_audio_handler.dart';
import 'package:lector_pdf/ui/formula_graph_view.dart';

class _FakeHandler implements TtsAudioHandler {
  final said = <String>[];

  @override
  Future<String?> speakAside(List<String> sentences, {bool sameVoice = false}) async {
    said.addAll(sentences);
    return null;
  }

  @override
  Future<void> stopAside() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeHandler handler;

  Future<void> open(WidgetTester tester, {Size size = const Size(400, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    handler = _FakeHandler();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FormulaGraphView(handler: handler)),
      ),
    );
  }

  testWidgets('un ejemplo llena la fórmula y se puede escuchar', (tester) async {
    await open(tester);
    await tester.tap(find.text('y = 2x + 1'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '2x + 1');

    await tester.tap(find.text('Escuchar'));
    await tester.pump();
    expect(handler.said.single, contains('Corta el eje y en 1'));
  });

  testWidgets('avisa lo que no entiende sin dejar de graficar las demás', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'z + 1');
    await tester.pump();
    expect(find.textContaining('No entiendo'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'x');
    await tester.pump();
    expect(find.textContaining('No entiendo'), findsNothing);
    await tester.tap(find.text('Otra fórmula'));
    await tester.pump();
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('las teclas escriben en la fórmula elegida', (tester) async {
    await open(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'x').first);
    await tester.pump();
    await tester.ensureVisible(find.text('sen'));
    await tester.pump();
    await tester.tap(find.text('sen'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'xsen(');
    expect(find.text('Escuchar'), findsOneWidget);
  });

  testWidgets('el plano se mueve, se acerca y vuelve sin errores', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'tan(x)');
    await tester.pump();
    await tester.drag(find.byType(CustomPaint).first, const Offset(60, 30));
    await tester.pump();
    await tester.tap(find.byIcon(CupertinoIcons.plus).first);
    await tester.pump();
    await tester.tap(find.byIcon(CupertinoIcons.arrow_up_down));
    await tester.pump();
    await tester.tap(find.byIcon(CupertinoIcons.scope));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('acostado, el plano y las fórmulas van lado a lado', (tester) async {
    await open(tester, size: const Size(800, 360));
    await tester.tap(find.widgetWithText(ActionChip, 'y = x²'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('una fórmula que llega de otra parte se grafica', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final request = ValueNotifier<String?>(null);
    addTearDown(request.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormulaGraphView(handler: _FakeHandler(), request: request),
        ),
      ),
    );
    request.value = 'y = 2x + 1';
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'y = 2x + 1');
    expect(request.value, isNull);
    expect(tester.takeException(), isNull);
  });
}
