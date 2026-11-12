// lib/ios/glass_tab_bar.dart
//
// The dashboard's bottom tab bar on iPhone: a real UITabBar, which iOS 26+
// draws as a floating Liquid Glass capsule. Same four tabs, same order and
// the same callback as the Android pill bar in dashboard_screen.dart; only
// the drawing differs. Icons are SF Symbols (Phosphor icons can't go inside
// a native bar), chosen to match the Phosphor ones.

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../widgets/dashboard_sidebar.dart';

/// SF Symbol (normal, selected) for each dashboard tab label.
const Map<String, (String, String)> kTabSymbols = {
  'Home': ('house', 'house.fill'),
  'Exercise': (
    'figure.strengthtraining.traditional',
    'figure.strengthtraining.traditional',
  ),
  'Messages': ('bubble.left', 'bubble.left.fill'),
  'Profile': ('person.crop.circle', 'person.crop.circle.fill'),
};

class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onTap,
  });

  final List<DashboardDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return CNTabBar(
      tint: AppPalette.teal,
      // A little smaller than the system default (25 pt): the user asked
      // for lighter-looking tab icons.
      iconSize: 20,
      currentIndex: currentIndex,
      onTap: onTap,
      items: [
        for (final d in destinations)
          CNTabBarItem(
            label: d.label,
            icon: CNSymbol(kTabSymbols[d.label]?.$1 ?? 'circle'),
            activeIcon: CNSymbol(kTabSymbols[d.label]?.$2 ?? 'circle.fill'),
          ),
      ],
    );
  }
}
