import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/ui/calculator_view.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CalculatorView())));
  }

  Future<void> press(WidgetTester tester, List<String> keys) async {
    for (final k in keys) {
      await tester.tap(find.text(k).last);
      await tester.pump();
    }
  }

  String shown(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('muestra el resultado mientras se escribe y al dar igual', (tester) async {
    await open(tester);
    await press(tester, ['2', '+', '3', '×', '4']);
    expect(find.text('= 14'), findsOneWidget);
    await press(tester, ['=']);
    expect(shown(tester), '14');
    expect(find.text('2+3×4 = 14'), findsOneWidget);
  });

  testWidgets('después del igual, un número empieza otra cuenta y un operador sigue', (tester) async {
    await open(tester);
    await press(tester, ['2', '+', '2', '=', '×', '3', '=']);
    expect(shown(tester), '12');
    await press(tester, ['5']);
    expect(shown(tester), '5');
  });

  testWidgets('grados por omisión; se cambia a radianes', (tester) async {
    await open(tester);
    await press(tester, ['sen', '9', '0', '=']);
    expect(shown(tester), '1');
    expect(find.text('sen(90) = 1'), findsOneWidget, reason: 'el paréntesis se cierra solo');
    await press(tester, ['Grados']);
    expect(find.text('Radianes'), findsOneWidget);
    await press(tester, ['cos', '0', '=']);
    expect(shown(tester), '1');
  });

  testWidgets('Inv cambia las funciones por sus inversas, una sola vez', (tester) async {
    await open(tester);
    await press(tester, ['Inv', 'arcsen', '1', '=']);
    expect(shown(tester), '90');
    expect(find.text('sen'), findsOneWidget);
  });

  testWidgets('borrar quita una función entera; AC, todo', (tester) async {
    await open(tester);
    await press(tester, ['2', 'sen']);
    expect(shown(tester), '2sen(');
    await tester.tap(find.bySemanticsLabel('Borrar'));
    await tester.pump();
    expect(shown(tester), '2');
    await press(tester, ['AC']);
    expect(shown(tester), '');
  });

  testWidgets('una cuenta sin resultado lo dice y no pisa lo escrito', (tester) async {
    await open(tester);
    await press(tester, ['1', '÷', '0', '=']);
    expect(find.textContaining('infinito'), findsOneWidget);
    expect(shown(tester), '1÷0');
    await press(tester, ['AC', '√', '−', '1', '=']);
    expect(find.text('Esa cuenta no tiene resultado.'), findsOneWidget);
  });

  group('fracciones', () {
    testWidgets('con la tecla de fracción el resultado sale en fracción', (tester) async {
      await open(tester);
      await press(tester, ['1', 'a/b', '2', '+', '1', 'a/b', '3']);
      expect(find.bySemanticsLabel('= 5 sobre 6'), findsOneWidget);
      expect(tester.widget<Math>(find.byType(Math)).parseError, isNull, reason: 'se dibuja bien');
      await press(tester, ['=']);
      expect(shown(tester), '5/6');
      expect(find.text('1/2+1/3 = 5/6'), findsOneWidget);
    });

    testWidgets('con ÷ sale en decimal, y se puede cambiar en los dos sentidos', (tester) async {
      await open(tester);
      await press(tester, ['1', '÷', '3', '=']);
      expect(shown(tester), '0,333333333333');
      await press(tester, ['Ver fracción']);
      expect(shown(tester), '1/3');
      expect(find.text('1÷3 = 1/3'), findsOneWidget);
      await press(tester, ['Ver decimal']);
      expect(shown(tester), '0,333333333333');
    });

    testWidgets('el resultado sigue exacto en la cuenta siguiente', (tester) async {
      await open(tester);
      await press(tester, ['1', 'a/b', '3', '=', '×', '3', '=']);
      expect(shown(tester), '1');
    });

    testWidgets('sigue en fracciones al continuar', (tester) async {
      await open(tester);
      await press(tester, ['1', 'a/b', '2', '=', '+', '1', 'a/b', '3', '=']);
      expect(shown(tester), '5/6');
      await press(tester, ['×', '2', '=']);
      expect(shown(tester), '5/3');
    });

    testWidgets('número mixto', (tester) async {
      await open(tester);
      await press(tester, ['2', 'a b/c', '1', 'a/b', '2', '+', '1', '=']);
      expect(shown(tester), '7/2');
      expect(find.bySemanticsLabel('= 7 sobre 2'), findsOneWidget);
      expect(tester.widget<Math>(find.byType(Math)).parseError, isNull, reason: 'se dibuja bien');
    });

    testWidgets('lo que no es fracción lo dice', (tester) async {
      await open(tester);
      await press(tester, ['√', '2', 'Ver fracción']);
      expect(find.textContaining('no es una fracción exacta'), findsOneWidget);
    });

    testWidgets('sen(30°) también se puede ver como un medio', (tester) async {
      await open(tester);
      await press(tester, ['sen', '3', '0', '=']);
      expect(shown(tester), '0,5');
      await press(tester, ['Ver fracción']);
      expect(shown(tester), '1/2');
    });
  });

  testWidgets('entra en un teléfono acostado sin desbordarse', (tester) async {
    await open(tester);
    tester.view.physicalSize = const Size(800, 330);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
