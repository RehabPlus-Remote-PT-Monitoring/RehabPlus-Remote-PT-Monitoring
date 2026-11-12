// Tests for the second review pass over the stats/report code and the
// data-heavy screens: bugs fixed and pure logic that was restructured.
//
// The daylight-saving cases only bite in a zone with DST; run also with
// `TZ=America/New_York flutter test test/stats_review_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:rehabplus/models/session.dart';
import 'package:rehabplus/screens/messages_screen.dart';
import 'package:rehabplus/screens/notification_page.dart';
import 'package:rehabplus/services/progress_report.dart';
import 'package:rehabplus/services/progress_stats.dart';

// Friday 16 Oct 2026, 3 pm (local).
final now = DateTime(2026, 10, 16, 15);

DateTime daysAgo(int d, [int hour = 9]) =>
    DateTime(now.year, now.month, now.day - d, hour);

ExerciseSession session(
  DateTime start, {
  String name = 'Knee Extension',
  List<double> scores = const [1, 1],
  int? pain,
}) => ExerciseSession(
  id: '${start.toIso8601String()}$name',
  exerciseId: name,
  exerciseName: name,
  startTime: start,
  endTime: start.add(const Duration(minutes: 10)),
  targetReps: 10,
  targetSets: 1,
  completedReps: 10,
  repComplianceScores: scores,
  painLevel: pain,
);

void main() {
  group('ProgressStats.overview', () {
    test('a repeated window length does not count sessions twice', () {
      // Bug: each window in the list was accumulated separately, but the
      // results were keyed by length, so [7, 7] doubled every total.
      final sessions = [session(daysAgo(0)), session(daysAgo(2))];
      final once = ProgressStats.overview(sessions, now, windows: const [7]);
      final twice = ProgressStats.overview(
        sessions,
        now,
        windows: const [7, 7],
      );
      expect(twice.periodFor(7).current.sessions, 2);
      expect(
        twice.periodFor(7).current.sessions,
        once.periodFor(7).current.sessions,
      );
      expect(
        twice.periodFor(7).current.time,
        once.periodFor(7).current.time,
      );
    });
  });

  group('ProgressReport.build reads each session score once', () {
    // The form score and pain are now computed once per session and shared
    // by the period average, the chart buckets and the per-exercise rows.
    // These pin the results so the restructuring can't change them.
    final sessions = [
      session(daysAgo(0), name: 'A', scores: [1, 0.5], pain: 2), // 75
      session(daysAgo(0, 18), name: 'B', scores: [double.nan], pain: 6),
      session(daysAgo(3), name: 'A', scores: [0.25], pain: null), // 25
      session(daysAgo(10), name: 'A', scores: [0.9], pain: 1), // previous
    ];
    final r = ProgressReport.build(sessions, now, days: 7);

    test('period averages', () {
      expect(r.sessions, 3);
      expect(r.formScore, 50); // (75 + 25) / 2; B has no usable score
      expect(r.pain, 4); // (2 + 6) / 2
      expect(r.previousFormScore, closeTo(90, 1e-9));
      expect(r.previousPain, 1);
    });

    test('chart buckets', () {
      final today = r.points.last;
      expect(today.sessions, 2);
      expect(today.formScore, 75);
      expect(today.pain, 4);
      final threeDaysAgo = r.points[r.points.length - 4];
      expect(threeDaysAgo.formScore, 25);
      expect(threeDaysAgo.pain, isNull);
    });

    test('per-exercise rows', () {
      final a = r.exercises.firstWhere((e) => e.name == 'A');
      expect(a.sessions, 2);
      expect(a.formScore, 50);
      expect(a.pain, 2);
      expect(a.lastDone, daysAgo(0));
      final b = r.exercises.firstWhere((e) => e.name == 'B');
      expect(b.formScore, isNull);
      expect(b.pain, 6);
    });
  });

  group('message and notification time labels', () {
    // Monday 9 Mar 2026, the day after the US spring-forward change: in
    // America/New_York, Sunday 8 Mar is only 23 hours long.
    final monday = DateTime(2026, 3, 9, 8);
    final sunday = DateTime(2026, 3, 8, 10);

    test('"Yesterday" across a daylight-saving change', () {
      // Bug: Duration.inDays of 23 hours is 0, so this showed "Sun".
      expect(threadTimeLabel(sunday, monday), 'Yesterday');
      expect(notificationTimeLabel(sunday, monday), 'Yesterday');
    });

    test('today, this week and older', () {
      final at = DateTime(2026, 10, 16, 15); // Friday
      final earlyToday = DateTime(2026, 10, 16, 0, 5);
      // intl puts a narrow no-break space before AM, so compare with it.
      expect(threadTimeLabel(earlyToday, at), DateFormat.jm().format(earlyToday));
      expect(threadTimeLabel(DateTime(2026, 10, 13, 9), at), 'Tue');
      expect(notificationTimeLabel(DateTime(2026, 10, 13, 9), at), 'Tuesday');
      expect(threadTimeLabel(DateTime(2026, 10, 9, 9), at), 'Oct 9');
      expect(notificationTimeLabel(DateTime(2026, 10, 9, 9), at), 'Oct 9');
    });

    test('just before midnight yesterday is "Yesterday", not today', () {
      final at = DateTime(2026, 10, 16, 0, 1);
      expect(threadTimeLabel(DateTime(2026, 10, 15, 23, 59), at), 'Yesterday');
    });
  });
}
