import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const yellow = Color(0xFFFFC928);
  static const ink = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const surface = Color(0xFFFBFAF7);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: yellow,
      brightness: Brightness.light,
    ).copyWith(primary: yellow, onPrimary: ink, surface: surface);

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surface,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: yellow,
          foregroundColor: ink,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
