import 'package:flutter/material.dart';

ThemeData buildTheme({Brightness brightness = Brightness.light}) {
  final scheme = ColorScheme.fromSeed(
    // Material Blue 800 — strong, professional, readable on white & dark.
    seedColor: const Color(0xFF1565C0),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
      ),
    ),
  );
}

/// High-contrast indicator colors per spec section 4.
///
/// The palette is intentionally green-free — the app standardised on blue for
/// every "good / positive" affordance. Negatives stay red because that's the
/// universal accounting convention and the only non-blue accent we keep.
class BalanceColors {
  /// Material Blue 700 (light) / Blue 300 (dark). Replaces the green that
  /// used to mean "positive balance".
  static Color positive(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF64B5F6)
          : const Color(0xFF1976D2);

  static Color negative(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFEF5350)
          : const Color(0xFFC62828);

  /// Picks blue (positive) or red (negative) based on the sign.
  static Color signed(BuildContext context, num value) =>
      value >= 0 ? positive(context) : negative(context);
}
