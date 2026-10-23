import 'package:flutter/material.dart';

/// Tema estilo iOS: neutro, tipografía del sistema, radios continuos.
class AppTheme {
  static const blue = Color(0xFF007AFF);
  static const blueDark = Color(0xFF0A84FF);
  static const gray = Color(0xFF8E8E93);

  static ThemeData light() => _base(
        brightness: Brightness.light,
        bg: const Color(0xFFFFFFFF),
        surface: const Color(0xFFF2F2F7),
        surface2: const Color(0xFFFFFFFF),
        text: const Color(0xFF1C1C1E),
        accent: blue,
      );

  static ThemeData dark() => _base(
        brightness: Brightness.dark,
        bg: const Color(0xFF000000),
        surface: const Color(0xFF1C1C1E),
        surface2: const Color(0xFF2C2C2E),
        text: const Color(0xFFF2F2F7),
        accent: blueDark,
      );

  static ThemeData _base({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color surface2,
    required Color text,
    required Color accent,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: Colors.white,
      secondary: gray,
      onSecondary: Colors.white,
      error: const Color(0xFFFF3B30),
      onError: Colors.white,
      surface: bg,
      onSurface: text,
      surfaceContainerHighest: surface,
      surfaceContainerHigh: surface2,
      primaryContainer: accent.withValues(alpha: 0.16),
      onPrimaryContainer: text,
      outlineVariant: gray.withValues(alpha: 0.35),
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final tt = base.textTheme.apply(bodyColor: text, displayColor: text);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      splashFactory: NoSplash.splashFactory,
      textTheme: tt.copyWith(
        headlineSmall: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6),
        titleLarge: tt.titleLarge?.copyWith(fontSize: 19, height: 1.6, fontWeight: FontWeight.w400, letterSpacing: -0.1),
        bodyLarge: tt.bodyLarge?.copyWith(fontSize: 17, height: 1.5),
        labelSmall: tt.labelSmall?.copyWith(color: gray, fontWeight: FontWeight.w600, letterSpacing: 0.6),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg.withValues(alpha: 0.86),
        foregroundColor: accent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(color: text, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3),
        shape: Border(bottom: BorderSide(color: gray.withValues(alpha: 0.25), width: 0.5)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      dividerTheme: DividerThemeData(color: gray.withValues(alpha: 0.25), thickness: 0.5, space: 0.5),
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
      progressIndicatorTheme: ProgressIndicatorThemeData(color: text, linearTrackColor: gray.withValues(alpha: 0.3)),
      sliderTheme: SliderThemeData(activeTrackColor: text, inactiveTrackColor: gray.withValues(alpha: 0.3), thumbColor: text, trackHeight: 4),
    );
  }
}
