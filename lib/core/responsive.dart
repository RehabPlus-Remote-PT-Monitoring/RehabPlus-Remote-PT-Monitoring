// lib/core/responsive.dart
//
// Tablet support: every screen was designed for a phone-width column. On a
// tablet (or a phone turned sideways) the same layout stretched edge to edge,
// so cards, lists and buttons became wide strips that are hard to read.
//
// `ReadableWidth` keeps a screen's content in a centred column no wider than
// [kReadableMaxWidth]. On a phone in portrait it does nothing (the screen is
// already narrower than that), so phone layouts are unchanged.
//
// How to use it: wrap a Scaffold's `body:` (and a custom bottom bar), e.g.
//
//   body: ReadableWidth(child: ListView(...)),
//
// Leave full-bleed screens alone: the camera exercise screen and the splash.
// App bars stay full width on purpose, like other Android tablet apps.

import 'package:flutter/widgets.dart';

/// Widest the main content column may get, in logical pixels. 600 is
/// Android's own phone/tablet boundary (sw600dp), so on a tablet the content
/// looks the same as on a large phone.
const double kReadableMaxWidth = 600;

/// Centres [child] in a column at most [maxWidth] wide.
///
/// The child still gets the full height, so scrolling lists, `Expanded` and
/// bottom-anchored buttons keep working exactly as they do on a phone.
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
