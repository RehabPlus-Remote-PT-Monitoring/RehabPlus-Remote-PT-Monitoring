// lib/core/responsive.dart
//
// Tablet support: every screen was designed for a phone-width column. On a
// tablet (or a phone turned sideways) the same layout stretched edge to edge,
// so cards, lists and buttons became wide strips that are hard to read.
//
// Two tools keep content in a centred column no wider than
// [kReadableMaxWidth]. On a phone in portrait both do nothing (the screen is
// already narrower than that), so phone layouts are unchanged.
//
// 1. Scrolling content (ListView, SingleChildScrollView, CustomScrollView):
//    keep the scroll view FULL WIDTH and pad it with [readablePadding].
//    Wrapping a scroll view in a narrower box makes the empty sides dead:
//    a swipe there wouldn't scroll.
//
//      ListView(padding: readablePadding(context, const EdgeInsets.all(16)))
//
// 2. Content that doesn't scroll (a header row, a bottom button bar, a
//    message composer): wrap it in [ReadableWidth].
//
// Leave full-bleed screens alone: the camera exercise screen and the splash.
// Teal headers and app bars stay full width on purpose, like other Android
// tablet apps.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Widest the main content column may get, in logical pixels. 600 is
/// Android's own phone/tablet boundary (sw600dp), so on a tablet the content
/// looks the same as on a large phone.
const double kReadableMaxWidth = 600;

/// [base] padding for a full-width scroll view, plus the extra left and
/// right inset that centres its content in a [maxWidth] column.
///
/// Uses the screen width, so it is meant for scroll views that span the
/// screen (all of them in this app). The content ends up exactly as wide as
/// it would inside a [ReadableWidth] with the same [base] padding.
EdgeInsets readablePadding(
  BuildContext context, [
  EdgeInsets base = EdgeInsets.zero,
  double maxWidth = kReadableMaxWidth,
]) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  final side = math.max(0.0, (screenWidth - maxWidth) / 2);
  return base.copyWith(left: base.left + side, right: base.right + side);
}

/// Centres [child] in a column at most [maxWidth] wide. For content that
/// does not scroll; scroll views use [readablePadding] instead.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({
    super.key,
    required this.child,
    this.maxWidth = kReadableMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      // Be only as tall as the child. Without this, a ReadableWidth given a
      // loose height (e.g. Scaffold.bottomNavigationBar) would fill the
      // whole screen.
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
