import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:rehabplus/ios/glass_tab_bar.dart';
import 'package:rehabplus/widgets/dashboard_sidebar.dart';

void main() {
  final destinations = [
    DashboardDestination(label: 'Home', icon: PhosphorIcons.squaresFour()),
    DashboardDestination(label: 'Exercise', icon: PhosphorIcons.barbell()),
    DashboardDestination(label: 'Messages', icon: PhosphorIcons.chatCircle()),
    DashboardDestination(label: 'Profile', icon: PhosphorIcons.userCircle()),
  ];

  test('every dashboard tab has an SF Symbol pair', () {
    for (final d in destinations) {
      expect(kTabSymbols.containsKey(d.label), isTrue, reason: d.label);
    }
  });

  testWidgets('builds a native tab bar with the dashboard tabs', (
    tester,
  ) async {
    int? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GlassTabBar(
            destinations: destinations,
            currentIndex: 2,
            onTap: (i) => tapped = i,
          ),
        ),
      ),
    );
    final bar = tester.widget<CNTabBar>(find.byType(CNTabBar));
    expect(bar.items.map((i) => i.label), [
      'Home',
      'Exercise',
      'Messages',
      'Profile',
    ]);
    expect(bar.currentIndex, 2);
    // A little smaller than the system default (25) so the bar feels lighter.
    expect(bar.iconSize, 20);
    bar.onTap(3);
    expect(tapped, 3);
    // The package's fallback bar schedules a short internal timer.
    await tester.pump(const Duration(seconds: 2));
  });
}
