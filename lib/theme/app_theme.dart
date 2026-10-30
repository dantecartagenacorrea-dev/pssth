import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colores del aspecto «premium»: encabezado negro con el dato grande y, debajo,
/// una hoja redondeada (blanca, o casi negra con el fondo negro) donde va el
/// contenido.
class Premium {
  Premium._();

  /// Encabezado de todas las pantallas (siempre negro).
  static const hero = Color(0xFF0B0B0B);
  static const heroText = Color(0xFFFFFFFF);
  static const heroMuted = Color(0xFF9A9A9A);

  /// Píldoras sobre el negro: borde y relleno blancos muy tenues.
  static const pillBorder = Color(0x2EFFFFFF);
  static const pillFill = Color(0x0FFFFFFF);

  /// Barra de navegación flotante y avisos.
  static const float = Color(0xFF151515);

  /// Verde para lo nuevo o completado (como el «+$50» de las imágenes).
  static const positive = Color(0xFF1F9D55);

  static const radiusSheet = 28.0;
  static const radiusCard = 18.0;
}

/// Colores de la hoja según el fondo elegido en Aspecto (blanco o negro).
class SheetColors {
  const SheetColors({
    required this.sheet,
    required this.text,
    required this.muted,
    required this.card,
    required this.line,
    required this.accent,
  });

  final Color sheet, text, muted, card, line;

  /// La palabra que suena y los detalles destacados (ámbar).
  final Color accent;

  /// Fondo blanco, como las pantallas de Apple (voicenotes).
  static const light = SheetColors(
    sheet: Color(0xFFFFFFFF),
    text: Color(0xFF000000),
    // Gris con contraste 5:1 sobre blanco (el de Apple, 8E8E93, no se leía).
    muted: Color(0xFF6C6C70),
    card: Color(0xFFF2F2F7),
    line: Color(0xFFE5E5EA),
    accent: Color(0xFFBA7517),
  );

  /// Fondo negro, como el modo oscuro de Apple (Statistic).
  static const dark = SheetColors(
    sheet: Color(0xFF000000),
    text: Color(0xFFFFFFFF),
    muted: Color(0xFF8E8E93),
    card: Color(0xFF1C1C1E),
    line: Color(0xFF2C2C2E),
    accent: Color(0xFFFAC775),
  );
}

class AppTheme {
  AppTheme._();

  /// Letra de la interfaz: en el iPhone la del sistema (SF, la de Apple); en
  /// Android, Inter, la más parecida que se puede incluir (SF solo se permite
  /// en equipos de Apple).
  static final String? font = Platform.isIOS ? null : 'Inter';

  /// Tema de toda la app: el contenido usa los colores de la hoja ([light]:
  /// blanca); el encabezado negro usa [hero].
  static ThemeData premium({bool light = true}) => _build(light ? SheetColors.light : SheetColors.dark, light);

  /// Tema de la tarjeta destacada (el dato grande): negra sobre el fondo
  /// blanco y gris oscuro sobre el negro, siempre con texto blanco.
  static ThemeData hero({bool onLight = true}) => _build(
    SheetColors(
      sheet: onLight ? Premium.hero : const Color(0xFF1C1C1E),
      text: Premium.heroText,
      muted: Premium.heroMuted,
      card: const Color(0xFF2C2C2E),
      line: Premium.pillBorder,
      accent: const Color(0xFFFAC775),
    ),
    false,
  );

