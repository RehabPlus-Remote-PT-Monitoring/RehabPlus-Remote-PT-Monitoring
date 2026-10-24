// lib/widgets/dashboard_sidebar.dart
//
// The navigation the dashboard shows instead of the bottom bar on wide
// screens (>= kSidebarBreakpoint, e.g. a tablet in landscape): the app name
// at the top, then one row per tab with its icon and label.
//
// It uses the same look as the bottom bar (Phosphor icons, faint when not
// selected, a teal gradient pill with white icon and label when selected),
// so the app looks the same on a phone and a tablet, just arranged for the
// width.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/app_palette.dart';

/// One tab of the dashboard, shared by the bottom bar and the sidebar.
class DashboardDestination {
  const DashboardDestination({required this.label, required this.icon});

  final String label;
  final PhosphorIconData icon;
}

class DashboardSidebar extends StatelessWidget {
  const DashboardSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
  });

  /// Total width. The dashboard narrows the page area's MediaQuery by
  /// exactly this much, so the pages measure the space they really have.
  static const double width = 240;

  static const Color _teal = Color(0xFF23A8AA);
  static const Color _darkTeal = Color(0xFF0D6E71);

  final List<DashboardDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: palette.surface,
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: SafeArea(
        right: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
          children: [
            _buildAppName(palette),
            const SizedBox(height: 26),
            for (var i = 0; i < destinations.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
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

  /// The same shield logo and name as the Home header, in brand teal.
  Widget _buildAppName(AppPalette palette) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_teal, _darkTeal]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: PhosphorIcon(
            PhosphorIcons.shieldPlus(),
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Rehab +',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: palette.textPrimary,
          ),
        ),
      ],
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

  static const Duration _duration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = selected ? Colors.white : palette.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selected ? null : onTap,
        child: AnimatedContainer(
          duration: _duration,
          curve: Curves.easeInOutCubic,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [DashboardSidebar._teal, DashboardSidebar._darkTeal],
                  )
                : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: DashboardSidebar._teal.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              PhosphorIcon(destination.icon, size: 22, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
