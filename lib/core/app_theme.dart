// lib/core/app_theme.dart
//
// The app-wide look, built once for light and once for dark mode.
//
// Direction (handoff.md, "UI polish"): RehabPlus should feel like an iPhone
// app on both phones and tablets. This file is the single place that sets
// the iOS-like foundations every screen inherits:
//
//   * Fonts: Inter, the closest free match to Apple's San Francisco (SF Pro
//     may only be used on Apple platforms). See pubspec.yaml.
//   * Type scale: Apple's text styles (large title 34, headline 17, body 17,
//     subheadline 15, footnote 13, caption 12) with size-specific tracking:
//     tighter as text gets bigger, never Material's positive letter spacing.
//   * platform: iOS. Flutter's adaptive widgets (Switch.adaptive,
//     CircularProgressIndicator.adaptive, RefreshIndicator.adaptive, text
//     selection, scroll bounce, back-button chevrons) take their iOS form.
//     This only changes Flutter's widgets: dart:io Platform and
//     defaultTargetPlatform still say Android, so plugins and Firebase are
//     unaffected.
//   * Page transitions: the iOS slide (new page from the right, the old one
//     drifting left underneath). On Android with gesture navigation the
//     system back swipe still works and plays the same slide.
//   * Colours: AppPalette (iOS grouped grey/black backgrounds, white or
//     dark-grey cards) plus the brand teal as the single accent.
//
// Screens should read text styles from Theme.of(context).textTheme for new
// UI. Many existing screens still pass explicit font sizes; those move onto
// the scale screen by screen (handoff.md, UI polish steps 5-10).

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Family name registered in pubspec.yaml.
const String kAppFontFamily = 'Inter';

/// Letter spacing for Inter at [size] logical pixels, from Inter's own
/// "dynamic metrics" (the same idea as Apple's SF tracking tables): about 0
/// at caption sizes, slightly negative for body, tighter for big titles.
double interTracking(double size) {
  const a = -0.0223, b = 0.185, c = -0.1745;
  final em = a + b * math.exp(c * size);
  return em * size;
}

TextStyle _style(double size, FontWeight weight, double height, Color color) =>
    TextStyle(
      fontFamily: kAppFontFamily,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: interTracking(size),
      color: color,
    );

/// Apple's text styles mapped onto Material's text theme roles.
TextTheme _textTheme(AppPalette p) => TextTheme(
  // Large Title / Title 1-3.
  displayLarge: _style(34, FontWeight.w700, 1.2, p.textPrimary),
  displayMedium: _style(28, FontWeight.w700, 1.2, p.textPrimary),
  displaySmall: _style(22, FontWeight.w700, 1.25, p.textPrimary),
  headlineLarge: _style(34, FontWeight.w700, 1.2, p.textPrimary),
  headlineMedium: _style(28, FontWeight.w700, 1.2, p.textPrimary),
  headlineSmall: _style(22, FontWeight.w700, 1.25, p.textPrimary),
  titleLarge: _style(20, FontWeight.w600, 1.25, p.textPrimary),
  // Headline (17 semibold) and a 15 semibold row title.
  titleMedium: _style(17, FontWeight.w600, 1.3, p.textPrimary),
  titleSmall: _style(15, FontWeight.w600, 1.3, p.textPrimary),
  // Body 17, Subheadline 15, Footnote 13.
  bodyLarge: _style(17, FontWeight.w400, 1.35, p.textPrimary),
  bodyMedium: _style(15, FontWeight.w400, 1.35, p.textPrimary),
  bodySmall: _style(13, FontWeight.w400, 1.35, p.textSecondary),
  // Buttons (17 semibold), small labels, Caption 12.
  labelLarge: _style(17, FontWeight.w600, 1.25, p.textPrimary),
  labelMedium: _style(13, FontWeight.w500, 1.3, p.textSecondary),
  labelSmall: _style(12, FontWeight.w500, 1.3, p.textSecondary),
);

/// The whole theme for one brightness.
ThemeData buildAppTheme(Brightness brightness) {
  final p = AppPalette.of(brightness);
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppPalette.teal,
    brightness: brightness,
    primary: AppPalette.teal,
    secondary: AppPalette.midTeal,
    surface: p.surface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    platform: TargetPlatform.iOS,
    fontFamily: kAppFontFamily,
    colorScheme: scheme,
    textTheme: _textTheme(p),
    extensions: [p],
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    dividerTheme: DividerThemeData(color: p.divider, thickness: 0.5, space: 1),
    // No Material ink ripples: iOS controls highlight instead.
    splashFactory: NoSplash.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    // iOS-style widgets (CupertinoAlertDialog, switches) use this.
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: AppPalette.teal,
      scaffoldBackgroundColor: p.background,
      barBackgroundColor: p.surface.withValues(alpha: 0.85),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? AppPalette.darkTeal : AppPalette.teal,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: _style(17, FontWeight.w600, 1.3, Colors.white),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: _style(17, FontWeight.w400, 1.3, p.textPrimary),
      subtitleTextStyle: _style(13, FontWeight.w400, 1.3, p.textSecondary),
      iconColor: AppPalette.teal,
      minVerticalPadding: 10,
    ),
    switchTheme: SwitchThemeData(
      // Used by Switch.adaptive's iOS form for the "on" track.
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? AppPalette.teal : null,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppPalette.teal,
        foregroundColor: Colors.white,
        minimumSize: const Size(44, 50),
        textStyle: _style(17, FontWeight.w600, 1.25, Colors.white),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        textStyle: _style(17, FontWeight.w600, 1.25, Colors.white),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppPalette.teal,
        textStyle: _style(17, FontWeight.w400, 1.25, AppPalette.teal),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      titleTextStyle: _style(17, FontWeight.w600, 1.3, p.textPrimary),
      contentTextStyle: _style(13, FontWeight.w400, 1.35, p.textPrimary),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      modalBackgroundColor: p.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF2C2C2E) : const Color(0xFF1C1C1E),
      contentTextStyle: _style(15, FontWeight.w400, 1.3, Colors.white),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.inputFill,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide.none,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: AppPalette.teal.withValues(alpha: 0.2),
    ),
  );
}
