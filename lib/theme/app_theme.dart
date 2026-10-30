import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tema estilo iOS: neutro, tipografía del sistema, radios continuos.
class AppTheme {
  static const blue = Color(0xFF007AFF);
  static const blueDark = Color(0xFF0A84FF);
  static const gray = Color(0xFF8E8E93);

  /// Gris de los textos secundarios sobre fondo blanco (contraste 5:1).
  static const grayOnLight = Color(0xFF6C6C70);

  static ThemeData light() => _base(
    brightness: Brightness.light,
    bg: const Color(0xFFFFFFFF),
    surface: const Color(0xFFF2F2F7),
    surface2: const Color(0xFFFFFFFF),
    text: const Color(0xFF1C1C1E),
    accent: blue,
    // Sobre blanco el gris claro no se lee bien (3,3:1): uno más oscuro.
    muted: grayOnLight,
  );

  static ThemeData dark() => _base(
    brightness: Brightness.dark,
    bg: const Color(0xFF000000),
    surface: const Color(0xFF1C1C1E),
    surface2: const Color(0xFF2C2C2E),
    text: const Color(0xFFF2F2F7),
    accent: blueDark,
  );

  /// Toda la app sobre el éter: fondo de puntos y botones, tarjetas e íconos
  /// transparentes, sin contorno. En negro con el texto en blanco o, con
  /// [light], en blanco con el texto en negro.
  static ThemeData ether({bool light = false}) {
    final d = light ? AppTheme.light() : dark();
    final ink = light ? Colors.black : Colors.white;
    final paper = light ? Colors.white : Colors.black;
    // Sin contornos: botones y tarjetas son solo su texto e ícono.
    const line = BorderSide.none;
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return d.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: d.colorScheme.copyWith(primary: ink, onPrimary: paper),
      appBarTheme: d.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        // Hora y batería del sistema del color de las letras.
        systemOverlayStyle: light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
        shape: const Border(),
      ),
      cardTheme: d.cardTheme.copyWith(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: line),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: ink,
          side: line,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: buttonShape,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(foregroundColor: ink, side: line, shape: buttonShape),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: ink)),
      iconTheme: IconThemeData(color: ink),
      // Todo del color del fondo, sin separadores ni superficies grises.
      canvasColor: paper,
      dividerTheme: const DividerThemeData(color: Colors.transparent, thickness: 0, space: 0),
      bottomSheetTheme: d.bottomSheetTheme.copyWith(backgroundColor: paper, modalBackgroundColor: paper),
      // Diálogos y avisos flotantes y bien definidos: borde fino y esquinas
      // redondeadas, como los paneles.
      dialogTheme: d.dialogTheme.copyWith(
        backgroundColor: paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: ink.withValues(alpha: 0.22)),
        ),
      ),
      popupMenuTheme: d.popupMenuTheme.copyWith(color: paper),
      snackBarTheme: d.snackBarTheme.copyWith(
        backgroundColor: paper,
        contentTextStyle: TextStyle(color: ink),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: ink.withValues(alpha: 0.22)),
        ),
      ),
    );
  }

  static ThemeData _base({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color surface2,
    required Color text,
    required Color accent,
    Color muted = gray,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: Colors.white,
      secondary: muted,
      onSecondary: Colors.white,
      error: const Color(0xFFFF3B30),
      onError: Colors.white,
      surface: bg,
      onSurface: text,
      surfaceContainerHighest: surface,
      surfaceContainerHigh: surface2,
      primaryContainer: accent.withValues(alpha: 0.16),
      onPrimaryContainer: text,
      outlineVariant: muted.withValues(alpha: 0.35),
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final tt = base.textTheme.apply(bodyColor: text, displayColor: text);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      splashFactory: NoSplash.splashFactory,
      textTheme: tt.copyWith(
        headlineSmall: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6),
        titleLarge: tt.titleLarge?.copyWith(
          fontSize: 19,
          height: 1.6,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.1,
        ),
        bodyLarge: tt.bodyLarge?.copyWith(fontSize: 17, height: 1.5),
        labelSmall: tt.labelSmall?.copyWith(color: muted, fontWeight: FontWeight.w600, letterSpacing: 0.6),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg.withValues(alpha: 0.86),
        foregroundColor: accent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(color: text, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3),
        shape: Border(bottom: BorderSide(color: muted.withValues(alpha: 0.25), width: 0.5)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      dividerTheme: DividerThemeData(color: muted.withValues(alpha: 0.25), thickness: 0.5, space: 0.5),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: text, minimumSize: const Size(44, 44)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: surface2,
          foregroundColor: text,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface2,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: text, linearTrackColor: muted.withValues(alpha: 0.3)),
      sliderTheme: SliderThemeData(
        activeTrackColor: text,
        inactiveTrackColor: muted.withValues(alpha: 0.3),
        thumbColor: text,
        trackHeight: 4,
      ),
    );
  }

  /// Misma app (mismos colores) con otra letra: la muy legible.
  static ThemeData withFont(ThemeData t, String family) => t.copyWith(
    textTheme: t.textTheme.apply(fontFamily: family),
    primaryTextTheme: t.primaryTextTheme.apply(fontFamily: family),
  );
}
