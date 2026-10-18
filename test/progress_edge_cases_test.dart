// Edge cases for the pure progress code (progress_stats.dart and
// progress_report.dart): empty input, bad stored values, future dates and
// day boundaries. Run also with `TZ=America/New_York flutter test` to
// exercise the daylight-saving cases for real (Linux reads TZ at start-up).

import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/models/prescription.dart';
import 'package:rehabplus/models/session.dart';
import 'package:rehabplus/services/progress_report.dart';
import 'package:rehabplus/services/progress_stats.dart';

// Friday 16 Oct 2026, 3 pm (local).
final now = DateTime(2026, 10, 16, 15);

ExerciseSession session(
  DateTime start, {
  String exerciseId = 'kneeExtension',
  String name = 'Knee Extension',
  Duration? length = const Duration(minutes: 10),
  DateTime? end,
  List<double> scores = const [1, 1],
  int? pain,
  int targetReps = 10,
  int completedReps = 10,
  bool endedEarly = false,
  String? prescriptionId,
}) => ExerciseSession(
  id: '${start.toIso8601String()}$name',
  exerciseId: exerciseId,
  exerciseName: name,
  startTime: start,
  endTime: end ?? (length == null ? null : start.add(length)),
  targetReps: targetReps,
  targetSets: 1,
  completedReps: completedReps,
  repComplianceScores: scores,
  painLevel: pain,
  endedEarly: endedEarly,
  prescriptionId: prescriptionId,
);

DateTime daysAgo(int d, [int hour = 9]) =>
    DateTime(now.year, now.month, now.day - d, hour);

