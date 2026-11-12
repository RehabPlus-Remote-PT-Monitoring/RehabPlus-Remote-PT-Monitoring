// Messaging screen features that are pure logic (no Firebase): day
// separators, the "New messages" divider, sharing a session as text, and
// paging older messages in below the live window.

import 'package:cupertino_native_better/cupertino_native_better.dart'
    show LiquidGlassContainer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/app_palette.dart';
import 'package:rehabplus/ios/ios_chrome.dart';
import 'package:rehabplus/models/chat.dart';
import 'package:rehabplus/models/session.dart';
import 'package:rehabplus/services/chat_pager.dart';
import 'package:rehabplus/services/chat_session_share.dart';
import 'package:rehabplus/services/chat_timeline.dart';
import 'package:rehabplus/widgets/chat_composer_surface.dart';
import 'package:rehabplus/widgets/chat_session_share_sheet.dart';
import 'package:rehabplus/widgets/chat_timeline_widgets.dart';

ChatMessage _msg(
  String id,
  DateTime sentAt, {
  bool mine = false,
  bool pending = false,
}) => ChatMessage(
  id: id,
  text: id,
  fromPatient: mine,
  sentAt: sentAt,
  pending: pending,
);

void main() {
  group('chatDayLabel', () {
    // A Monday afternoon.
    final now = DateTime(2026, 11, 9, 15, 30);

    test('today and yesterday by calendar day, not 24 hours', () {
      expect(chatDayLabel(DateTime(2026, 11, 9, 0, 1), now), 'Today');
      expect(chatDayLabel(DateTime(2026, 11, 9, 23, 59), now), 'Today');
      expect(chatDayLabel(DateTime(2026, 11, 8, 23, 59), now), 'Yesterday');
      expect(chatDayLabel(DateTime(2026, 11, 8, 0, 0), now), 'Yesterday');
    });

    test('the weekday for the rest of the past week', () {
      expect(chatDayLabel(DateTime(2026, 11, 7, 9), now), 'Saturday');
      expect(chatDayLabel(DateTime(2026, 11, 3, 9), now), 'Tuesday');
    });

    test('a date once it is a week or more ago', () {
      expect(chatDayLabel(DateTime(2026, 11, 2, 9), now), 'Nov 2');
      expect(chatDayLabel(DateTime(2026, 1, 15, 9), now), 'Jan 15');
    });

    test('the year for other years', () {
      expect(chatDayLabel(DateTime(2025, 11, 3, 9), now), 'Nov 3, 2025');
    });

    test('a phone clock slightly ahead (tomorrow) shows its date', () {
      expect(chatDayLabel(DateTime(2026, 11, 10, 0, 20), now), 'Nov 10');
    });

    test('yesterday works across a month and year boundary', () {
      final newYear = DateTime(2027, 1, 1, 8);
      expect(chatDayLabel(DateTime(2026, 12, 31, 22), newYear), 'Yesterday');
    });
  });

  group('startsNewDay', () {
    test('the oldest loaded message always starts a day', () {
      expect(startsNewDay(DateTime(2026, 11, 9, 8), null), isTrue);
    });

    test('only a different local calendar day starts a new one', () {
      expect(
        startsNewDay(
          DateTime(2026, 11, 9, 0, 5),
          DateTime(2026, 11, 8, 23, 55),
        ),
        isTrue,
      );
      expect(
        startsNewDay(DateTime(2026, 11, 9, 23, 0), DateTime(2026, 11, 9, 0, 1)),
        isFalse,
      );
    });
  });

  group('newMessagesDividerId', () {
    final t = DateTime(2026, 11, 9, 9);
    // Newest first, as the chat screen lists them.
    final msgs = [
      _msg('s3', t.add(const Duration(minutes: 5))),
      _msg('p2', t.add(const Duration(minutes: 4)), mine: true),
      _msg('s2', t.add(const Duration(minutes: 3))),
      _msg('s1', t.add(const Duration(minutes: 2))),
      _msg('p1', t.add(const Duration(minutes: 1)), mine: true),
    ];

    test('sits above the oldest of the newest N staff messages', () {
      expect(newMessagesDividerId(msgs, 1), 's3');
      expect(newMessagesDividerId(msgs, 2), 's2');
      expect(newMessagesDividerId(msgs, 3), 's1');
    });

    test('no divider when nothing was unread', () {
      expect(newMessagesDividerId(msgs, 0), isNull);
      expect(newMessagesDividerId(msgs, -1), isNull);
      expect(newMessagesDividerId(const [], 3), isNull);
    });

    test('more unread than loaded staff messages: above the oldest one', () {
      expect(newMessagesDividerId(msgs, 9), 's1');
    });

    test('no staff messages at all: no divider', () {
      expect(newMessagesDividerId([msgs[1], msgs[4]], 2), isNull);
    });
  });

  group('sessionShareText', () {
    ExerciseSession session({
      int completed = 10,
      int target = 10,
      List<double> scores = const [1, 1, 1, 0.68],
      int? pain = 2,
      String? painNote,
      bool endedEarly = false,
      String name = 'Knee Extension',
    }) => ExerciseSession(
      id: 'x',
      exerciseId: 'kneeExtension',
      exerciseName: name,
      startTime: DateTime(2026, 11, 7, 8, 15),
      targetReps: target,
      targetSets: 1,
      completedReps: completed,
      repComplianceScores: scores,
      painLevel: pain,
      painNote: painNote,
      endedEarly: endedEarly,
    );

    test('name, time, reps, accuracy and pain', () {
      expect(
        sessionShareText(session()),
        'Session summary - Knee Extension (Nov 7, 8:15 AM)\n'
        '10/10 reps, accuracy 92%, pain 2/10',
      );
    });

    test('ended early and the pain note are included', () {
      expect(
        sessionShareText(
          session(completed: 4, endedEarly: true, painNote: 'Sharp at the end'),
        ),
        'Session summary - Knee Extension (Nov 7, 8:15 AM)\n'
        '4/10 reps, accuracy 92%, pain 2/10 - ended early\n'
        'Pain note: Sharp at the end',
      );
    });

    test('missing accuracy and pain are left out, not shown as 0', () {
      expect(
        sessionShareText(session(scores: const [], pain: null)),
        'Session summary - Knee Extension (Nov 7, 8:15 AM)\n10/10 reps',
      );
    });

    test('a blank pain note is left out', () {
      expect(
        sessionShareText(session(painNote: '   ')),
        isNot(contains('note')),
      );
    });

    test('never longer than a message may be', () {
      final text = sessionShareText(
        session(name: 'N' * 100, painNote: 'x' * 5000),
      );
      expect(text.length, lessThanOrEqualTo(ChatMessage.maxTextLength));
      expect(text, startsWith('Session summary - N'));
    });
  });

  group('mergeMessages', () {
    final t = DateTime(2026, 11, 9, 9);

    test('dedupes by id and orders newest first', () {
      final live = [
        _msg('c', t.add(const Duration(minutes: 3))),
        _msg('b', t.add(const Duration(minutes: 2))),
      ];
      final older = [
        _msg('b', t.add(const Duration(minutes: 2))),
        _msg('a', t),
      ];
      expect(mergeMessages(live, older).map((m) => m.id), ['c', 'b', 'a']);
    });

    test('the live copy wins (it carries the current pending state)', () {
      final live = [_msg('a', t, pending: true)];
      final older = [_msg('a', t)];
      expect(mergeMessages(live, older).single.pending, isTrue);
    });

    test('equal times keep a stable order', () {
      final merged = mergeMessages([_msg('b', t)], [_msg('a', t)]);
      expect(merged.map((m) => m.id), ['b', 'a']);
      final again = mergeMessages([_msg('a', t)], [_msg('b', t)]);
      expect(again.map((m) => m.id), ['b', 'a']);
    });
  });

  group('ChatPager', () {
    final base = DateTime(2026, 11, 1, 9);
    // 10 messages, one a minute; m9 is the newest.
    final all = [
      for (var i = 9; i >= 0; i--) _msg('m$i', base.add(Duration(minutes: i))),
    ];

    /// A fake Firestore page: newest first, at or before [before] (like
    /// startAt on sentAt, so the boundary message comes back again).
    Future<List<ChatMessage>> Function(DateTime, int) loaderOver(
      List<ChatMessage> source,
      List<DateTime> calls,
    ) => (before, limit) async {
      calls.add(before);
      return source
          .where((m) => !m.sentAt.isAfter(before))
          .take(limit)
          .toList();
    };

    test('a live window smaller than its limit is the whole conversation', () {
      final pager = ChatPager(loadPage: (_, _) async => [], liveLimit: 5);
      pager.merge(all.take(3).toList());
      expect(pager.reachedStart, isTrue);
      expect(pager.canLoadMore, isFalse);
    });

    test('loads older pages below the live window, deduped by id', () async {
      final calls = <DateTime>[];
      final pager = ChatPager(
        loadPage: loaderOver(all, calls),
        liveLimit: 4,
        pageSize: 4,
      );
      expect(pager.merge(all.take(4).toList()).map((m) => m.id), [
        'm9',
        'm8',
        'm7',
        'm6',
      ]);
      expect(pager.reachedStart, isFalse);

      await pager.loadOlder();
      expect(calls.single, base.add(const Duration(minutes: 6)));
      expect(pager.merge(all.take(4).toList()).map((m) => m.id), [
        'm9',
        'm8',
        'm7',
        'm6',
        'm5',
        'm4',
        'm3',
      ]);
      expect(pager.reachedStart, isFalse);

      await pager.loadOlder();
      final merged = pager.merge(all.take(4).toList());
      expect(merged.map((m) => m.id), [for (var i = 9; i >= 0; i--) 'm$i']);
      // That page (m3..m0) was full; the next one is short.
      await pager.loadOlder();
      expect(pager.reachedStart, isTrue);
      expect(pager.loadedOlder, isTrue);
      expect(pager.merge(all.take(4).toList()).length, 10);
    });

    test(
      'a message pushed out of the live window by a new one stays',
      () async {
        final calls = <DateTime>[];
        final pager = ChatPager(
          loadPage: loaderOver(all, calls),
          liveLimit: 3,
          pageSize: 3,
        );
        pager.merge(all.sublist(1, 4)); // m8 m7 m6
        await pager.loadOlder(); // m6 m5 m4
        // m9 arrives; the live window now ends at m7, m6 still shows.
        final merged = pager.merge(all.sublist(0, 3));
        expect(merged.map((m) => m.id), ['m9', 'm8', 'm7', 'm6', 'm5', 'm4']);
      },
    );

    test('a pending message that disappears from live is not kept', () {
      final pager = ChatPager(loadPage: (_, _) async => [], liveLimit: 5);
      pager.merge([_msg('p', base, mine: true, pending: true)]);
      expect(pager.merge(const []), isEmpty);
    });

    test('only one load at a time', () async {
      var calls = 0;
      final pager = ChatPager(
        loadPage: (before, limit) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return [];
        },
        liveLimit: 2,
        pageSize: 2,
      );
      pager.merge(all.take(2).toList());
      final first = pager.loadOlder();
      expect(pager.loading, isTrue);
      await pager.loadOlder();
      await first;
      expect(calls, 1);
      expect(pager.loading, isFalse);
    });

    test('a failed load is reported and can be retried', () async {
      var fail = true;
      final pager = ChatPager(
        loadPage: (before, limit) async {
          if (fail) throw StateError('offline');
          return [];
        },
        liveLimit: 2,
        pageSize: 2,
        // The retry pause has its own test (ios_review_test.dart).
        retryDelay: Duration.zero,
      );
      pager.merge(all.take(2).toList());
      await pager.loadOlder();
      expect(pager.lastLoadFailed, isTrue);
      expect(pager.reachedStart, isFalse);
      expect(pager.loading, isFalse);

      fail = false;
      await pager.loadOlder();
      expect(pager.lastLoadFailed, isFalse);
      expect(pager.reachedStart, isTrue);
    });

    test(
      'a full page with nothing new stops paging instead of looping',
      () async {
        // Every message has the same sentAt (an import): startAt keeps
        // returning the ones already shown.
        final same = [for (var i = 0; i < 5; i++) _msg('s$i', base)];
        final pager = ChatPager(
          loadPage: (before, limit) async => same.take(limit).toList(),
          liveLimit: 2,
          pageSize: 2,
        );
        pager.merge(same.take(2).toList());
        await pager.loadOlder();
        expect(pager.reachedStart, isTrue);
      },
    );

    test('notifies listeners around a load', () async {
      final pager = ChatPager(loadPage: (_, _) async => [], liveLimit: 1);
      pager.merge(all.take(1).toList());
      var notified = 0;
      pager.addListener(() => notified++);
      await pager.loadOlder();
      expect(notified, 2); // started, finished
    });

    test('nothing to page from before the first snapshot', () async {
      var calls = 0;
      final pager = ChatPager(
        loadPage: (_, _) async {
          calls++;
          return [];
        },
        liveLimit: 1,
      );
      await pager.loadOlder();
      expect(calls, 0);
    });
  });

  group('chat widgets', () {
    tearDown(() => debugUseIosChromeOverride = null);

    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('history footer: spinner, start marker, failure, nothing', (
      tester,
    ) async {
      Widget footer({
        bool loading = false,
        bool start = false,
        bool failed = false,
      }) => host(
        ChatHistoryFooter(
          loading: loading,
          reachedStart: start,
          failed: failed,
        ),
      );

      await tester.pumpWidget(footer(loading: true));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(footer(start: true));
      expect(find.text('Beginning of conversation'), findsOneWidget);

      await tester.pumpWidget(footer(failed: true));
      expect(find.textContaining("Couldn't load older"), findsOneWidget);

      await tester.pumpWidget(footer());
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('composer on Android: the flat surfaceMuted bar, no glass', (
      tester,
    ) async {
      debugUseIosChromeOverride = false;
      await tester.pumpWidget(
        host(const ChatComposerSurface(child: Text('row'))),
      );
      final bar = tester.widget<Container>(
        find
            .ancestor(of: find.text('row'), matching: find.byType(Container))
            .first,
      );
      expect(bar.color, AppPalette.of(Brightness.light).surfaceMuted);
      expect(find.byType(LiquidGlassContainer), findsNothing);
    });

    testWidgets('composer on iPhone: a rounded bar (no native glass off iOS)', (
      tester,
    ) async {
      debugUseIosChromeOverride = true;
      await tester.pumpWidget(
        host(const ChatComposerSurface(child: Text('row'))),
      );
      final bar = tester.widget<Container>(
        find
            .ancestor(of: find.text('row'), matching: find.byType(Container))
            .first,
      );
      final decoration = bar.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(26));
      // The test host isn't iOS 26, so the translucent fallback is used.
      expect(find.byType(LiquidGlassContainer), findsNothing);
    });

    testWidgets('share sheet lists the 5 newest sessions and returns the tap', (
      tester,
    ) async {
      final sessions = [
        for (var i = 0; i < 7; i++)
          ExerciseSession(
            id: 's$i',
            exerciseId: 'e$i',
            exerciseName: 'Exercise $i',
            startTime: DateTime(2026, 11, 7 - i, 8),
            targetReps: 10,
            targetSets: 1,
          ),
      ];
      // Tall enough for all five rows (the sheet scrolls on short phones).
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      ExerciseSession? picked;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showChatSessionShareSheet(context, sessions);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Exercise 0'), findsOneWidget);
      expect(find.text('Exercise 4'), findsOneWidget);
      expect(find.text('Exercise 5'), findsNothing);

      await tester.tap(find.text('Exercise 2'));
      await tester.pumpAndSettle();
      expect(picked?.id, 's2');
    });

    testWidgets('share sheet with no sessions says so', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showChatSessionShareSheet(context, const []),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No sessions yet'), findsOneWidget);
    });
  });
}
