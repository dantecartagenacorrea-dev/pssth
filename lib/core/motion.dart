import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Color del fondo de toda la app (las letras van del color contrario).
enum Paper {
  black('Negro', 'Letras blancas sobre fondo negro.'),
  white('Blanco', 'Letras negras sobre fondo blanco.');

  const Paper(this.label, this.detail);
  final String label;
  final String detail;
}

/// Espacio entre renglones del texto que se lee.
enum LineSpacing {
  compacto('Compacto', 1.3),
  normal('Normal', 1.45),
  amplio('Amplio', 1.75);

  const LineSpacing(this.label, this.height);
  final String label;
  final double height;
}

/// Letra del texto que se lee.
enum ReadingFont {
  normal('Normal'),
  legible('Muy legible'),
  book('De libro');

  const ReadingFont(this.label);
  final String label;
}

/// Ajustes de comodidad visual, guardados en el equipo.
class Comfort {
  Comfort._();
  static const _paperKey = 'paper';
  static const _fontKey = 'reading_font';

  /// Ajuste anterior (sí o no a la letra muy legible): solo para leerlo.
  static const _legibleKey = 'legible_font';
  static const _textSizeKey = 'reading_size';
  static const _lineHeightKey = 'reading_line_height';
  static const _keepControlsKey = 'keep_controls';
  static const _skipCitationsKey = 'skip_citations';
  static const _skipLinksKey = 'skip_links';
  static const _readingPaperKey = 'reading_paper';
  static const _readingModeKey = 'reading_mode';

  /// Ajuste anterior (Completo, Suave o Quieto): solo para leerlo una vez.

  static final paper = ValueNotifier(Paper.black);

  /// Letra del texto que se lee: la de la interfaz, una pensada para leer
  /// mejor (Atkinson Hyperlegible) o una de libro.
  static final font = ValueNotifier(ReadingFont.normal);

  static const legibleFamily = 'AtkinsonHyperlegible';

  /// Con serifa, como un libro impreso. Viene en el sistema (Noto Serif en
  /// Android, Georgia en iPhone): no suma peso a la app.
  static String get bookFamily => defaultTargetPlatform == TargetPlatform.iOS ? 'Georgia' : 'serif';

  /// Familia del texto que se lee; null es la de la interfaz.
  static String? get readingFont => switch (font.value) {
    ReadingFont.normal => null,
    ReadingFont.legible => legibleFamily,
    ReadingFont.book => bookFamily,
  };

  /// Tamaño de la letra del texto que se lee (antes fijo en 19).
  static final textSize = ValueNotifier(defaultTextSize);
  static const defaultTextSize = 19.0, minTextSize = 15.0, maxTextSize = 30.0;

  /// Espacio entre renglones del texto que se lee.
  static final lineHeight = ValueNotifier(LineSpacing.normal);

  /// Los controles de la lectura no se esconden solos a los 3 segundos.
  static final keepControls = ValueNotifier(false);

  /// No leer en voz alta las citas y notas: [12], (Pérez, 2019).
  static final skipCitations = ValueNotifier(false);

  /// No leer en voz alta direcciones web ni correos (sí por omisión: letra por
  /// letra no le sirven a nadie).
  static final skipLinks = ValueNotifier(true);

  /// Fondo elegido en la lectura a pantalla completa (blanco, sepia o negro),
  /// por nombre; null si nunca se eligió.
  static final readingPaper = ValueNotifier<String?>(null);

  /// Modo elegido en la lectura a pantalla completa de un PDF (original o
  /// texto), por nombre; null si nunca se eligió.
  static final readingMode = ValueNotifier<String?>(null);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    paper.value = Paper.values.asNameMap()[p.getString(_paperKey)] ?? Paper.black;
    // Quien tenía la letra muy legible la conserva.
    font.value =
        ReadingFont.values.asNameMap()[p.getString(_fontKey)] ??
        ((p.getBool(_legibleKey) ?? false) ? ReadingFont.legible : ReadingFont.normal);
    textSize.value = (p.getDouble(_textSizeKey) ?? defaultTextSize).clamp(minTextSize, maxTextSize);
    lineHeight.value = LineSpacing.values.asNameMap()[p.getString(_lineHeightKey)] ?? LineSpacing.normal;
    keepControls.value = p.getBool(_keepControlsKey) ?? false;
    skipCitations.value = p.getBool(_skipCitationsKey) ?? false;
    skipLinks.value = p.getBool(_skipLinksKey) ?? true;
    readingPaper.value = p.getString(_readingPaperKey);
    readingMode.value = p.getString(_readingModeKey);
  }

  static Future<void> setReadingMode(String name) async {
    readingMode.value = name;
    await (await SharedPreferences.getInstance()).setString(_readingModeKey, name);
  }

  static Future<void> setReadingPaper(String name) async {
    readingPaper.value = name;
    await (await SharedPreferences.getInstance()).setString(_readingPaperKey, name);
  }

  static Future<void> setTextSize(double size) async {
    textSize.value = size.clamp(minTextSize, maxTextSize);
    await (await SharedPreferences.getInstance()).setDouble(_textSizeKey, textSize.value);
  }

  static Future<void> setLineHeight(LineSpacing value) async {
    lineHeight.value = value;
    await (await SharedPreferences.getInstance()).setString(_lineHeightKey, value.name);
  }

  static Future<void> setKeepControls(bool on) async {
    keepControls.value = on;
    await (await SharedPreferences.getInstance()).setBool(_keepControlsKey, on);
  }

  static Future<void> setSkipCitations(bool on) async {
    skipCitations.value = on;
    await (await SharedPreferences.getInstance()).setBool(_skipCitationsKey, on);
  }

  static Future<void> setSkipLinks(bool on) async {
    skipLinks.value = on;
    await (await SharedPreferences.getInstance()).setBool(_skipLinksKey, on);
  }

  static Future<void> setPaper(Paper value) async {
    paper.value = value;
    await (await SharedPreferences.getInstance()).setString(_paperKey, value.name);
  }

  static Future<void> setFont(ReadingFont value) async {
    font.value = value;
    await (await SharedPreferences.getInstance()).setString(_fontKey, value.name);
  }
}
