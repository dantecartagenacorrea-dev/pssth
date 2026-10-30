import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/core/motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('el fondo, la dispersión y la letra se recuerdan', () async {
    await Comfort.setPaper(Paper.white);
    await Comfort.setScatter(false);
    await Comfort.setLegible(true);
    Comfort.paper.value = Paper.black;
    Comfort.scatter.value = true;
    Comfort.legible.value = false;
    await Comfort.load();
    expect(Comfort.paper.value, Paper.white);
    expect(Comfort.scatter.value, isFalse);
    expect(Comfort.legible.value, isTrue);
  });

  test('sin nada guardado: fondo negro con dispersión', () async {
    await Comfort.load();
    expect(Comfort.paper.value, Paper.black);
    expect(Comfort.scatter.value, isTrue);
  });

  test('el ajuste de movimiento anterior se respeta', () async {
    for (final (old, scatter) in [('completo', true), ('suave', false), ('quieto', false)]) {
      SharedPreferences.setMockInitialValues({'motion': old});
      await Comfort.load();
      expect(Comfort.scatter.value, scatter, reason: old);
    }
  });

  testWidgets('el fondo queda quieto si se pide quitar las animaciones', (tester) async {
    late bool calm;
    Widget probe({required bool still}) => MediaQuery(
      data: MediaQueryData(disableAnimations: still),
      child: Builder(
        builder: (c) {
          calm = calmOf(c);
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(probe(still: false));
    expect(calm, isFalse);
    await tester.pumpWidget(probe(still: true));
    expect(calm, isTrue);
  });

  test('los ajustes de lectura se recuerdan y el tamaño queda en su rango', () async {
    await Comfort.setTextSize(24);
    await Comfort.setLineHeight(LineSpacing.amplio);
    await Comfort.setKeepControls(true);
    await Comfort.setSkipCitations(true);
    Comfort.textSize.value = Comfort.defaultTextSize;
    Comfort.lineHeight.value = LineSpacing.normal;
    Comfort.keepControls.value = false;
    Comfort.skipCitations.value = false;
    await Comfort.load();
    expect(Comfort.textSize.value, 24);
    expect(Comfort.lineHeight.value, LineSpacing.amplio);
    expect(Comfort.keepControls.value, isTrue);
    expect(Comfort.skipCitations.value, isTrue);
    await Comfort.setTextSize(99);
    expect(Comfort.textSize.value, Comfort.maxTextSize);
    Comfort.skipCitations.value = false;
  });
}
