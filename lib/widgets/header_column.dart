// lib/widgets/header_column.dart
//
// A page with the app's teal header on top and scrolling content below,
// where the content shows UNDER the header's rounded bottom corners.
//
// Why: the teal headers have rounded bottom corners (radius 32). With the
// usual `Column[header, Expanded(scroll view)]` the scroll view is clipped at
// the header's bottom edge, so scrolled cards were cut off in a flat line
// there while the rounded corners showed empty background on both sides
// (seen on Home on iPhone and Android). This is the same problem the bottom
// bar had (see lib/core/tab_bar_clearance.dart), mirrored to the top.
//
// How: [HeaderColumn] is a drop-in for that Column: its first child is the
// header, the rest are laid out as a Column right below it, exactly where
// they were before. The difference is painting:
//   * the content is painted BEFORE the header, so the header covers it;
//   * the content is clipped [kHeaderCornerOverlap] pixels ABOVE its top
//     edge instead of at it, so whatever it paints up there shows in the
//     header's two rounded corners.
// The scroll view under the header opts in with `clipBehavior: Clip.none`
// (otherwise it clips itself at its own top edge as before).
//
// Layout and scrolling are unchanged on purpose: the scroll view still
// starts at the header's bottom edge, so "scroll this field into view"
// (keyboard focus, ensureVisible) never parks content behind the header.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// How far above the content's top edge it may still be seen. Matches the
/// headers' bottom corner radius
/// (`BorderRadius.vertical(bottom: Radius.circular(32))`).
const double kHeaderCornerOverlap = 32;

/// Like `Column(children: [header, ...rest])`, except that `rest` can show
/// [overlap] pixels up into the header's rounded bottom corners.
class HeaderColumn extends StatelessWidget {
  const HeaderColumn({
    super.key,
    required this.children,
    this.overlap = kHeaderCornerOverlap,
  }) : assert(children.length >= 1, 'The first child is the header.');

  final List<Widget> children;
  final double overlap;

  @override
  Widget build(BuildContext context) {
    return CustomMultiChildLayout(
      delegate: _HeaderColumnDelegate(),
      // Order is paint (and reverse hit-test) order: content first, header
      // on top of it.
      children: [
        LayoutId(
          id: _Slot.body,
          child: ClipRect(
            clipper: _ExtendTopClipper(overlap),
            child: Column(children: children.sublist(1)),
          ),
        ),
        LayoutId(id: _Slot.header, child: children.first),
      ],
    );
  }
}

enum _Slot { header, body }

/// Header at the top at its natural height, content filling the rest.
class _HeaderColumnDelegate extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    // Header: full width and UNBOUNDED height, exactly what a Column gives
    // its non-flex children. A bounded height would let headers built from
    // a default (max-size) Column stretch to fill the whole page.
    final headerSize = layoutChild(
      _Slot.header,
      BoxConstraints(minWidth: size.width, maxWidth: size.width),
    );
    positionChild(_Slot.header, Offset.zero);

    final bodyTop = headerSize.height;
    layoutChild(
      _Slot.body,
      BoxConstraints.tight(
        Size(size.width, math.max(0.0, size.height - bodyTop)),
      ),
    );
    positionChild(_Slot.body, Offset(0, bodyTop));
  }

  @override
  bool shouldRelayout(_HeaderColumnDelegate oldDelegate) => false;
}

/// The child's own bounds, plus [extra] pixels above them.
class _ExtendTopClipper extends CustomClipper<Rect> {
  _ExtendTopClipper(this.extra);

  final double extra;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -extra, size.width, size.height);

  @override
  bool shouldReclip(_ExtendTopClipper oldClipper) => oldClipper.extra != extra;
}
