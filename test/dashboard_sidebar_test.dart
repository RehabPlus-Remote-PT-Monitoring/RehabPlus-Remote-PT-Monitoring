// The tablet sidebar the dashboard shows instead of the bottom bar on wide
// screens (lib/widgets/dashboard_sidebar.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:rehabplus/core/app_palette.dart';
import 'package:rehabplus/widgets/dashboard_sidebar.dart';

void main() {
  final destinations = [
    DashboardDestination(label: 'Home', icon: PhosphorIcons.squaresFour()),
    DashboardDestination(label: 'Exercise', icon: PhosphorIcons.barbell()),
    DashboardDestination(label: 'Messages', icon: PhosphorIcons.chatCircle()),
    DashboardDestination(label: 'Profile', icon: PhosphorIcons.userCircle()),
  ];

  Future<List<int>> pumpSidebar(WidgetTester tester, int selected) async {
    final taps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.light]),
        home: Scaffold(
          body: Row(
            children: [
              DashboardSidebar(
                destinations: destinations,
                selectedIndex: selected,
                onSelect: taps.add,
              ),
            ],
          ),
        ),
      ),
    );
    return taps;
  }

  testWidgets('shows every tab and reports taps on the others', (
    tester,
  ) async {
    final taps = await pumpSidebar(tester, 0);

    for (final d in destinations) {
      expect(find.text(d.label), findsOneWidget);
    }
    await tester.tap(find.text('Messages'));
    await tester.tap(find.text('Profile'));
    // Tapping the open tab again does nothing.
    await tester.tap(find.text('Home'));
    expect(taps, [2, 3]);
  });

  testWidgets('is exactly as wide as the shell subtracts from the page', (
    tester,
  ) async {
    await pumpSidebar(tester, 1);
    expect(
      tester.getSize(find.byType(DashboardSidebar)).width,
      DashboardSidebar.width,
    );
  });

  testWidgets('marks the open tab as selected for screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpSidebar(tester, 2);
    expect(
      tester.getSemantics(find.text('Messages')),
      matchesSemantics(
        label: 'Messages',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
      ),
    );
    handle.dispose();
  });
}
