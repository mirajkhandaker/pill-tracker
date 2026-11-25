import 'package:flutter/material.dart';

/// Material 3 light/dark themes tuned for an elderly-friendly, high-contrast UI:
/// large body text (>=16sp), tall tap targets (>=48dp), generous padding,
/// rounded corners, and clear focus indicators.
abstract final class AppTheme {
  static const Color primary = Color(0xFF00897B); // teal
  static const Color secondary = Color(0xFFFFB300); // amber

  static const double radius = 12;
  static const double padding = 16;
  static const double minButtonHeight = 48;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      secondary: secondary,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: _textTheme(base.textTheme),
      cardTheme: CardThemeData(
        elevation: 1,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, minButtonHeight),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, minButtonHeight),
          textStyle: const TextStyle(fontSize: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: padding,
          vertical: 14,
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  /// Bumps the baseline font sizes so nothing on screen is below ~16sp.
  static TextTheme _textTheme(TextTheme t) => t.copyWith(
    bodyLarge: t.bodyLarge?.copyWith(fontSize: 17),
    bodyMedium: t.bodyMedium?.copyWith(fontSize: 16),
    titleMedium: t.titleMedium?.copyWith(fontSize: 18),
    titleLarge: t.titleLarge?.copyWith(fontSize: 22),
    labelLarge: t.labelLarge?.copyWith(fontSize: 16),
  );
}
