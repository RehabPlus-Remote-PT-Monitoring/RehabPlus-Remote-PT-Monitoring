// Tests for lib/core/responsive.dart: content stays in a readable column on
// wide screens, and the empty sides of a scroll view still scroll.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/responsive.dart';

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  testWidgets('readablePadding adds nothing on a phone-width screen', (
    tester,
  ) async {
    late EdgeInsets padding;
    await pumpAt(
      tester,
      const Size(400, 800),
      Builder(
        builder: (context) {
          padding = readablePadding(context, const EdgeInsets.all(16));
          return const SizedBox();
        },
      ),
    );
    expect(padding, const EdgeInsets.all(16));
  });

  testWidgets('readablePadding centres a 600-wide column on a tablet', (
    tester,
  ) async {
    late EdgeInsets padding;
    await pumpAt(
      tester,
      const Size(1280, 800),
      Builder(
        builder: (context) {
          padding = readablePadding(context, const EdgeInsets.all(16));
          return const SizedBox();
        },
      ),
    );
    // (1280 - 680) / 2 = 300 extra on each side; top/bottom untouched.
    expect(padding, const EdgeInsets.fromLTRB(316, 16, 316, 16));
  });

  testWidgets('a swipe in the empty side of the list still scrolls it', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpAt(
      tester,
      const Size(1280, 800),
      Builder(
        builder: (context) => ListView(
          controller: controller,
          padding: readablePadding(context),
          children: [
            for (var i = 0; i < 50; i++)
              SizedBox(height: 80, child: Text('row $i')),
          ],
        ),
      ),
    );

    // x = 100 is well outside the centred column (300..980).
    await tester.dragFrom(const Offset(100, 600), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
  });
}
