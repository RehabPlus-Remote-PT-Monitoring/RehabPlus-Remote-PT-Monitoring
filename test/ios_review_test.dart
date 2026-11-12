// Tests for the review-and-harden pass over the iPhone-branch files:
// paging races in ChatPager, the confirm fallback after the screen closed,
// the native segmented control's index guard, the share sheet's double
// tap, the cached "why red" sentences, the gauge's NaN guard, and the
// refresh-rate-aware frame budget.

import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/diagnostic_logger.dart';
import 'package:rehabplus/core/frame_stats.dart';
import 'package:rehabplus/ios/app_controls.dart';
import 'package:rehabplus/ios/ios_chrome.dart';
import 'package:rehabplus/models/chat.dart';
import 'package:rehabplus/models/session.dart';
import 'package:rehabplus/services/chat_pager.dart';
import 'package:rehabplus/services/exercise_feedback.dart';
import 'package:rehabplus/services/form_checker.dart';
import 'package:rehabplus/widgets/chat_session_share_sheet.dart';

ChatMessage _msg(String id, DateTime sentAt) =>
    ChatMessage(id: id, text: id, fromPatient: false, sentAt: sentAt);

/// Messages m0 (oldest) .. m{count-1}, newest first, one minute apart.
List<ChatMessage> _conversation(int count) {
  final base = DateTime(2026, 11, 1, 9);
  return [
    for (var i = count - 1; i >= 0; i--)
      _msg('m$i', base.add(Duration(minutes: i))),
  ];
}

bool _logged(String message) =>
    DiagnosticLogger.I.recent(limit: 200).any((e) => e.message == message);

