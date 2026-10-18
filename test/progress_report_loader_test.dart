// ProgressReportLoader: memoisation, the inline/background split, and
// dropping results that arrive too late (new data, a closed screen).
//
// Under `flutter test`, runInBackground runs the job inline but still
// asynchronously, so the background path is exercised here by setting a
// tiny backgroundThreshold.

import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/diagnostic_logger.dart';
import 'package:rehabplus/models/session.dart';
import 'package:rehabplus/services/progress_report.dart';
import 'package:rehabplus/services/progress_report_loader.dart';

final now = DateTime(2026, 10, 16, 15);

ExerciseSession session(int daysAgo, {int? pain}) {
  final start = DateTime(now.year, now.month, now.day - daysAgo, 9);
  return ExerciseSession(
    id: 'id$daysAgo-${pain ?? 'x'}',
    exerciseId: 'kneeExtension',
    exerciseName: 'Knee Extension',
    startTime: start,
    endTime: start.add(const Duration(minutes: 10)),
    targetReps: 10,
    targetSets: 1,
    completedReps: 10,
    repComplianceScores: const [1, 1],
    painLevel: pain,
  );
}

/// Lets the (inline, async) background job and its `.then` run.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  final logger = DiagnosticLogger.I;

  setUp(() {
    logger.setSink((_) {}); // keep test output quiet
    logger.minLevel = DiagnosticLevel.verbose;
    logger.clearBuffer();
  });

  tearDown(() => logger.minLevel = DiagnosticLevel.info);

  Iterable<DiagnosticEvent> events(String message) =>
      logger.recent(limit: 500).where((e) => e.message == message);

  group('inline (normal histories)', () {
    test('builds once per input change, not per call', () {
      var callbacks = 0;
      final loader = ProgressReportLoader(
        owner: 'test',
        onBackgroundResult: () => callbacks++,
      );
      final sessions = [session(0), session(1)];

      final first = loader.reportFor(sessions, days: 7, now: now);
      final second = loader.reportFor(sessions, days: 7, now: now);
      expect(first.report, isNotNull);
      expect(identical(first.report, second.report), isTrue);
      expect(first.isStale, isFalse);
      expect(events('Report built'), hasLength(1));

      // A new list (AppProvider replaces it on every load) rebuilds.
      final third = loader.reportFor(
        [...sessions, session(2)],
        days: 7,
        now: now,
      );
      expect(third.report!.sessions, 3);
      expect(events('Report built'), hasLength(2));

      // Each period is cached separately.
      final month = loader.reportFor([...sessions], days: 30, now: now);
      expect(month.report!.days, 30);

      expect(callbacks, 0, reason: 'inline builds need no callback');
    });

    test('a new day invalidates the cache', () {
      final loader = ProgressReportLoader(
        owner: 'test',
        onBackgroundResult: () {},
      );
      final sessions = [session(0)];
      final today = loader.reportFor(sessions, days: 7, now: now).report!;
      final tomorrow = loader
          .reportFor(sessions, days: 7, now: now.add(const Duration(days: 1)))
          .report!;
      expect(identical(today, tomorrow), isFalse);
      // Same day, later time: still cached.
      final later = loader
          .reportFor(
            sessions,
            days: 7,
            now: now.add(const Duration(days: 1, hours: 2)),
          )
          .report!;
      expect(identical(tomorrow, later), isTrue);
    });

    test('logs the build with verdict, counts and where it ran', () {
      final loader = ProgressReportLoader(
        owner: 'test',
        onBackgroundResult: () {},
      );
      loader.reportFor([session(0, pain: 8)], days: 7, now: now);
      final data = events('Report built').single.data!;
      expect(data['owner'], 'test');
      expect(data['days'], 7);
      expect(data['sessionsIn'], 1);
      expect(data['verdict'], ProgressStatus.needsAttention.name);
      expect(data['where'], 'inline');
      expect(data['ms'], isA<int>());
    });

    test('overview is memoised with the same inputs', () {
      final loader = ProgressReportLoader(
        owner: 'test',
        onBackgroundResult: () {},
      );
      final sessions = [session(0), session(8)];
      final a = loader.overviewFor(sessions, now: now);
      final b = loader.overviewFor(sessions, now: now);
      expect(identical(a, b), isTrue);
      expect(a.periodFor(7).current.sessions, 1);
      expect(a.periodFor(7).previous.sessions, 1);
    });
  });

  group('background (very long histories)', () {
    ProgressReportLoader loaderWith(void Function() onResult) =>
        ProgressReportLoader(
          owner: 'test',
          onBackgroundResult: onResult,
          backgroundThreshold: 1,
        );

    test('shows a loading state, then the result after the callback', () async {
      var callbacks = 0;
      final loader = loaderWith(() => callbacks++);
      final sessions = [session(0), session(1)];

      final before = loader.reportFor(sessions, days: 7, now: now);
      expect(before.report, isNull);
      expect(before.isLoading, isTrue);
      expect(loader.isComputing(7), isTrue);

      await settle();
      expect(callbacks, 1);
      final after = loader.reportFor(sessions, days: 7, now: now);
      expect(after.report!.sessions, 2);
      expect(after.isStale, isFalse);
      expect(events('Report built').single.data!['where'], 'background');
    });

    test(
      'keeps showing the last report (stale) while a new period builds',
      () async {
        final loader = loaderWith(() {});
        final sessions = [session(0), session(20)];
        loader.reportFor(sessions, days: 7, now: now);
        await settle();
        final week = loader.reportFor(sessions, days: 7, now: now).report!;

        final switching = loader.reportFor(sessions, days: 30, now: now);
        expect(identical(switching.report, week), isTrue);
        expect(switching.isStale, isTrue);

        await settle();
        final month = loader.reportFor(sessions, days: 30, now: now);
        expect(month.report!.days, 30);
        expect(month.report!.sessions, 2);
        expect(month.isStale, isFalse);
      },
    );

    test(
      'a result for a period the user left is cached for that period only',
      () async {
        final loader = loaderWith(() {});
        final sessions = [session(0), session(20)];
        loader.reportFor(sessions, days: 7, now: now); // starts the 7-day build
        loader.reportFor(sessions, days: 90, now: now); // user switches at once
        await settle();

        expect(loader.reportFor(sessions, days: 90, now: now).report!.days, 90);
        expect(loader.reportFor(sessions, days: 7, now: now).report!.days, 7);
      },
    );

    test('results for outdated inputs are discarded', () async {
      var callbacks = 0;
      final loader = loaderWith(() => callbacks++);
      loader.reportFor([session(0), session(1)], days: 7, now: now);
      // New data arrives before the first build finishes.
      final fresh = [session(0), session(1), session(2)];
      loader.reportFor(fresh, days: 7, now: now);
      await settle();

      expect(callbacks, 1, reason: 'only the current build notifies');
      expect(
        events('Report result discarded').single.data!['reason'],
        'inputs_changed',
      );
      expect(loader.reportFor(fresh, days: 7, now: now).report!.sessions, 3);
    });

    test('results that arrive after dispose are dropped', () async {
      var callbacks = 0;
      final loader = loaderWith(() => callbacks++);
      loader.reportFor([session(0), session(1)], days: 7, now: now);
      loader.dispose();
      await settle();
      expect(callbacks, 0);
      expect(
        events('Report result discarded').single.data!['reason'],
        'disposed',
      );
    });

    test('long histories outside the window stay inline', () {
      // Threshold 2: two sessions in total, but only one is in the window
      // the report reads, so it is built inline and returned at once.
      final loader = ProgressReportLoader(
        owner: 'test',
        onBackgroundResult: () {},
        backgroundThreshold: 2,
      );
      final view = loader.reportFor(
        [session(0), session(400)],
        days: 7,
        now: now,
      );
      expect(view.report!.sessions, 1);
      expect(loader.isComputing(7), isFalse);
    });
  });
}
