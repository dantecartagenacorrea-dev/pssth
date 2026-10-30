import 'package:flutter/widgets.dart';
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

/// Ajustes de comodidad visual, guardados en el equipo.
class Comfort {
  Comfort._();
  static const _paperKey = 'paper';
  static const _scatterKey = 'scatter';
  static const _legibleKey = 'legible_font';
  static const _textSizeKey = 'reading_size';
  static const _lineHeightKey = 'reading_line_height';
  static const _keepControlsKey = 'keep_controls';
  static const _skipCitationsKey = 'skip_citations';

  /// Ajuste anterior (Completo, Suave o Quieto): solo para leerlo una vez.
  static const _oldMotionKey = 'motion';

  static final paper = ValueNotifier(Paper.black);

  /// Dispersión de letras: las pantallas se forman desde un enjambre de
  /// letras y el fondo se mueve. Apagada, la pantalla es lisa y todo aparece
  /// de una vez (también si el sistema pide reducir el movimiento).
  static final scatter = ValueNotifier(true);

  /// Letra pensada para leer mejor (Atkinson Hyperlegible).
  static final legible = ValueNotifier(false);

  static const legibleFamily = 'AtkinsonHyperlegible';

  /// Letra del texto que se lee: la muy legible si se eligió; si no, la de
  /// la interfaz.
  static String? get readingFont => legible.value ? legibleFamily : null;

  /// Tamaño de la letra del texto que se lee (antes fijo en 19).
  static final textSize = ValueNotifier(defaultTextSize);
  static const defaultTextSize = 19.0, minTextSize = 15.0, maxTextSize = 30.0;

  /// Espacio entre renglones del texto que se lee.
  static final lineHeight = ValueNotifier(LineSpacing.normal);

  /// Los controles de la lectura no se esconden solos a los 3 segundos.
  static final keepControls = ValueNotifier(false);

  /// No leer en voz alta las citas y notas: [12], (Pérez, 2019).
  static final skipCitations = ValueNotifier(false);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    paper.value = Paper.values.asNameMap()[p.getString(_paperKey)] ?? Paper.black;
    // Quien tenía "Completo" sigue con la dispersión; "Suave" o "Quieto", sin.
    final old = p.getString(_oldMotionKey);
    scatter.value = p.getBool(_scatterKey) ?? (old == null || old == 'completo');
    legible.value = p.getBool(_legibleKey) ?? false;
    textSize.value = (p.getDouble(_textSizeKey) ?? defaultTextSize).clamp(minTextSize, maxTextSize);
    lineHeight.value = LineSpacing.values.asNameMap()[p.getString(_lineHeightKey)] ?? LineSpacing.normal;
    keepControls.value = p.getBool(_keepControlsKey) ?? false;
    skipCitations.value = p.getBool(_skipCitationsKey) ?? false;
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

  static Future<void> setPaper(Paper value) async {
    paper.value = value;
    await (await SharedPreferences.getInstance()).setString(_paperKey, value.name);
  }

  static Future<void> setScatter(bool on) async {
    scatter.value = on;
    await (await SharedPreferences.getInstance()).setBool(_scatterKey, on);
  }

  static Future<void> setLegible(bool on) async {
    legible.value = on;
    await (await SharedPreferences.getInstance()).setBool(_legibleKey, on);
  }
}

/// ¿Quieto el fondo (puntos, letras que flotan al leer)? Sin dispersión la
/// app avisa que no hay animaciones, igual que cuando lo pide el sistema.
bool calmOf(BuildContext context) => MediaQuery.disableAnimationsOf(context);
