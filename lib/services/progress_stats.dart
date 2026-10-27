// lib/services/progress_stats.dart
//
// Progress numbers for the Home dashboard, the Exercise page and the
// "Today's plan" sheet, computed from the patient's saved sessions.
//
// Everything here is a pure function of (sessions, now): no Flutter, no
// Firebase, no clock reads. That keeps it unit-testable with a fixed `now`
// and lets it run on a background isolate (see progress_report_loader.dart).
//
// Robustness rules shared by all progress code
// --------------------------------------------
//   - "Days" are calendar days in the phone's local time zone. Times are
//     converted with toLocal() first, so a UTC DateTime (e.g. parsed from an
//     ISO string ending in "Z") lands on the right local day.
//   - Day arithmetic uses calendar fields (DateTime(y, m, d + n)), never
//     `Duration(days: n)`: across a daylight-saving change a "day" is 23 or
//     25 hours, and adding 24 h lands on the wrong side of midnight.
//   - Bad stored values never crash a screen: sessions whose end is before
//     their start count zero time, non-finite (NaN/infinite) rep scores are
//     ignored, scores and pain are clamped to their valid ranges, and
//     negative rep counts are treated as zero.
//
// Performance note: constructing a local DateTime needs a time-zone lookup
// and is by far the most expensive step per session, so the loops below
// compare instants against precomputed window boundaries and use integer
// day keys instead of building a DateTime per session.

import 'dart:math';

import 'package:collection/collection.dart';

import '../models/session.dart';

/// Calendar-day helpers (local time, daylight-saving safe).
class CalendarDays {
  CalendarDays._();

