import '../models/session.dart';

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
}

/// Progress numbers for the dashboard, computed from the patient's saved
/// sessions. Pure functions so they can be unit-tested with a fixed [now].
class ProgressStats {
  ProgressStats._();

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  /// Whether the patient exercised on each day of the current week,
  /// Monday first (index 0 = Mon … 6 = Sun).
  static List<bool> currentWeek(List<ExerciseSession> sessions, DateTime now) {
    final monday = _day(now).subtract(Duration(days: now.weekday - 1));
    final active = sessions.map((s) => _day(s.startTime)).toSet();
    return List.generate(
      7,
      (i) => active.contains(monday.add(Duration(days: i))),
    );
  }

  /// Totals for the last [days] days including today, or — with
  /// [periodsAgo] = 1 — the [days] days before that (for trends).
  static PeriodStats period(
    List<ExerciseSession> sessions,
    DateTime now, {
    required int days,
    int periodsAgo = 0,
  }) {
    final end = _day(
      now,
    ).add(const Duration(days: 1)).subtract(Duration(days: days * periodsAgo));
    final start = end.subtract(Duration(days: days));

    final inWindow = sessions
        .where((s) => !s.startTime.isBefore(start) && s.startTime.isBefore(end))
        .toList();

    var time = Duration.zero;
    for (final s in inWindow) {
      final end = s.endTime;
      if (end != null && end.isAfter(s.startTime)) {
        time += end.difference(s.startTime);
      }
    }

    return PeriodStats(
      activeDays: inWindow.map((s) => _day(s.startTime)).toSet().length,
      sessions: inWindow.length,
      time: time,
    );
  }

  /// Whether [exerciseId] was fully completed (not ended early) on [day].
  static bool doneOn(
    List<ExerciseSession> sessions,
    String exerciseId,
    DateTime day,
  ) {
    final d = _day(day);
    return sessions.any(
      (s) =>
          s.exerciseId == exerciseId && !s.endedEarly && _day(s.startTime) == d,
    );
  }

  /// Completed sessions of [exerciseId] in the current Monday–Sunday week.
  static int completedThisWeek(
    List<ExerciseSession> sessions,
    String exerciseId,
    DateTime now,
  ) {
    final monday = _day(now).subtract(Duration(days: now.weekday - 1));
    return sessions
        .where(
          (s) =>
              s.exerciseId == exerciseId &&
              !s.endedEarly &&
              !s.startTime.isBefore(monday),
        )
        .length;
  }

  /// "42m", "1h 5m", "0m".
  static String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
