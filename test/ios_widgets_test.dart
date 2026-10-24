// Smoke tests for the shared iOS-style widgets: they must build inside the
// app's real theme in light and dark mode without layout errors, and the
// interactive ones must respond.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/app_theme.dart';
import 'package:rehabplus/core/responsive.dart';
import 'package:rehabplus/widgets/ios_list.dart';
import 'package:rehabplus/widgets/ios_page.dart';
import 'package:rehabplus/widgets/pressable.dart';

void main() {
  Widget app(Widget home, Brightness b) =>
      MaterialApp(theme: buildAppTheme(b), home: home);

  for (final brightness in Brightness.values) {
    testWidgets('IosPage with sections builds ($brightness)', (tester) async {
      var tapped = 0;
      var switched = false;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) => IosPage(
              title: 'Settings',
              previousPageTitle: 'Profile',
              children: [
                IosSection(
                  header: 'Account',
                  footer: 'A footnote.',
                  children: [
                    IosRow(
                      icon: CupertinoIcons.lock,
                      title: 'App lock',
                      value: 'On',
                      onTap: () => tapped++,
                    ),
                    IosSwitchRow(
                      icon: CupertinoIcons.bell,
                      title: 'Reminders',
                      value: switched,
                      onChanged: (v) => setState(() => switched = v),
                    ),
                    const IosControlRow(title: 'Theme', child: Text('ctrl')),
                  ],
                ),
              ],
            ),
          ),
          brightness,
        ),
      );
      expect(find.text('ACCOUNT'), findsOneWidget);
      await tester.tap(find.text('App lock'));
      await tester.tap(find.text('Reminders'));
      await tester.pumpAndSettle();
      expect(tapped, 1);
      expect(switched, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Pressable taps and AdaptiveColumns goes two-up when wide', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var taps = 0;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: AdaptiveColumns(
            left: [Pressable(onTap: () => taps++, child: const Text('L'))],
            right: const [Text('R')],
          ),
        ),
        Brightness.light,
      ),
    );
    await tester.tap(find.text('L'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    // Side by side: same top, R to the right of L.
    final l = tester.getTopLeft(find.text('L'));
    final r = tester.getTopLeft(find.text('R'));
    expect(r.dy, l.dy);
    expect(r.dx, greaterThan(l.dx + 400));
  });
}
