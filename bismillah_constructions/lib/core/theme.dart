import 'package:flutter/material.dart';

/// 60-30-10 colour distribution per design spec:
/// - 60% neutral base (Cool Gray surfaces / Deep Navy in dark)
/// - 30% structural blue (Deep Navy AppBar)
/// - 10% action (Indigo CTAs + 3% semantic Emerald/Rose for finance only)
ThemeData buildTheme({Brightness brightness = Brightness.light}) {
  // Indigo seed drives the primary palette — every FilledButton / ElevatedButton
  // / focus ring inherits from this. This is the "7%" of the 60-30-10 mix.
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3949AB), // Indigo 600
    brightness: brightness,
  );

  // Structural Deep Navy — the "30%" reserved for the AppBar. Kept
  // independent of the seed so the bar reads distinctly from indigo
  // button accents. A slightly lighter shade is used in dark mode to
  // avoid the eye-strain "wall of black-blue" effect.
  const deepNavyLight = Color(0xFF1A237E); // Indigo 900
  const deepNavyDark = Color(0xFF252F5C);  // mid-tone navy, easier on eyes

  // Cool Gray scaffold for light mode (the "60%" whitespace). For dark
  // mode we let Material 3 derive the scaffold from the seed
  // (`scheme.surface`) — it produces a soft indigo-tinted dark gray that
  // is comfortable for long sessions and still keeps the blue identity.
  const coolGrayLight = Color(0xFFF5F5F7);

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor:
        brightness == Brightness.light ? coolGrayLight : scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor:
          brightness == Brightness.light ? deepNavyLight : deepNavyDark,
      foregroundColor: Colors.white,
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

/// Strictly reserved for financial gain/loss per the design spec — never
/// for decorative accents elsewhere in the UI.
///
/// Emerald = positive (gain), Rose = negative (loss). Tuned for both
/// themes so the contrast meets WCAG AA against the scaffold colours.
class BalanceColors {
  /// Emerald 600 (light) / Emerald 400 (dark).
  static Color positive(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF34D399)
          : const Color(0xFF059669);

  /// Rose 600 (light) / Rose 400 (dark).
  static Color negative(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFFB7185)
          : const Color(0xFFE11D48);

  /// Picks Emerald (positive) or Rose (negative) based on the sign.
  static Color signed(BuildContext context, num value) =>
      value >= 0 ? positive(context) : negative(context);
}
