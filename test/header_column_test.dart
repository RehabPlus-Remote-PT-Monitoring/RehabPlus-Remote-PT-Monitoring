import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/widgets/header_column.dart';

/// A 100 px tall header with rounded bottom corners, like the app's.
Widget _header() => Container(
      key: const Key('header'),
      height: 100,
      decoration: const BoxDecoration(
        color: Colors.teal,
        borderRadius:
            BorderRadius.vertical(bottom: Radius.circular(kHeaderCornerOverlap)),
      ),
    );

Future<void> _pump(WidgetTester tester, List<Widget> rest) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: HeaderColumn(children: [_header(), ...rest])),
    ),
  );
}

void main() {
  testWidgets('lays out like a Column: header, then the rest below it',
      (tester) async {
    await _pump(tester, [
      const Expanded(child: SizedBox.expand(key: Key('body'))),
      const SizedBox(key: Key('bar'), height: 40),
    ]);

    final header = tester.getRect(find.byKey(const Key('header')));
    final body = tester.getRect(find.byKey(const Key('body')));
    final bar = tester.getRect(find.byKey(const Key('bar')));
    expect(header.top, 0);
    expect(header.width, 400);
    expect(body.top, header.bottom);
    expect(bar.top, body.bottom);
    expect(bar.bottom, 800);
  });

  testWidgets('a header built from a plain Column keeps its natural height',
      (tester) async {
    // A default Column is max-size along its main axis; under a bounded
    // height it would stretch to the whole page and push the content off.
    await _pump(tester, []);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeaderColumn(
            children: [
              const Column(
                key: Key('header'),
                children: [SizedBox(height: 120)],
              ),
              const Expanded(child: SizedBox.expand(key: Key('body'))),
            ],
          ),
        ),
      ),
    );

    expect(tester.getRect(find.byKey(const Key('header'))).height, 120);
    expect(tester.getRect(find.byKey(const Key('body'))).top, 120);
  });

  testWidgets('the content is clipped kHeaderCornerOverlap above its top',
      (tester) async {
    await _pump(tester, [const Expanded(child: SizedBox.expand())]);

    final clip = tester.renderObject<RenderClipRect>(
      find.descendant(
        of: find.byType(HeaderColumn),
        matching: find.byType(ClipRect),
      ),
    );
    final rect = clip.clipper!.getClip(clip.size);
    expect(rect.top, -kHeaderCornerOverlap);
    expect(rect.bottom, clip.size.height);
  });

  testWidgets('the header is painted and hit-tested above the content',
      (tester) async {
    var headerTaps = 0;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeaderColumn(
            children: [
              GestureDetector(onTap: () => headerTaps++, child: _header()),
              const Expanded(child: SizedBox.expand()),
            ],
          ),
        ),
      ),
    );

    // The header is the last child painted.
    final layout = tester.renderObject<RenderCustomMultiChildLayoutBox>(
      find.descendant(
        of: find.byType(HeaderColumn),
        matching: find.byType(CustomMultiChildLayout),
      ),
    );
    final lastPainted = layout.lastChild!;
    final headerBox = tester.renderObject(find.byKey(const Key('header')));
    var node = headerBox;
    while (node.parent != layout) {
      node = node.parent!;
    }
    expect(node, same(lastPainted));

    await tester.tapAt(const Offset(200, 50));
    expect(headerTaps, 1);
  });

  testWidgets('a scroll view with Clip.none shows in the header corners',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pump(tester, [
      Expanded(
        child: ListView(
          controller: controller,
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < 30; i++)
              SizedBox(key: Key('row$i'), height: 50),
          ],
        ),
      ),
    ]);
    controller.jumpTo(75);
    await tester.pump();

    // Row 1 (50..100) scrolled up by 75 now spans -25..25 relative to the
    // list, i.e. it reaches up into the header's bottom 25 px and is still
    // built (not dropped as off-screen).
    final header = tester.getRect(find.byKey(const Key('header')));
    final row1 = tester.getRect(find.byKey(const Key('row1')));
    expect(row1.top, header.bottom - 25);
  });
}
