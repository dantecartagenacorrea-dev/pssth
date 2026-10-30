import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/ui/first_run_guide.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(bool isNewUser) => MaterialApp(
  home: Builder(
    builder: (context) => TextButton(
      onPressed: () => FirstRunGuide.showOnce(context, isNewUser: isNewUser),
      child: const Text('abrir'),
    ),
  ),
);

void main() {
  testWidgets('a quien empieza le muestra los 3 pasos, una sola vez', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(true));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Abre lo que quieras escuchar'), findsOneWidget);
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Escucha y sigue la lectura'), findsOneWidget);
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();
    expect(find.text('Estudia sin salir del texto'), findsNothing);
    // La segunda vez ya no aparece.
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Abre lo que quieras escuchar'), findsNothing);
  });

  testWidgets('a quien ya tiene documentos no se la muestra', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(false));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Abre lo que quieras escuchar'), findsNothing);
  });
}
