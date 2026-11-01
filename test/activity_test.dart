import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/core/activity.dart';
import 'package:lector_pdf/ui/activity_badge.dart';

void main() {
  test('el trabajo se anota mientras dura, aunque falle', () async {
    final gate = Completer<void>();
    final work = Activity.run('Sincronizando', () => gate.future);
    expect(Activity.current.value, ['Sincronizando']);
    gate.complete();
    await work;
    expect(Activity.current.value, isEmpty);

    await expectLater(Activity.run('Corrigiendo con IA', () async => throw StateError('x')), throwsStateError);
    expect(Activity.current.value, isEmpty);
  });

  testWidgets('el indicador muestra lo que hace la app y se va al terminar', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Stack(children: [ActivityBadge()])));
    final gate = Completer<void>();
    final work = Activity.run('Sincronizando', () => gate.future);
    final other = Activity.run('Bajando voces', () => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pump();
    expect(find.text('Sincronizando… +1'), findsOneWidget);
    // A los 3 segundos queda solo el punto (no tapa los botones de arriba).
    await tester.pump(const Duration(milliseconds: 3100));
    expect(find.textContaining('Sincronizando'), findsNothing);
    expect(Activity.current.value, isNotEmpty);
    gate.complete();
    await tester.pump(const Duration(seconds: 1));
    await work;
    await other;
    await tester.pump(const Duration(milliseconds: 300));
    expect(Activity.current.value, isEmpty);
    final fade = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(fade.opacity, 0);
  });
}