void main() {
  setUp(DiagnosticLogger.I.clearBuffer);
  tearDown(() => debugUseIosChromeOverride = null);

  group('ChatPager', () {
    test('a short cached snapshot does not stop paging once the full '
        'server snapshot arrives', () {
      final all = _conversation(10);
      final pager = ChatPager(loadPage: (_, _) async => [], liveLimit: 4);
      // Firestore's first snapshot can come from the phone's cache with
      // fewer messages than the limit...
      pager.merge(all.take(2).toList());
      expect(pager.reachedStart, isTrue);
      // ...and the server's full window a moment later.
      pager.merge(all.take(4).toList());
      expect(pager.reachedStart, isFalse);
      expect(pager.canLoadMore, isTrue);
    });

    test('paging to the start stays reached whatever the live window does',
        () async {
      final all = _conversation(5);
      final pager = ChatPager(
        loadPage: (_, _) async => [all.last],
        liveLimit: 4,
        pageSize: 4,
      );
      pager.merge(all.take(4).toList());
      await pager.loadOlder();
      expect(pager.reachedStart, isTrue);
      pager.merge(all.take(4).toList());
      expect(pager.reachedStart, isTrue);
    });

    test('after a failure, retries wait for retryDelay', () async {
      var now = DateTime(2026, 11, 1, 12);
      var calls = 0;
      final pager = ChatPager(
        loadPage: (_, _) async {
          calls++;
          throw StateError('offline');
        },
        liveLimit: 2,
        pageSize: 2,
        retryDelay: const Duration(seconds: 3),
        clock: () => now,
      );
      pager.merge(_conversation(4).take(2).toList());

      await pager.loadOlder();
      expect(calls, 1);
      expect(pager.lastLoadFailed, isTrue);

      // A fling sends many scroll notifications; none may re-send at once.
      now = now.add(const Duration(seconds: 1));
      expect(pager.canLoadMore, isFalse);
      await pager.loadOlder();
      expect(calls, 1);

      now = now.add(const Duration(seconds: 2));
      expect(pager.canLoadMore, isTrue);
      await pager.loadOlder();
      expect(calls, 2);
      expect(_logged('Loading older messages failed'), isTrue);
    });

    test('merge reuses its result for the same snapshot and refreshes after '
        'a page adds messages', () async {
      final all = _conversation(8);
      final pager = ChatPager(
        loadPage: (before, limit) async => all
            .where((m) => !m.sentAt.isAfter(before))
            .take(limit)
            .toList(),
        liveLimit: 3,
        pageSize: 3,
      );
      final live = all.take(3).toList();
      final first = pager.merge(live);
      expect(identical(pager.merge(live), first), isTrue);

      await pager.loadOlder();
      final second = pager.merge(live);
      expect(identical(second, first), isFalse);
      expect(second.map((m) => m.id), ['m7', 'm6', 'm5', 'm4', 'm3']);
      // A new snapshot list (even with equal content) is merged afresh.
      expect(identical(pager.merge(List.of(live)), second), isFalse);
    });

    test('a page arriving after dispose is dropped without notifying',
        () async {
      final all = _conversation(6);
      final page = Completer<List<ChatMessage>>();
      final pager = ChatPager(
        loadPage: (_, _) => page.future,
        liveLimit: 2,
        pageSize: 2,
      );
      pager.merge(all.take(2).toList());
      final load = pager.loadOlder();
      pager.dispose(); // the patient closed the chat mid-load
      page.complete(all.skip(2).take(2).toList());
      await load; // must not throw "used after being disposed"
      expect(pager.canLoadMore, isFalse);
      expect(pager.loadedOlder, isFalse);
    });
  });

  group('confirmWithFallback', () {
    test('does not open the fallback once the screen is gone', () async {
      var materialShown = false;
      final answer = await confirmWithFallback(
        native: () async => null,
        material: () async {
          materialShown = true;
          return true;
        },
        canFallBack: () => false,
        title: 'Decline and sign out?',
      );
      expect(answer, isFalse);
      expect(materialShown, isFalse);
      expect(_logged('Screen closed before the fallback dialog'), isTrue);
    });

    test('logs a native answer', () async {
      final answer = await confirmWithFallback(
        native: () async => true,
        material: () async => false,
        title: 'Forgot your PIN?',
      );
      expect(answer, isTrue);
      expect(_logged('Native alert answered'), isTrue);
    });
  });

  testWidgets('AppSegmented ignores an out-of-range native index', (
    tester,
  ) async {
    debugUseIosChromeOverride = true;
    final got = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSegmented<int>(
            segments: const [(7, '7 days'), (30, '30 days')],
            selected: 99, // not a segment: falls back to the first
            onChanged: got.add,
            material: () => const SizedBox(),
          ),
        ),
      ),
    );
    final cn = tester.widget<CNSegmentedControl>(
      find.byType(CNSegmentedControl),
    );
    expect(cn.selectedIndex, 0);
    expect(_logged('Segmented value not in segments'), isTrue);
    cn.onValueChanged(5);
    cn.onValueChanged(-1);
    expect(got, isEmpty);
    expect(_logged('Segment index out of range'), isTrue);
    cn.onValueChanged(1);
    expect(got, [30]);
  });

  testWidgets('a double tap in the share sheet does not close the chat', (
    tester,
  ) async {
    final sessions = [
      ExerciseSession(
        id: 's0',
        exerciseId: 'e0',
        exerciseName: 'Exercise 0',
        startTime: DateTime(2026, 11, 7, 8),
        targetReps: 10,
        targetSets: 1,
      ),
    ];
    ExerciseSession? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showChatSessionShareSheet(context, sessions);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final tile = find.text('Exercise 0');
    final tileWidget = tester.widget<ListTile>(
      find.ancestor(of: tile, matching: find.byType(ListTile)),
    );
    // Two taps in the same frame, before the sheet's exit animation can
    // block input.
    tileWidget.onTap!();
    tileWidget.onTap!();
    await tester.pumpAndSettle();

    expect(picked?.id, 's0');
    // The page that opened the sheet is still there.
    expect(find.text('open'), findsOneWidget);
    expect(_logged('Repeated share tap ignored'), isTrue);
  });

  group('whyRedSummary', () {
    test('keeps order, drops repeats, and caps the reasons', () {
      final summary = whyRedSummary([
        FormIssueCode.tooFast,
        FormIssueCode.tooFast,
        FormIssueCode.armBent,
        FormIssueCode.kneesIn,
      ]);
      expect(
        summary,
        '${formIssueExplanation(FormIssueCode.tooFast)} '
        '${formIssueExplanation(FormIssueCode.armBent)}',
      );
      expect(
        whyRedSummary(
          [FormIssueCode.kneesIn, FormIssueCode.armBent, FormIssueCode.tooFast],
          maxReasons: 3,
        ),
        [
          FormIssueCode.kneesIn,
          FormIssueCode.armBent,
          FormIssueCode.tooFast,
        ].map(formIssueExplanation).join(' '),
      );
    });

    test('every code at once (largest cache key) round-trips', () {
      expect(
        whyRedSummary(
          FormIssueCode.values.reversed,
          maxReasons: FormIssueCode.values.length,
        ),
        FormIssueCode.values.reversed.map(formIssueExplanation).join(' '),
      );
    });

    test('the same issues reuse one string (no per-frame join)', () {
      final a = whyRedSummary([FormIssueCode.bodySway]);
      final b = whyRedSummary([FormIssueCode.bodySway]);
      expect(identical(a, b), isTrue);
      // Order matters: a different first issue is a different sentence.
      expect(
        whyRedSummary([FormIssueCode.armBent, FormIssueCode.bodySway]),
        isNot(whyRedSummary([FormIssueCode.bodySway, FormIssueCode.armBent])),
      );
    });

    test('nothing to say for no issues or no room', () {
      expect(whyRedSummary(const []), isNull);
      expect(whyRedSummary([FormIssueCode.armBent], maxReasons: 0), isNull);
    });
  });

  test('the range gauge shows no marker for a non-finite range', () {
    expect(
      const RangeGaugeScale(restAngle: double.nan, targetAngle: 90).position(45),
      isNull,
    );
    expect(
      const RangeGaugeScale(
        restAngle: 0,
        targetAngle: double.infinity,
      ).position(45),
      isNull,
    );
  });

  group('frame budget', () {
    test('follows the refresh rate, 60 Hz when it is unknown', () {
      expect(frameBudgetMs(60), closeTo(16.67, 0.01));
      expect(frameBudgetMs(120), closeTo(8.33, 0.01));
      expect(frameBudgetMs(0), closeTo(16.67, 0.01));
      expect(frameBudgetMs(double.nan), closeTo(16.67, 0.01));
      expect(frameBudgetMs(1000), closeTo(16.67, 0.01));
    });

    test('the window summary reports the budget it judged against', () {
      final w = FrameStatsWindow(budgetMs: 1000 / 120)
        ..add(buildMs: 10, rasterMs: 2);
      final s = w.takeSummary()!;
      expect(s['budgetMs'], 8.3);
      expect(s['janky'], 1);
    });

    testWidgets('a named route keeps its name as the screen', (tester) async {
      final observer = FrameStatsRouteObserver();
      await tester.pumpWidget(
        MaterialApp(navigatorObservers: [observer], home: const SizedBox()),
      );
      final named = MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/profile'),
        builder: (_) => const Placeholder(),
      );
      final unnamed = MaterialPageRoute<void>(
        builder: (_) => const Placeholder(),
      );
      expect(observer.screenNameFor(named), '/profile');
      expect(observer.screenNameFor(unnamed), 'Placeholder');
      expect(observer.screenNameFor(null), isNull);
    });
  });
}
