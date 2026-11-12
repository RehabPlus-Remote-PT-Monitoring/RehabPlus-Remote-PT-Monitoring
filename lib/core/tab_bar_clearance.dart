// lib/core/tab_bar_clearance.dart
//
// Room at the bottom of a tab page for the dashboard's bottom bar.
//
// The dashboard Scaffold draws its pages BEHIND the bottom bar
// (`extendBody: true`), so the bar's rounded top corners and its shadow show
// the page scrolling underneath instead of a flat cut-off edge. Scaffold then
// reports the bar's real height (system navigation inset included) as the
// page's MediaQuery bottom padding.
//
// ListView with no padding of its own adds that padding by itself, but a
// scroll view that sets its own padding (readablePadding, a fixed inset) or a
// SingleChildScrollView does not. Without it the last card would end up
// under the bar and could not be scrolled into view. Those scroll views wrap
// their padding in [withTabBarClearance].

import 'package:flutter/widgets.dart';

/// [base] plus the page's bottom MediaQuery padding, which on the dashboard
/// tabs is the bottom bar's height. Outside the dashboard it is just the
/// system's bottom inset, which is also the right amount of room.
EdgeInsets withTabBarClearance(BuildContext context, EdgeInsets base) {
  return base.copyWith(
    bottom: base.bottom + MediaQuery.paddingOf(context).bottom,
  );
}
