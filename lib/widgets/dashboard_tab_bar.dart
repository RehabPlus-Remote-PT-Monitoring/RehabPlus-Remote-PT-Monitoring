// lib/widgets/dashboard_tab_bar.dart
//
// The iOS tab bar of the dashboard (phones and tablets narrower than
// kSidebarBreakpoint): a full-width bar attached to the bottom edge,
// translucent with a blur so the page scrolls visibly underneath it, a
// hairline on top, and every tab showing its icon AND its label (filled
// teal icon when selected, grey outline otherwise), 49 pt tall plus the
// home-indicator / navigation-bar inset, like UITabBar.
//
// The Scaffold hosting it must use `extendBody: true`; Scaffold then adds the
// bar's height to MediaQuery.padding.bottom for the body, so scroll views
// that respect that padding clear the bar at the end of their content.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/app_palette.dart';

/// One top-level destination of the dashboard (Home, Exercise, ...), shared
/// by the tab bar and the tablet sidebar.
class DashboardDestination {
  const DashboardDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.badge,
  });

  final String label;

  /// Outline icon, shown when the destination is not selected.
  final IconData icon;

  /// Filled icon, shown when it is selected (iOS convention).
  final IconData selectedIcon;

  /// Optional badge next to the icon (e.g. unread messages). Its own
  /// semantics are merged into the destination's label.
  final Widget? badge;
}

class DashboardTabBar extends StatelessWidget {
  const DashboardTabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
  });

  /// UITabBar's height without the bottom safe area.
  static const double barHeight = 49;

  /// iOS tab bars stop growing with Dynamic Type (iOS shows a large preview
  /// on long-press instead). Clamp the label so it never overflows the bar.
  static const double _maxLabelScale = 1.3;

  final List<DashboardDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Only the blur behind the bar, not the whole screen.
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: 0.85),
            border: Border(
              top: BorderSide(color: palette.divider, width: 0.5),
            ),
          ),
          child: SafeArea(
            top: false,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: _maxLabelScale,
              child: SizedBox(
                height: barHeight,
                child: Row(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Expanded(
                        child: _TabItem(
                          destination: destinations[i],
                          selected: i == selectedIndex,
                          onTap: () => onSelect(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final DashboardDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppPalette.teal : context.palette.textMuted;
    final badge = destination.badge;

    // One accessibility node per tab: "Messages, 2 unread, selected, tab".
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        label: destination.label,
        child: GestureDetector(
          // The whole cell is the target, not just the icon.
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 25,
                    color: color,
                  ),
                  if (badge != null)
                    Positioned(left: 16, top: -5, child: badge),
                ],
              ),
              const SizedBox(height: 2),
              // The label is already the node's semantic label.
              ExcludeSemantics(
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
