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

  /// Page background behind the cards (light: 0xFFF0F4F4).
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

  static const AppPalette light = AppPalette(
    background: Color(0xFFF0F4F4),
    surface: Colors.white,
    surfaceMuted: Color(0xFFF5F5F5),
    textPrimary: Color(0xDD000000), // black87
    textSecondary: Color(0x8A000000), // black54
    textMuted: Color(0x73000000), // black45
    textFaint: Color(0x42000000), // black26
    divider: Color(0xFFEEEEEE), // grey 200
    shadow: Colors.black,
    inputFill: Color(0xFFF4F7F8),
  );

  static const AppPalette dark = AppPalette(
    background: Color(0xFF0E1717),
    surface: Color(0xFF182323),
    surfaceMuted: Color(0xFF223030),
    textPrimary: Color(0xEBFFFFFF), // white 92%
    textSecondary: Color(0xB3FFFFFF), // white70
    textMuted: Color(0x8AFFFFFF), // white54
    textFaint: Color(0x61FFFFFF), // white38
    divider: Color(0x1FFFFFFF), // white12
    shadow: Colors.black,
    inputFill: Color(0xFF223030),
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
