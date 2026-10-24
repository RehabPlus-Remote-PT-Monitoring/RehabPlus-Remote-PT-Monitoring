// lib/core/app_palette.dart
//
// The app's colours for light and dark mode, by role (page background, card,
// main text, ...) instead of by value. Screens read them with
// `context.palette` so they follow Settings > Appearance:
//
//   color: context.palette.surface              // was Colors.white
//   style: TextStyle(color: context.palette.textPrimary)   // was black87
//
// Brand colours (teal, the header gradient) are the same in both modes:
// white text on teal reads well on a dark page too.

import 'package:flutter/material.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textFaint,
    required this.divider,
    required this.shadow,
    required this.inputFill,
  });

  /// Page background behind the cards (iOS grouped grey / black).
  final Color background;

  /// Cards, sheets, dialogs, list tiles (light: white).
  final Color surface;

  /// Chips, tracks of progress bars, empty-state circles (light: grey 100).
  final Color surfaceMuted;

  /// Headings and values (light: black87).
  final Color textPrimary;

  /// Body text and secondary values (light: black54).
  final Color textSecondary;

  /// Labels, subtitles, captions (light: black45 / black38).
  final Color textMuted;

  /// Chevrons, disabled icons, hints (light: black26).
  final Color textFaint;

  /// Dividers and card borders (light: grey 200).
  final Color divider;

  /// Card drop shadows. Use with the alpha the light design used; in dark
  /// mode it is pure black, which is barely visible, as intended.
  final Color shadow;

  /// Text field fill (light: 0xFFF4F7F8).
  final Color inputFill;

  // Brand colours, identical in both modes.
  static const Color teal = Color(0xFF23A8AA);
  static const Color darkTeal = Color(0xFF0D6E71);
  static const Color midTeal = Color(0xFF1A8587);

  /// The header gradient used across the app.
  static const List<Color> headerGradient = [darkTeal, midTeal, teal];

  // Values follow Apple's system colours so the app reads like an iPhone
  // app: grouped grey (light) / black (dark) page backgrounds with white or
  // dark-grey cards on top, and label colours as the same hue at falling
  // opacities. Hex comments name the iOS colour each one copies.

  static const AppPalette light = AppPalette(
    background: Color(0xFFF2F2F7), // systemGroupedBackground
    surface: Colors.white, // secondarySystemGroupedBackground
    surfaceMuted: Color(0xFFEFEFF4), // tertiarySystemGroupedBackground
    textPrimary: Color(0xFF000000), // label
    textSecondary: Color(0xBF3C3C43), // between label and secondaryLabel
    textMuted: Color(0x993C3C43), // secondaryLabel
    textFaint: Color(0x4D3C3C43), // tertiaryLabel (chevrons, hints)
    divider: Color(0x4A3C3C43), // separator
    shadow: Colors.black,
    inputFill: Color(0x1F767680), // tertiarySystemFill
  );

  static const AppPalette dark = AppPalette(
    background: Color(0xFF000000), // systemGroupedBackground (dark)
    surface: Color(0xFF1C1C1E), // secondarySystemGroupedBackground
    surfaceMuted: Color(0xFF2C2C2E), // tertiarySystemGroupedBackground
    textPrimary: Color(0xFFFFFFFF), // label
    textSecondary: Color(0xBFEBEBF5), // between label and secondaryLabel
    textMuted: Color(0x99EBEBF5), // secondaryLabel
    textFaint: Color(0x4DEBEBF5), // tertiaryLabel
    divider: Color(0xFF38383A), // opaqueSeparator
    shadow: Colors.black,
    inputFill: Color(0x3D767680), // tertiarySystemFill
  );

  /// The palette for a brightness (used by the theme and by tests).
  static AppPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textFaint,
    Color? divider,
    Color? shadow,
    Color? inputFill,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      divider: divider ?? this.divider,
      shadow: shadow ?? this.shadow,
      inputFill: inputFill ?? this.inputFill,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceMuted: mix(surfaceMuted, other.surfaceMuted),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      textFaint: mix(textFaint, other.textFaint),
      divider: mix(divider, other.divider),
      shadow: mix(shadow, other.shadow),
      inputFill: mix(inputFill, other.inputFill),
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// The current palette. Falls back to the light one when the theme has no
  /// [AppPalette] (e.g. a widget test that builds a bare MaterialApp).
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ??
      AppPalette.of(Theme.of(this).brightness);

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}
