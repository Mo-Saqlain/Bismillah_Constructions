import 'package:flutter/material.dart';

/// Material-3 palette: a neutral surface scaffold and AppBar so the
/// only saturated element on screen is the floating indigo pill nav.
/// Title and AppBar icons take the indigo primary so the AppBar
/// echoes the pill's colour identity without slabbing a navy block
/// across the top of every screen.
///
///  * Surfaces  — Cool gray in light, M3-derived dark gray in dark.
///  * AppBar    — surface bg, indigo title + icons, hairline divider.
///  * Accent    — indigo seed drives buttons, focus rings, the pill.
///  * Finance   — emerald / rose strictly for signed money values.
ThemeData buildTheme({Brightness brightness = Brightness.light}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3949AB), // Indigo 600
    brightness: brightness,
  );

  // Cool Gray scaffold for light mode. Dark mode falls back to the
  // M3-derived surface — a soft indigo-tinted dark gray that is
  // comfortable for long sessions.
  const coolGrayLight = Color(0xFFF5F5F7);
  final appBarBg = brightness == Brightness.light
      ? coolGrayLight
      : scheme.surface;

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: appBarBg,
    appBarTheme: AppBarTheme(
      backgroundColor: appBarBg,
      foregroundColor: scheme.primary,
      // Disable Material 3's automatic scrolled-tint so the bar stays
      // flat with the scaffold instead of darkening on scroll.
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.primary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.15,
      ),
      iconTheme: IconThemeData(color: scheme.primary),
      // Hairline divider below the bar to separate it from the body
      // now that the colour is no longer doing that job.
      shape: Border(
        bottom: BorderSide(color: scheme.outlineVariant, width: 1),
      ),
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