void main() {
  group('empty input', () {
    test('report, overview, period and activity are all empty', () {
      final r = ProgressReport.build(const [], now, days: 90);
      expect(r.status, ProgressStatus.noData);
      expect(r.sessions, 0);
      expect(r.formScore, isNull);
      expect(r.pain, isNull);
      expect(r.repCompletion, isNull);
      expect(r.exercises, isEmpty);
      expect(r.points, hasLength(13));

      final o = ProgressStats.overview(const [], now);
      expect(o.week, List.filled(7, false));
      expect(o.periodFor(30).current.sessions, 0);
      // Unknown window: zeros, not a crash.
      expect(o.periodFor(12).previous.time, Duration.zero);

      expect(ProgressStats.period(const [], now, days: 7).sessions, 0);
      expect(ProgressStats.activity(const [], now).doneToday, isEmpty);
      expect(ProgressStats.countByExerciseSince(const [], now), isEmpty);
    });

    test('zero or negative period lengths do not throw', () {
      final r0 = ProgressReport.build([session(daysAgo(0))], now, days: 0);
      expect(r0.days, ProgressReport.minDays);
      expect(r0.sessions, 1); // today
      final rNeg = ProgressReport.build([session(daysAgo(0))], now, days: -5);
      expect(rNeg.days, ProgressReport.minDays);
      expect(
        ProgressStats.period([session(daysAgo(0))], now, days: 0),
        isA<PeriodStats>(),
      );
      expect(
        ProgressStats.period([session(daysAgo(0))], now, days: 0).sessions,
        0,
      );
    });
  });

  group('bad stored values', () {
    test('end before start counts no time', () {
      final s = session(
        daysAgo(0),
        end: daysAgo(0).subtract(const Duration(hours: 1)),
      );
      expect(s.countedDuration, Duration.zero);
      expect(ProgressReport.build([s], now, days: 7).time, Duration.zero);
      expect(ProgressStats.period([s], now, days: 7).time, Duration.zero);
      expect(ProgressStats.period([s], now, days: 7).sessions, 1);
    });

    test('missing end time counts no time', () {
      final s = session(daysAgo(0), length: null);
      expect(ProgressReport.build([s], now, days: 7).time, Duration.zero);
    });

    test('NaN and infinite rep scores are ignored, not propagated', () {
      final sessions = [
        session(daysAgo(0), scores: [double.nan, 1, double.infinity]),
        session(daysAgo(1), scores: [double.nan]), // no usable score
      ];
      final r = ProgressReport.build(sessions, now, days: 7);
      expect(r.formScore, 100);
      expect(r.formScore!.isFinite, isTrue);
      expect(r.points.where((p) => p.formScore != null), hasLength(1));
      expect(sessions[1].safeFormScore, isNull);
      expect(sessions[1].safeCompliance, 0);
      // The finding text must be built without throwing on round().
      expect(r.findings, isNotEmpty);
    });

    test('scores outside 0..1 and pain outside 0..10 are clamped', () {
      final r = ProgressReport.build(
        [
          session(daysAgo(0), scores: [5, -1], pain: 42),
        ],
        now,
        days: 7,
      );
      expect(r.formScore, 50); // (1 + 0) / 2
      expect(r.pain, 10);
      expect(r.status, ProgressStatus.needsAttention); // high pain
    });

    test('zero target reps gives no rep figure; negatives count as zero', () {
      final zero = ProgressReport.build(
        [session(daysAgo(0), targetReps: 0, completedReps: 5)],
        now,
        days: 7,
      );
      expect(zero.repCompletion, isNull);

      final negative = ProgressReport.build(
        [
          session(daysAgo(0), targetReps: 10, completedReps: -4),
          session(daysAgo(1), targetReps: -10, completedReps: 5),
        ],
        now,
        days: 7,
      );
      expect(negative.repCompletion, 0.5); // 5 done / 10 targeted
    });

    test(
      'bad prescription values never give negative or broken plan figures',
      () {
        final rxs = [
          Prescription(
            id: 'neg',
            exerciseType: 'kneeExtension',
            targetReps: 10,
            frequencyPerWeek: -3,
            assignedAt: daysAgo(10),
          ),
          Prescription(
            id: 'badDays',
            exerciseType: 'kneeExtension',
            targetReps: 10,
            frequencyPerWeek: 3,
            schedule: const PrescriptionSchedule(days: [0, 8, 99]),
            assignedAt: daysAgo(10),
          ),
          Prescription(
            id: 'future',
            exerciseType: 'kneeExtension',
            targetReps: 10,
            frequencyPerWeek: 7,
            assignedAt: now.add(const Duration(days: 3)),
          ),
        ];
        final r = ProgressReport.build(
          [session(daysAgo(1), prescriptionId: 'badDays')],
          now,
          days: 7,
          prescriptions: rxs,
        );
        // Only 'badDays' plans anything: its weekdays are all invalid, so it
        // falls back to 3 per week over the 6 finished days = 2.
        expect(r.plannedSessions, 2);
        expect(r.plannedDone, 1);
        expect(r.adherence, 0.5);
      },
    );
  });

  group('dates', () {
    test('future-dated sessions (wrong phone clock) are not counted', () {
      final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
      final nextYear = DateTime(now.year + 1, 1, 1);
      final sessions = [
        session(tomorrow),
        session(nextYear),
        session(daysAgo(0)),
      ];

      final r = ProgressReport.build(sessions, now, days: 7);
      expect(r.sessions, 1);
      expect(ProgressStats.period(sessions, now, days: 7).sessions, 1);
      expect(
        ProgressStats.overview(sessions, now).periodFor(7).current.sessions,
        1,
      );
      expect(ProgressStats.countByExerciseSince(sessions, daysAgo(7)), {
        'kneeExtension': 3,
      });
    });

    test('day boundaries: 23:59 yesterday vs 00:00 today', () {
      final lateYesterday = DateTime(now.year, now.month, now.day - 1, 23, 59);
      final midnight = DateTime(now.year, now.month, now.day);
      final r = ProgressReport.build(
        [session(lateYesterday), session(midnight)],
        now,
        days: 7,
      );
      expect(r.points.last.sessions, 1); // today
      expect(r.points[r.points.length - 2].sessions, 1); // yesterday
      expect(r.activeDays, 2);

      final activity = ProgressStats.activity([session(lateYesterday)], now);
      expect(activity.isDoneToday('kneeExtension'), isFalse);
    });

    test(
      'first and last day of the window are included, the day before is not',
      () {
        final sessions = [
          session(daysAgo(6, 0)), // first day of the 7-day window, midnight
          session(daysAgo(7, 23)), // the day before: previous period
        ];
        final r = ProgressReport.build(sessions, now, days: 7);
        expect(r.sessions, 1);
        expect(r.points.first.sessions, 1);
        final stats = ProgressStats.period(sessions, now, days: 7);
        final previous = ProgressStats.period(
          sessions,
          now,
          days: 7,
          periodsAgo: 1,
        );
        expect(stats.sessions, 1);
        expect(previous.sessions, 1);
      },
    );

    test('UTC times are placed on their local day', () {
      final localTime = daysAgo(2, 22);
      final asUtc = localTime.toUtc();
      final local = ProgressReport.build([session(localTime)], now, days: 7);
      final utc = ProgressReport.build([session(asUtc)], now, days: 7);
      expect(
        utc.points.map((p) => p.sessions).toList(),
        local.points.map((p) => p.sessions).toList(),
      );
      expect(
        ProgressStats.currentWeek([session(asUtc)], now),
        ProgressStats.currentWeek([session(localTime)], now),
      );
      // `now` given in UTC means the same local day.
      expect(
        ProgressReport.build(
          [session(localTime)],
          now.toUtc(),
          days: 7,
        ).sessions,
        1,
      );
    });

    test('daylight-saving change inside the window (US: 1 Nov 2026)', () {
      // In zones with DST, adding 24 h steps cross the change one hour off
      // midnight. The window must still be whole calendar days.
      final tuesday = DateTime(2026, 11, 3, 15);
      final sessions = [
        session(DateTime(2026, 10, 28, 0, 30)), // first day of 7-day window
        session(DateTime(2026, 11, 1, 23, 30)), // Sunday, after the change
        session(DateTime(2026, 11, 2, 0, 30)), // Monday just after midnight
      ];
      final r = ProgressReport.build(sessions, tuesday, days: 7);
      expect(r.sessions, 3);
      expect(r.points.first.start, DateTime(2026, 10, 28));
      expect(r.points.first.sessions, 1);
      expect(r.points[5].start, DateTime(2026, 11, 2));
      expect(r.points[5].sessions, 1);
      for (final p in r.points) {
        expect(p.start.hour, 0, reason: 'bucket starts at local midnight');
      }

      expect(ProgressStats.period(sessions, tuesday, days: 7).sessions, 3);
      // Week of Mon 2 Nov: Monday only; Sunday 1 Nov was last week.
      expect(ProgressStats.currentWeek(sessions, tuesday), [
        true,
        false,
        false,
        false,
        false,
        false,
        false,
      ]);
    });

    test('CalendarDays.between counts calendar days', () {
      expect(
        CalendarDays.between(
          DateTime(2026, 10, 31, 23),
          DateTime(2026, 11, 1, 1),
        ),
        1,
      );
      expect(
        CalendarDays.between(DateTime(2026, 11, 2), DateTime(2026, 10, 26)),
        -7,
      );
      expect(
        CalendarDays.addDays(DateTime(2026, 10, 31, 18), 2),
        DateTime(2026, 11, 2),
      );
    });
  });

  group('overview matches the single-window functions', () {
    test('for every window and both periods', () {
      final sessions = [
        for (var d = 0; d < 200; d += 3)
          session(daysAgo(d), length: Duration(minutes: d % 17)),
        session(daysAgo(0, 20)),
      ];
      final o = ProgressStats.overview(sessions, now);
      expect(o.week, ProgressStats.currentWeek(sessions, now));
      for (final w in [7, 30, 90]) {
        for (final ago in [0, 1]) {
          final expected = ProgressStats.period(
            sessions,
            now,
            days: w,
            periodsAgo: ago,
          );
          final got = ago == 0
              ? o.periodFor(w).current
              : o.periodFor(w).previous;
          expect(got.sessions, expected.sessions, reason: 'w=$w ago=$ago');
          expect(got.activeDays, expected.activeDays, reason: 'w=$w ago=$ago');
          expect(got.time, expected.time, reason: 'w=$w ago=$ago');
        }
      }
    });
  });

  group('activity', () {
    test('done today and this week per exercise, ended-early excluded', () {
      final sessions = [
        session(daysAgo(0), exerciseId: 'a'),
        session(daysAgo(0), exerciseId: 'b', endedEarly: true),
        session(daysAgo(2), exerciseId: 'b'), // Wed, this week
        session(daysAgo(5), exerciseId: 'a'), // Sun, last week
      ];
      final activity = ProgressStats.activity(sessions, now);
      expect(activity.doneToday, {'a'});
      expect(activity.weekCount('a'), 1);
      expect(activity.weekCount('b'), 1);
      expect(activity.weekCount('missing'), 0);
      expect(ProgressStats.completedThisWeek(sessions, 'a', now), 1);
      expect(ProgressStats.doneOn(sessions, 'b', now), isFalse);
    });
  });

  test('formatDuration never shows negative time', () {
    expect(ProgressStats.formatDuration(const Duration(minutes: -5)), '0m');
    expect(ProgressStats.formatDuration(const Duration(minutes: 65)), '1h 5m');
  });

  test('per-exercise ties are ordered by name, every time', () {
    final sessions = [
      session(daysAgo(1), name: 'Wall Sit'),
      session(daysAgo(2), name: 'Bicep Curl'),
    ];
    final r = ProgressReport.build(sessions, now, days: 7);
    expect(r.exercises.map((e) => e.name), ['Bicep Curl', 'Wall Sit']);
    expect(r.exercises.last.lastDone, daysAgo(1));
  });

  test('relevantSessions keeps exactly this period and the one before', () {
    final sessions = [
      session(daysAgo(0)),
      session(daysAgo(13)), // previous 7-day period
      session(daysAgo(14)), // older: not needed
      session(DateTime(now.year, now.month, now.day + 1)), // future
    ];
    final relevant = ProgressReport.relevantSessions(sessions, now, days: 7);
    expect(relevant, [sessions[0], sessions[1]]);
  });
}
