import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/core/motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('el fondo y la letra se recuerdan', () async {
    await Comfort.setPaper(Paper.white);
    await Comfort.setFont(ReadingFont.book);
    Comfort.paper.value = Paper.black;
    Comfort.font.value = ReadingFont.normal;
    await Comfort.load();
    expect(Comfort.paper.value, Paper.white);
    expect(Comfort.font.value, ReadingFont.book);
    expect(Comfort.readingFont, Comfort.bookFamily);
  });

  test('quien tenía la letra muy legible la conserva', () async {
    SharedPreferences.setMockInitialValues({'legible_font': true});
    await Comfort.load();
    expect(Comfort.font.value, ReadingFont.legible);
    expect(Comfort.readingFont, Comfort.legibleFamily);
    SharedPreferences.setMockInitialValues({});
    await Comfort.load();
    expect(Comfort.font.value, ReadingFont.normal);
    expect(Comfort.readingFont, isNull);
  });

  test('sin nada guardado: fondo negro', () async {
    await Comfort.load();
    expect(Comfort.paper.value, Paper.black);
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

  test('el fondo de la lectura a pantalla completa se recuerda', () async {
    await Comfort.setReadingPaper('sepia');
    Comfort.readingPaper.value = null;
    await Comfort.load();
    expect(Comfort.readingPaper.value, 'sepia');
  });

  test('el modo de la lectura a pantalla completa se recuerda', () async {
    await Comfort.setReadingMode('text');
    Comfort.readingMode.value = null;
    await Comfort.load();
    expect(Comfort.readingMode.value, 'text');
  });
}
