// lib/core/responsive.dart
//
// Phone, tablet and landscape layout helpers.
//
// Widths (logical pixels; the Honor test tablet is ~807 wide in portrait and
// ~1290 in landscape, phones are 360-430 wide):
//
//   * < [kTwoColumnBreakpoint]: one centred column at most
//     [kReadableMaxWidth] wide. On a phone in portrait that is the whole
//     screen, so phone layouts are unchanged.
//   * >= [kTwoColumnBreakpoint]: screens that opt in lay their cards out in
//     two columns ([AdaptiveColumns]) inside [kWideMaxWidth].
//   * >= [kSidebarBreakpoint] (the dashboard only): a sidebar on the left
//     replaces the bottom tab bar. The dashboard then narrows MediaQuery's
//     size for the page area, so everything below measures the space it
//     really has, not the whole screen.
//
// How to use:
//
// 1. Scrolling content (ListView, SingleChildScrollView, CustomScrollView):
//    keep the scroll view FULL WIDTH and pad it with [readablePadding].
//    Wrapping a scroll view in a narrower box makes the empty sides dead:
//    a swipe there wouldn't scroll.
//
//      ListView(padding: readablePadding(context, const EdgeInsets.all(16)))
//
//    Screens with two columns pass `adaptiveMaxWidth(context)` instead of
//    the default narrow width.
//
// 2. Content that doesn't scroll (a header row, a bottom button bar, a
//    message composer): wrap it in [ReadableWidth].
//
// Leave full-bleed screens alone: the camera exercise screen and the splash.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Widest a single content column may get. Wide enough to use a portrait
/// tablet properly, narrow enough that lines of text stay readable.
const double kReadableMaxWidth = 680;

/// Widest the two-column layout may get (landscape tablets).
const double kWideMaxWidth = 1100;

/// From this width, screens that opt in show two columns.
const double kTwoColumnBreakpoint = 900;

/// From this width the dashboard shows a sidebar instead of the tab bar.
const double kSidebarBreakpoint = 1000;

/// Gap between the two columns, and the usual gap between cards.
const double kColumnGap = 16;

/// True when there is room for two columns of cards.
bool isTwoColumn(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kTwoColumnBreakpoint;

/// Max content width for a screen that switches to two columns when wide.
double adaptiveMaxWidth(BuildContext context) =>
    isTwoColumn(context) ? kWideMaxWidth : kReadableMaxWidth;

/// The extra left/right inset that centres content of [maxWidth] on this
/// screen (0 on phones). Headers use it to line their content up with the
/// column below them.
double readableInset(
  BuildContext context, [
  double maxWidth = kReadableMaxWidth,
]) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  return math.max(0.0, (screenWidth - maxWidth) / 2);
}

/// [base] padding for a full-width scroll view, plus the extra left and
/// right inset that centres its content in a [maxWidth] column.
///
/// Uses MediaQuery's width, so it is meant for scroll views that span the
/// page (all of them in this app). The content ends up exactly as wide as
/// it would inside a [ReadableWidth] with the same [base] padding.
EdgeInsets readablePadding(
  BuildContext context, [
  EdgeInsets base = EdgeInsets.zero,
  double maxWidth = kReadableMaxWidth,
]) {
  final side = readableInset(context, maxWidth);
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

/// Two columns of cards when the screen is wide, one column otherwise.
///
/// On a narrow screen the result is `left` followed by `right` in one
/// column, so put the most important cards in [left]. Each list keeps its
/// own spacing (add SizedBoxes between cards as you would in a Column).
/// Columns are top-aligned and independent, like iPad dashboards, so a tall
/// card on one side doesn't stretch the other.
class AdaptiveColumns extends StatelessWidget {
  const AdaptiveColumns({
    super.key,
    required this.left,
    required this.right,
    this.gap = kColumnGap,
  });

  final List<Widget> left;
  final List<Widget> right;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (!isTwoColumn(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [...left, ...right],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: left,
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: right,
          ),
        ),
      ],
    );
  }
}