  static ThemeData _build(SheetColors c, bool light) {
    final scheme = ColorScheme(
      brightness: light ? Brightness.light : Brightness.dark,
      primary: c.text,
      onPrimary: c.sheet,
      secondary: c.muted,
      onSecondary: c.sheet,
      tertiary: c.accent,
      onTertiary: c.sheet,
      error: const Color(0xFFE5484D),
      onError: Colors.white,
      surface: c.sheet,
      onSurface: c.text,
      onSurfaceVariant: c.muted,
      surfaceContainerLowest: c.sheet,
      surfaceContainerLow: c.card,
      surfaceContainer: c.card,
      surfaceContainerHigh: c.card,
      surfaceContainerHighest: c.card,
      primaryContainer: c.card,
      onPrimaryContainer: c.text,
      secondaryContainer: c.card,
      onSecondaryContainer: c.text,
      outline: c.line,
      outlineVariant: c.line,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: font);
    final tt = base.textTheme.apply(bodyColor: c.text, displayColor: c.text);
    const pill = StadiumBorder();
    const pillSize = Size(0, 46);
    const pillPad = EdgeInsets.symmetric(horizontal: 18);
    final label = TextStyle(fontFamily: font, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.4);
    return base.copyWith(
      scaffoldBackgroundColor: c.sheet,
      canvasColor: c.sheet,
      splashFactory: NoSplash.splashFactory,
      // Escala de letras de Apple (Human Interface Guidelines): Título grande
      // 34, Títulos 28/22/20, Encabezado 17, Cuerpo 17, Subtítulo 15, Nota al
      // pie 13 y Leyendas 12/11.
      textTheme: tt.copyWith(
        // El dato grande del encabezado (como el saldo de las imágenes).
        displaySmall: tt.displaySmall?.copyWith(fontSize: 44, fontWeight: FontWeight.w600, letterSpacing: -1.4, height: 1.05),
        headlineLarge: tt.headlineLarge?.copyWith(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.9, height: 1.15),
        headlineMedium: tt.headlineMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.7, height: 1.2),
        headlineSmall: tt.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.25),
        titleLarge: tt.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.4, height: 1.3),
        titleMedium: tt.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.4),
        titleSmall: tt.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        bodyLarge: tt.bodyLarge?.copyWith(fontSize: 17, height: 1.45, letterSpacing: -0.4),
        bodyMedium: tt.bodyMedium?.copyWith(fontSize: 15, height: 1.4, letterSpacing: -0.2, color: c.text),
        bodySmall: tt.bodySmall?.copyWith(fontSize: 13, height: 1.35, letterSpacing: -0.1, color: c.muted),
        labelLarge: label,
        labelMedium: tt.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: c.muted),
        // Rótulos de sección («HOY», «27 OCTUBRE»).
        labelSmall: tt.labelSmall?.copyWith(color: c.muted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: c.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: font, color: c.text, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      iconTheme: IconThemeData(color: c.text, size: 22),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: c.text, minimumSize: const Size(44, 44))),
      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Premium.radiusCard)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.text,
        textColor: c.text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        titleTextStyle: TextStyle(fontFamily: font, fontSize: 15, fontWeight: FontWeight.w500, color: c.text, letterSpacing: -0.2),
        subtitleTextStyle: TextStyle(fontFamily: font, fontSize: 13, color: c.muted),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 0.6, space: 0.6),
      // Botón principal: píldora llena (negra sobre blanco, blanca sobre negro).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.text,
          foregroundColor: c.sheet,
          minimumSize: pillSize,
          padding: pillPad,
          shape: pill,
          textStyle: label,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          side: BorderSide(color: c.line),
          minimumSize: pillSize,
          padding: pillPad,
          shape: pill,
          textStyle: label,
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.text, textStyle: label, shape: pill)),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          foregroundColor: c.text,
          selectedForegroundColor: c.sheet,
          selectedBackgroundColor: c.text,
          side: BorderSide(color: c.line),
          shape: pill,
          textStyle: label,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: StadiumBorder(side: BorderSide(color: c.line)),
        side: BorderSide(color: c.line),
        backgroundColor: c.sheet,
        selectedColor: c.text,
        labelStyle: TextStyle(fontFamily: font, fontSize: 13, fontWeight: FontWeight.w500, color: c.text),
        secondaryLabelStyle: TextStyle(fontFamily: font, fontSize: 13, fontWeight: FontWeight.w500, color: c.sheet),
        checkmarkColor: c.sheet,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.card,
        hintStyle: TextStyle(color: c.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.text)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.sheet,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: c.line)),
        textStyle: TextStyle(fontFamily: font, fontSize: 15, color: c.text),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.sheet,
        modalBackgroundColor: c.sheet,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: c.line,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Premium.radiusSheet))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.sheet,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Premium.radiusSheet)),
        titleTextStyle: TextStyle(fontFamily: font, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: c.text),
        contentTextStyle: TextStyle(fontFamily: font, fontSize: 15, height: 1.45, color: c.text),
      ),
      // Avisos: píldora negra flotante, como la barra de navegación.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Premium.float,
        contentTextStyle: TextStyle(fontFamily: font, fontSize: 15, color: Colors.white),
        actionTextColor: const Color(0xFFFAC775),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: Premium.float, borderRadius: BorderRadius.circular(12)),
        textStyle: TextStyle(fontFamily: font, fontSize: 12, color: Colors.white),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.sheet : c.muted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.text : c.card),
        trackOutlineColor: WidgetStateProperty.all(c.line),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.text : Colors.transparent),
        checkColor: WidgetStateProperty.all(c.sheet),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStateProperty.all(c.text)),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.text, linearTrackColor: c.line, circularTrackColor: c.line),
      sliderTheme: SliderThemeData(activeTrackColor: c.text, inactiveTrackColor: c.line, thumbColor: c.text, trackHeight: 4),
    );
  }

  /// Misma app (mismos colores) con otra letra: la muy legible.
  static ThemeData withFont(ThemeData t, String family) => t.copyWith(
    textTheme: t.textTheme.apply(fontFamily: family),
    primaryTextTheme: t.primaryTextTheme.apply(fontFamily: family),
  );
}
