// Tests for the Messages tab's tablet split view (MessagesLayout in
// lib/screens/messages_screen.dart): phones show only the thread list,
// wide screens show the list beside the selected conversation, and
// switching threads replaces (disposes) the old conversation.
//
// The real list and chat need Firebase, so these tests pass simple
// stand-ins through the layout's builders.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/responsive.dart';
import 'package:rehabplus/models/chat.dart';
import 'package:rehabplus/screens/messages_screen.dart';

/// Stand-in conversation that records its lifecycle, so a test can check
/// the right pane is rebuilt (and its listeners cancelled) per thread.
class _FakeChat extends StatefulWidget {
  const _FakeChat({required this.thread, required this.events});

  final ChatThread thread;
  final List<String> events;

  @override
  State<_FakeChat> createState() => _FakeChatState();
}

class _FakeChatState extends State<_FakeChat> {
  @override
  void initState() {
    super.initState();
    widget.events.add('open ${widget.thread.name}');
  }

  @override
  void dispose() {
    widget.events.add('close ${widget.thread.name}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('chat ${widget.thread.name}');
}

/// Hosts MessagesLayout with a selection that list taps change, like
/// MessagesScreen does.
class _Harness extends StatefulWidget {
  const _Harness({required this.events, required this.widths});

  final List<String> events;

  /// Pane widths seen by the builders (from their MediaQuery).
  final Map<String, double> widths;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  // Starts with nothing selected, like MessagesScreen.
  ChatThread? _selected;

  @override
  Widget build(BuildContext context) {
    return MessagesLayout(
      selected: _selected,
      listBuilder: (context, split) {
        widget.widths['list'] = MediaQuery.sizeOf(context).width;
        return Column(
          children: [
            Text(split ? 'list (split)' : 'list (push)'),
            for (final thread in ChatThread.values)
              TextButton(
                onPressed: () => setState(() => _selected = thread),
                child: Text('tile ${thread.name}'),
              ),
          ],
        );
      },
      detailBuilder: (context, thread) {
        widget.widths['detail'] = MediaQuery.sizeOf(context).width;
        return _FakeChat(thread: thread, events: widget.events);
      },
    );
  }
}

void main() {
  late List<String> events;
  late Map<String, double> widths;

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _Harness(events: events, widths: widths)),
      ),
    );
  }

  setUp(() {
    events = [];
    widths = {};
  });

  test('the split starts at the two-column breakpoint', () {
    expect(showsMessagesSplit(400), isFalse);
    expect(showsMessagesSplit(kTwoColumnBreakpoint - 1), isFalse);
    expect(showsMessagesSplit(kTwoColumnBreakpoint), isTrue);
    expect(showsMessagesSplit(1280), isTrue);
  });

  testWidgets('a phone shows only the list, set up to push', (tester) async {
    await pumpAt(tester, const Size(400, 800));

    expect(find.text('list (push)'), findsOneWidget);
    expect(find.textContaining('chat '), findsNothing);
    expect(events, isEmpty);
    expect(widths['list'], 400);
  });

  testWidgets('a landscape tablet shows the list and opens no chat by itself', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1280, 800));

    expect(find.text('list (split)'), findsOneWidget);
    // Opening a chat marks it read, so nothing opens until a tap.
    expect(find.text('Select a conversation'), findsOneWidget);
    expect(find.textContaining('chat '), findsNothing);
    expect(events, isEmpty);
    expect(widths['list'], kMessagesListWidth);
  });

  testWidgets('tapping a thread opens it beside the list, sized to its pane', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1280, 800));
    await tester.tap(find.text('tile therapist'));
    await tester.pump();

    expect(find.text('chat therapist'), findsOneWidget);
    expect(find.text('Select a conversation'), findsNothing);
    expect(events, ['open therapist']);
    // Each pane measures itself, so readable padding centres in the pane.
    expect(widths['detail'], 1280 - kMessagesListWidth - 1);
    expect(tester.getSize(find.byType(_FakeChat)).width, widths['detail']);
    // Still one page: nothing was pushed.
    expect(find.text('list (split)'), findsOneWidget);
  });

  testWidgets('tapping another thread switches the pane and disposes the old chat', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1280, 800));
    await tester.tap(find.text('tile therapist'));
    await tester.pump();
    await tester.tap(find.text('tile clinic'));
    await tester.pump();

    expect(find.text('chat clinic'), findsOneWidget);
    expect(find.text('chat therapist'), findsNothing);
    // Flutter mounts the new chat before finalising the old one's dispose,
    // so only the set matters here.
    expect(
      events,
      unorderedEquals(['open therapist', 'close therapist', 'open clinic']),
    );
  });

  testWidgets('rotating to portrait closes the pane and shows the list', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1280, 800));
    await tester.tap(find.text('tile therapist'));
    await tester.pump();
    tester.view.physicalSize = const Size(800, 1280);
    await tester.pump();

    expect(find.text('list (push)'), findsOneWidget);
    expect(find.textContaining('chat '), findsNothing);
    expect(events, ['open therapist', 'close therapist']);
  });
}
