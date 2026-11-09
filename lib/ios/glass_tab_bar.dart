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
import 'ios_chrome.dart';

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

/// [base] padding for a tab page's scroll view, plus room at the bottom
/// for the floating glass tab bar on iPhone.
///
/// The dashboard Scaffold uses `extendBody`, so the page's MediaQuery
/// bottom padding already equals the bar's real height (home indicator
/// included). Scroll views that set their own padding don't pick that up
/// by themselves, so they add it here. Android: [base] unchanged.
EdgeInsets withTabBarClearance(BuildContext context, EdgeInsets base) {
  if (!useIosChrome) return base;
  return base.copyWith(
    bottom: base.bottom + MediaQuery.paddingOf(context).bottom,
  );
}

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
