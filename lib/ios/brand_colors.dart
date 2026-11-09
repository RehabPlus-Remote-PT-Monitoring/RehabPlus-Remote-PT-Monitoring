// lib/ios/brand_colors.dart
//
// Colour changes for the iPhone look, kept out of the screens so Android is
// untouched:
//
// - [brandGradient]: the teal header/button gradients become one solid
//   teal on iPhone (the user wanted fewer gradients). On Android it returns
//   exactly the gradient the call site described.
// - [AppAccents]: three supporting colours next to teal, each with one job:
//     coral  streaks, achievements and "today" highlights
//     mint   completed / done
//     amber  warnings
//   Light-mode shades are deep enough for text (WCAG AA 4.5:1 on white
//   and on the pale green/orange chip tints); dark mode uses brighter
//   tints. On Android each returns the colour the call site used before
//   ([fallback]).

import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import 'ios_chrome.dart';

/// A brand-teal fill. iPhone: solid mid teal, dark enough for white text.
/// Android: the gradient described by [colors], [begin] and [end].
Gradient brandGradient(
  List<Color> colors, {
  AlignmentGeometry begin = Alignment.centerLeft,
  AlignmentGeometry end = Alignment.centerRight,
}) {
  if (useIosChrome) {
    // A gradient between two equal colours is a solid fill. Keeping the
    // Gradient type means call sites only swap the constructor.
    return const LinearGradient(
      colors: [AppPalette.midTeal, AppPalette.midTeal],
    );
  }
  return LinearGradient(colors: colors, begin: begin, end: end);
}

/// Supporting colours for the iPhone look (see the file comment).
abstract final class AppAccents {
  static const Color _coralLight = Color(0xFFB8401A);
  static const Color _coralDark = Color(0xFFFF9479);
  static const Color _mintLight = Color(0xFF137A55);
  static const Color _mintDark = Color(0xFF5FD3A8);
  static const Color _amberLight = Color(0xFFA15C00);
  static const Color _amberDark = Color(0xFFFFC14D);

  /// Streaks, achievements, "today" highlights.
  static Color coral(BuildContext context, {required Color fallback}) =>
      _pick(context, fallback, _coralLight, _coralDark);

  /// Completed / done.
  static Color mint(BuildContext context, {required Color fallback}) =>
      _pick(context, fallback, _mintLight, _mintDark);

  /// Warnings.
  static Color amber(BuildContext context, {required Color fallback}) =>
      _pick(context, fallback, _amberLight, _amberDark);

  static Color _pick(
    BuildContext context,
    Color fallback,
    Color light,
    Color dark,
  ) {
    if (!useIosChrome) return fallback;
    return context.isDarkMode ? dark : light;
  }
}
