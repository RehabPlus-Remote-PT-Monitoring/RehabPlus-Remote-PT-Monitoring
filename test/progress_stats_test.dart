import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/models/session.dart';
import 'package:rehabplus/services/progress_stats.dart';

ExerciseSession _session(DateTime start, {int minutes = 10}) => ExerciseSession(
  id: start.toIso8601String(),
  exerciseId: 'kneeExtension',
  exerciseName: 'Knee Extension',
  startTime: start,
  endTime: start.add(Duration(minutes: minutes)),
  targetReps: 10,
  targetSets: 1,
);

void main() {
  // Friday 16 Oct 2026, 3 pm.
  final now = DateTime(2026, 10, 16, 15);

  // The week tracker and the stat cards come from ProgressStats.overview.
  group('overview week', () {
    test('marks days with a session, Monday first', () {
      final sessions = [
        _session(DateTime(2026, 10, 12, 8)), // Mon
        _session(DateTime(2026, 10, 12, 18)), // Mon again
        _session(DateTime(2026, 10, 15, 9)), // Thu
        _session(DateTime(2026, 10, 11, 9)), // previous Sunday: excluded
      ];
      expect(ProgressStats.overview(sessions, now).week, [
        true,
        false,
        false,
        true,
        false,
        false,
        false,
      ]);
    });

    test('is all false with no sessions', () {
      expect(ProgressStats.overview([], now).week, List.filled(7, false));
    });
  });

  group('overview periods', () {
    final sessions = [
      _session(DateTime(2026, 10, 16, 9), minutes: 12), // today
      _session(DateTime(2026, 10, 16, 14), minutes: 8), // today
      _session(DateTime(2026, 10, 10, 9), minutes: 15), // 6 days ago
      _session(
        DateTime(2026, 10, 9, 9),
        minutes: 20,
      ), // 7 days ago: previous week
      _session(
        DateTime(2026, 10, 3, 9),
        minutes: 5,
      ), // 13 days ago: previous week
    ];

    test('last 7 days includes today and the 6 days before', () {
      final p = ProgressStats.overview(sessions, now).periodFor(7).current;
      expect(p.sessions, 3);
      expect(p.activeDays, 2);
      expect(p.time, const Duration(minutes: 35));
    });

    test('previous 7 days for trends', () {
      final p = ProgressStats.overview(sessions, now).periodFor(7).previous;
      expect(p.sessions, 2);
      expect(p.activeDays, 2);
      expect(p.time, const Duration(minutes: 25));
    });

    test('ignores sessions with no end time', () {
      final open = ExerciseSession(
        id: 'x',
        exerciseId: 'kneeExtension',
        exerciseName: 'Knee Extension',
        startTime: DateTime(2026, 10, 16, 10),
        targetReps: 10,
        targetSets: 1,
      );
      final p = ProgressStats.overview([open], now).periodFor(7).current;
      expect(p.sessions, 1);
      expect(p.time, Duration.zero);
    });
  });

  group('checklist activity', () {
    final sessions = [
      _session(DateTime(2026, 10, 16, 9)), // today (Fri)
      _session(DateTime(2026, 10, 13, 9)), // Tue this week
      _session(DateTime(2026, 10, 9, 9)), // last week
      ExerciseSession(
        id: 'early',
        exerciseId: 'bicepCurl',
        exerciseName: 'Bicep Curl',
        startTime: DateTime(2026, 10, 16, 10),
        targetReps: 10,
        targetSets: 1,
        endedEarly: true,
      ),
    ];

    test('done today counts only completed sessions that day', () {
      final activity = ProgressStats.activity(sessions, now);
      expect(activity.isDoneToday('kneeExtension'), isTrue);
      expect(activity.isDoneToday('bicepCurl'), isFalse);
      // Wednesday 14 Oct had no session.
      expect(
        ProgressStats.activity(sessions, DateTime(2026, 10, 14, 12))
            .isDoneToday('kneeExtension'),
        isFalse,
      );
    });

    test('this week starts on Monday', () {
      final activity = ProgressStats.activity(sessions, now);
      expect(activity.weekCount('kneeExtension'), 2);
      expect(activity.weekCount('bicepCurl'), 0);
    });
  });

  test('formatDuration', () {
    expect(ProgressStats.formatDuration(const Duration(minutes: 42)), '42m');
    expect(ProgressStats.formatDuration(const Duration(minutes: 65)), '1h 5m');
    expect(ProgressStats.formatDuration(Duration.zero), '0m');
  });
}