  /// Local midnight at the start of [t]'s day.
  static DateTime startOf(DateTime t) {
    final local = t.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// Local midnight [days] calendar days after [day] (negative = before).
  static DateTime addDays(DateTime day, int days) {
    final local = day.toLocal();
    return DateTime(local.year, local.month, local.day + days);
  }

  /// Whole calendar days from [from]'s day to [to]'s day (negative when [to]
  /// is earlier). Counted on UTC copies of the local dates, so a 23- or
  /// 25-hour daylight-saving day still counts as exactly one day.
  static int between(DateTime from, DateTime to) {
    final a = from.toLocal();
    final b = to.toLocal();
    return DateTime.utc(
      b.year,
      b.month,
      b.day,
    ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  }
}

/// Sanitised views of a session's stored values. Old app versions, manual
/// edits in the console or clock problems can leave odd values in Firestore;
/// the progress code reads them only through these getters.
extension ProgressSessionValues on ExerciseSession {
  /// Time spent, or zero when the end is missing or not after the start.
  Duration get countedDuration {
    final end = endTime;
    if (end == null || !end.isAfter(startTime)) return Duration.zero;
    return end.difference(startTime);
  }

  /// Average rep score as 0–100, or null when the session has no usable
  /// scores. Non-finite scores are skipped; each score is clamped to 0–1.
  double? get safeFormScore {
    var sum = 0.0;
    var count = 0;
    for (final score in repComplianceScores) {
      if (!score.isFinite) continue;
      sum += score.clamp(0.0, 1.0);
      count++;
    }
    return count == 0 ? null : sum / count * 100;
  }

  /// Like [ExerciseSession.overallCompliance] (0–1, 0 when there are no
  /// scores) but never NaN, so it is safe to round or to draw.
  double get safeCompliance => (safeFormScore ?? 0) / 100;

  /// Reported pain clamped to 0–10, or null when none was reported.
  double? get safePain => painLevel?.clamp(0, 10).toDouble();

  int get safeTargetReps => max(0, targetReps);
  int get safeCompletedReps => max(0, completedReps);
}

/// Totals for one time window.
class PeriodStats {
  final int activeDays;
  final int sessions;
  final Duration time;

  const PeriodStats({
    required this.activeDays,
    required this.sessions,
    required this.time,
  });

  static const empty = PeriodStats(
    activeDays: 0,
    sessions: 0,
    time: Duration.zero,
  );
}

/// One window on the dashboard (e.g. "last 30 days") and the window of the
/// same length just before it, for the trend badges.
class PeriodComparison {
  const PeriodComparison({required this.current, required this.previous});

  final PeriodStats current;
  final PeriodStats previous;
}

/// Everything the Home dashboard's progress card and stat cards show, from
/// one pass over the sessions. Computed once per change of the session list
/// (or of the day), not on every rebuild.
class ProgressOverview {
  const ProgressOverview({required this.week, required this.periods});

  /// Exercised on each day of the current week, Monday first.
  final List<bool> week;

  /// Window length in days → this window vs the previous one.
  final Map<int, PeriodComparison> periods;

  PeriodComparison periodFor(int days) =>
      periods[days] ??
      const PeriodComparison(
        current: PeriodStats.empty,
        previous: PeriodStats.empty,
      );
}

/// Per-exercise activity for the "Today's plan" sheet and its badge.
class ExerciseActivity {
  const ExerciseActivity({
    required this.doneToday,
    required this.completedThisWeek,
  });

  /// Exercise ids fully completed (not ended early) today.
  final Set<String> doneToday;

  /// Exercise id → fully completed sessions this Monday–Sunday week.
  final Map<String, int> completedThisWeek;

  bool isDoneToday(String exerciseId) => doneToday.contains(exerciseId);
  int weekCount(String exerciseId) => completedThisWeek[exerciseId] ?? 0;
}

/// Progress numbers for the dashboard, computed from the patient's saved
/// sessions. Pure functions so they can be unit-tested with a fixed [now].
class ProgressStats {
  ProgressStats._();

  /// Monday (local midnight) of [now]'s week.
  static DateTime _mondayOf(DateTime now) {
    final today = CalendarDays.startOf(now);
    return CalendarDays.addDays(today, -(today.weekday - 1));
  }

  /// Whether the patient exercised on each day of the current week,
  /// Monday first (index 0 = Mon … 6 = Sun).
  static List<bool> currentWeek(List<ExerciseSession> sessions, DateTime now) {
    final monday = _mondayOf(now);
    final nextMonday = CalendarDays.addDays(monday, 7);
    final week = List<bool>.filled(7, false);
    for (final s in sessions) {
      final t = s.startTime;
      if (t.isBefore(monday) || !t.isBefore(nextMonday)) continue;
      week[CalendarDays.between(monday, t)] = true;
    }
    return week;
  }

  /// Totals for the last [days] days including today, or — with
  /// [periodsAgo] = 1 — the [days] days before that (for trends).
  /// [days] below 1 gives empty totals.
  static PeriodStats period(
    List<ExerciseSession> sessions,
    DateTime now, {
    required int days,
    int periodsAgo = 0,
  }) {
    if (days < 1 || periodsAgo < 0) return PeriodStats.empty;
    final tomorrow = CalendarDays.addDays(CalendarDays.startOf(now), 1);
    final end = CalendarDays.addDays(tomorrow, -days * periodsAgo);
    final start = CalendarDays.addDays(end, -days);

    var count = 0;
    var time = Duration.zero;
    final activeDays = <int>{};
    for (final s in sessions) {
      final t = s.startTime;
      if (t.isBefore(start) || !t.isBefore(end)) continue;
      count++;
      time += s.countedDuration;
      activeDays.add(CalendarDays.between(start, t));
    }
    return PeriodStats(
      activeDays: activeDays.length,
      sessions: count,
      time: time,
    );
  }

  /// The current week plus, for each length in [windows], that window and
  /// the one before it, in a single pass over [sessions].
  static ProgressOverview overview(
    List<ExerciseSession> sessions,
    DateTime now, {
    List<int> windows = const [7, 30, 90],
  }) {
    final today = CalendarDays.startOf(now);
    final tomorrow = CalendarDays.addDays(today, 1);
    final monday = _mondayOf(now);
    final valid = [
      for (final w in windows)
        if (w >= 1) w,
    ];
    final longest = valid.maxOrNull ?? 0;
    // Oldest instant any window looks at (two back-to-back windows).
    final oldest = CalendarDays.addDays(tomorrow, -2 * longest);
    final earliest = oldest.isBefore(monday) ? oldest : monday;

    final week = List<bool>.filled(7, false);
    // Per window: [current, previous] accumulators.
    final counts = {for (final w in valid) w: List<int>.filled(2, 0)};
    final times = {for (final w in valid) w: List.filled(2, Duration.zero)};
    final active = {
      for (final w in valid) w: [<int>{}, <int>{}],
    };

    for (final s in sessions) {
      final t = s.startTime;
      // Cheap instant comparisons first: most of a long history is older
      // than every window, and future-dated sessions (a wrong phone clock)
      // belong to no window.
      if (t.isBefore(earliest) || !t.isBefore(tomorrow)) continue;

      // 0 = today, 1 = yesterday, ...
      final daysAgo = CalendarDays.between(t, today);
      final weekIndex = CalendarDays.between(monday, t);
      if (weekIndex >= 0 && weekIndex < 7) week[weekIndex] = true;

      final duration = s.countedDuration;
      for (final w in valid) {
        final slot = daysAgo ~/ w; // 0 = this window, 1 = previous one
        if (slot > 1) continue;
        counts[w]![slot]++;
        times[w]![slot] += duration;
        active[w]![slot].add(daysAgo);
      }
    }

    PeriodStats statsFor(int w, int slot) => PeriodStats(
      activeDays: active[w]![slot].length,
      sessions: counts[w]![slot],
      time: times[w]![slot],
    );

    return ProgressOverview(
      week: week,
      periods: {
        for (final w in valid)
          w: PeriodComparison(
            current: statsFor(w, 0),
            previous: statsFor(w, 1),
          ),
      },
    );
  }

  /// Whether [exerciseId] was fully completed (not ended early) on [day].
  static bool doneOn(
    List<ExerciseSession> sessions,
    String exerciseId,
    DateTime day,
  ) {
    final start = CalendarDays.startOf(day);
    final end = CalendarDays.addDays(start, 1);
    return sessions.any(
      (s) =>
          s.exerciseId == exerciseId &&
          !s.endedEarly &&
          !s.startTime.isBefore(start) &&
          s.startTime.isBefore(end),
    );
  }

  /// Completed sessions of [exerciseId] in the current Monday–Sunday week.
  static int completedThisWeek(
    List<ExerciseSession> sessions,
    String exerciseId,
    DateTime now,
  ) => activity(sessions, now).weekCount(exerciseId);

  /// [doneOn] (today) and [completedThisWeek] for every exercise at once,
  /// in one pass, so a list of N exercises costs O(sessions) not
  /// O(N × sessions).
  static ExerciseActivity activity(
    List<ExerciseSession> sessions,
    DateTime now,
  ) {
    final today = CalendarDays.startOf(now);
    final tomorrow = CalendarDays.addDays(today, 1);
    final monday = _mondayOf(now);
    final nextMonday = CalendarDays.addDays(monday, 7);

    final doneToday = <String>{};
    final week = <String, int>{};
    for (final s in sessions) {
      if (s.endedEarly) continue;
      final t = s.startTime;
      if (!t.isBefore(today) && t.isBefore(tomorrow)) {
        doneToday.add(s.exerciseId);
      }
      if (!t.isBefore(monday) && t.isBefore(nextMonday)) {
        week[s.exerciseId] = (week[s.exerciseId] ?? 0) + 1;
      }
    }
    return ExerciseActivity(doneToday: doneToday, completedThisWeek: week);
  }

  /// Exercise id → sessions (any outcome) started after [since]. Used for
  /// the rolling "last 7 days" bars on the Exercise page.
  static Map<String, int> countByExerciseSince(
    List<ExerciseSession> sessions,
    DateTime since,
  ) {
    final counts = <String, int>{};
    for (final s in sessions) {
      if (!s.startTime.isAfter(since)) continue;
      counts[s.exerciseId] = (counts[s.exerciseId] ?? 0) + 1;
    }
    return counts;
  }

  /// "42m", "1h 5m", "0m". Negative durations show as "0m".
  static String formatDuration(Duration d) {
    if (d.isNegative) return '0m';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
