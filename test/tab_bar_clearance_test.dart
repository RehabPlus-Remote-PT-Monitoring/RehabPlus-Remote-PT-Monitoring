import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/tab_bar_clearance.dart';

/// A tab page under a Scaffold that draws it behind a 80 px bottom bar
/// (`extendBody: true`), like the dashboard on phones.
Widget _pageBehindBar(void Function(BuildContext) onBuild) {
  return MaterialApp(
    home: Scaffold(
      extendBody: true,
      body: Builder(
        builder: (context) {
          onBuild(context);
          return const SizedBox.expand();
        },
      ),
      bottomNavigationBar: const SizedBox(height: 80),
    ),
  );
}

void main() {
  testWidgets('adds the bottom bar height to the page padding', (tester) async {
    late EdgeInsets padding;
    await tester.pumpWidget(
      _pageBehindBar((context) {
        padding = withTabBarClearance(
          context,
          const EdgeInsets.fromLTRB(16, 0, 16, 16),
        );
      }),
    );

    expect(padding.left, 16);
    expect(padding.right, 16);
    expect(padding.top, 0);
    // 16 of its own plus the 80 px bar the page is drawn behind.
    expect(padding.bottom, 96);
  });

  testWidgets('without a bottom bar only the base padding is used',
      (tester) async {
    late EdgeInsets padding;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            padding = withTabBarClearance(context, const EdgeInsets.all(8));
            return const SizedBox.expand();
          },
        ),
      ),
    );

    expect(padding, const EdgeInsets.all(8));
  });
}
