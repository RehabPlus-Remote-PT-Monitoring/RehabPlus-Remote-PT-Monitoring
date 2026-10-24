// lib/widgets/dashboard_sidebar.dart
//
// The iPad-style sidebar the dashboard shows instead of the tab bar on wide
// screens (>= kSidebarBreakpoint, e.g. a tablet in landscape): the app name
// at the top, then one row per destination with its icon and label. The
// selected row gets a rounded teal tint, like the iPadOS sidebar.

import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import 'dashboard_tab_bar.dart' show DashboardDestination;
import 'pressable.dart';

class DashboardSidebar extends StatelessWidget {
  const DashboardSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    required this.header,
  });

  /// Total width, including the hairline on its right edge. The dashboard
  /// narrows the page area's MediaQuery by exactly this much.
  static const double width = 260;

  final List<DashboardDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// App name / logo shown above the destinations.
  final Widget header;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(right: BorderSide(color: palette.divider, width: 0.5)),
      ),
      child: SafeArea(
        right: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
              child: header,
            ),
            for (var i = 0; i < destinations.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _SidebarRow(
                  destination: destinations[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final DashboardDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final badge = destination.badge;
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        child: Pressable(
          onTap: onTap,
          semanticLabel: destination.label,
          pressedScale: 0.98,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? AppPalette.teal.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 22,
                  color: selected ? AppPalette.teal : palette.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  // The label is already the row's semantic label.
                  child: ExcludeSemantics(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected ? AppPalette.teal : palette.textPrimary,
                      ),
                    ),
                  ),
                ),
                ?badge,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
