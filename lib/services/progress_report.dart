// lib/services/progress_report.dart
//
// "How am I doing?": the patient-facing progress report (verdict, findings,
// key numbers, chart points and a per-exercise breakdown).
//
// Pure Dart (no Flutter, no Firebase, no clock reads), so it is unit-tested
// with a fixed `now` and can run on a background isolate for long histories
// (see progress_report_loader.dart). Day handling and the sanitising of odd
// stored values follow the rules at the top of progress_stats.dart.

import 'dart:math';

import '../models/prescription.dart';
import '../models/session.dart';
import 'progress_stats.dart';

/// Overall verdict shown at the top of the progress report.
enum ProgressStatus {
  noData,
  needsAttention,
  onTrack,
  great;

  String get label => switch (this) {
    ProgressStatus.noData => 'No sessions yet',
    ProgressStatus.needsAttention => 'Needs attention',
    ProgressStatus.onTrack => 'On track',
    ProgressStatus.great => 'Doing great',
  };
}

enum FindingKind { good, info, warning }

/// One line of the report, e.g. "Form score up 8 points".
class Finding {
  const Finding(this.kind, this.text);
  final FindingKind kind;
  final String text;
}

/// One bar/point on the charts: a day (7-day view) or a group of days.
class ProgressPoint {
  const ProgressPoint({
    required this.start,
    required this.days,
    required this.sessions,
    this.formScore,
    this.pain,
  });

  final DateTime start;
  final int days;
  final int sessions;

  /// Average form score (0–100) of the sessions in this bucket, if any.
  final double? formScore;

  /// Average reported pain (0–10), if any session recorded it.
  final double? pain;
}

/// Totals for one exercise within the period.
class ExerciseSummary {
  const ExerciseSummary({
    required this.name,
    required this.sessions,
    required this.lastDone,
    this.formScore,
    this.pain,
  });

  final String name;
  final int sessions;
  final DateTime lastDone;
  final double? formScore;
  final double? pain;
}

/// "How am I doing?" for the last [days] days, from the patient's saved
/// sessions (and, if given, their active prescriptions). Pure: pass a fixed
/// [now] in tests.
class ProgressReport {
  ProgressReport._({
    required this.days,
    required this.sessions,
    required this.activeDays,
    required this.endedEarly,
    required this.time,
    required this.formScore,
    required this.previousFormScore,
    required this.pain,
    required this.previousPain,
    required this.repCompletion,
    required this.plannedSessions,
    required this.plannedDone,
    required this.points,
    required this.exercises,
    required this.status,
    required this.findings,
  });

  final int days;
  final int sessions;
  final int activeDays;
  final int endedEarly;
  final Duration time;

  /// Average form score (0–100) this period / the period before (null = no data).
  final double? formScore;
  final double? previousFormScore;

  /// Average pain (0–10) this period / the period before.
  final double? pain;
  final double? previousPain;

  /// Reps done ÷ reps targeted, 0–1 (null = no sessions).
  final double? repCompletion;

  /// Sessions the therapist's plan called for in this period, and how many of
  /// them were done (null when there's no active plan).
  final int? plannedSessions;
  final int? plannedDone;

  final List<ProgressPoint> points;
  final List<ExerciseSummary> exercises;
  final ProgressStatus status;
  final List<Finding> findings;

  double? get adherence {
    final planned = plannedSessions;
    if (planned == null || planned == 0) return null;
    return min(1.0, (plannedDone ?? 0) / planned);
  }

  /// Shortest and longest periods the report accepts. Out-of-range values
  /// are clamped rather than throwing, so a bad caller can't break a screen.
  static const int minDays = 1;
  static const int maxDays = 3660;

  /// Chart grouping: daily for a week, 5-day groups for a month, weekly after.
  static int bucketDaysFor(int days) => days <= 7 ? 1 : (days <= 30 ? 5 : 7);

  /// The sessions [ProgressReport.build] actually looks at: this period and
  /// the one before it. Used to send less data to a background isolate.
  /// Only compares instants, so it is cheap enough for the UI thread.
  static List<ExerciseSession> relevantSessions(
    List<ExerciseSession> all,
    DateTime now, {
    required int days,
  }) {
    final span = days.clamp(minDays, maxDays);
    final end = CalendarDays.addDays(CalendarDays.startOf(now), 1);
    final prevStart = CalendarDays.addDays(end, -2 * span);
    return [
      for (final s in all)
        if (!s.startTime.isBefore(prevStart) && s.startTime.isBefore(end)) s,
    ];
  }

  factory ProgressReport.build(
    List<ExerciseSession> all,
    DateTime now, {
    required int days,
    List<Prescription> prescriptions = const [],
  }) {
    final span = days.clamp(minDays, maxDays);
    final today = CalendarDays.startOf(now);
    final end = CalendarDays.addDays(today, 1); // exclusive: tomorrow 00:00
    final start = CalendarDays.addDays(end, -span);
    final prevStart = CalendarDays.addDays(start, -span);

    // ── Split into this period / the previous one ───────────────────────
    // Sessions dated in the future (a wrong phone clock) fall outside both.
    final cur = <ExerciseSession>[];
    final curDaysAgo = <int>[]; // parallel to `cur`: 0 = today
    final prev = <ExerciseSession>[];
    for (final s in all) {
      final t = s.startTime;
      if (t.isBefore(prevStart) || !t.isBefore(end)) continue;
      if (t.isBefore(start)) {
        prev.add(s);
      } else {
        cur.add(s);
        curDaysAgo.add(CalendarDays.between(t, today));
      }
    }

    // ── Totals ──────────────────────────────────────────────────────────
    var time = Duration.zero;
    var repsDone = 0;
    var repsTarget = 0;
    var endedEarly = 0;
    final activeDayOffsets = <int>{};
    for (var i = 0; i < cur.length; i++) {
      final s = cur[i];
      time += s.countedDuration;
      repsDone += s.safeCompletedReps;
      repsTarget += s.safeTargetReps;
      if (s.endedEarly) endedEarly++;
      activeDayOffsets.add(curDaysAgo[i]);
    }

    // ── Chart buckets, oldest first, the last one ending today ──────────
    // Bucket 0 (newest) covers 0..bucket-1 days ago, bucket 1 the group
    // before it, and so on. Each session is placed by arithmetic instead of
    // re-scanning the list once per bucket.
    final bucket = bucketDaysFor(span);
    final count = (span / bucket).ceil();
    final bucketSessions = List<int>.filled(count, 0);
    final bucketForm = List.generate(count, (_) => _Mean());
    final bucketPain = List.generate(count, (_) => _Mean());
    for (var i = 0; i < cur.length; i++) {
      final b = curDaysAgo[i] ~/ bucket;
      if (b >= count) continue; // can't happen; defensive
      bucketSessions[b]++;
      bucketForm[b].addNullable(cur[i].safeFormScore);
      bucketPain[b].addNullable(cur[i].safePain);
    }
    final points = <ProgressPoint>[
      for (var b = count - 1; b >= 0; b--)
        ProgressPoint(
          start: CalendarDays.addDays(end, -(b + 1) * bucket),
          days: bucket,
          sessions: bucketSessions[b],
          formScore: bucketForm[b].value,
          pain: bucketPain[b].value,
        ),
    ];

    // ── Per exercise, most practised first ──────────────────────────────
    final byName = <String, _ExerciseTotals>{};
    for (final s in cur) {
      byName.putIfAbsent(s.exerciseName, _ExerciseTotals.new).add(s);
    }
    final exercises = [
      for (final e in byName.entries)
        ExerciseSummary(
          name: e.key,
          sessions: e.value.sessions,
          lastDone: e.value.lastDone!,
          formScore: e.value.form.value,
          pain: e.value.pain.value,
        ),
    ];
    // List.sort isn't stable, so ties are broken by name to keep the order
    // the same on every rebuild.
    exercises.sort((a, b) {
      final bySessions = b.sessions.compareTo(a.sessions);
      return bySessions != 0 ? bySessions : a.name.compareTo(b.name);
    });

    // ── The therapist's plan ────────────────────────────────────────────
    final (planned, plannedDone) = _plan(prescriptions, cur, start, today);

    final formScore = _form(cur);
    final previousFormScore = _form(prev);
    final pain = _pain(cur);
    final previousPain = _pain(prev);

    final (status, findings) = _assess(
      days: span,
      sessions: cur.length,
      activeDays: activeDayOffsets.length,
      endedEarly: endedEarly,
      formScore: formScore,
      previousFormScore: previousFormScore,
      pain: pain,
      previousPain: previousPain,
      planned: planned,
      plannedDone: plannedDone,
    );

    return ProgressReport._(
      days: span,
      sessions: cur.length,
      activeDays: activeDayOffsets.length,
      endedEarly: endedEarly,
      time: time,
      formScore: formScore,
      previousFormScore: previousFormScore,
      pain: pain,
      previousPain: previousPain,
      repCompletion: repsTarget > 0 ? min(1.0, repsDone / repsTarget) : null,
      plannedSessions: planned,
      plannedDone: plannedDone,
      points: points,
      exercises: exercises,
      status: status,
      findings: findings,
    );
  }

  static double? _form(Iterable<ExerciseSession> sessions) {
    final mean = _Mean();
    for (final s in sessions) {
      mean.addNullable(s.safeFormScore);
    }
    return mean.value;
  }

  static double? _pain(Iterable<ExerciseSession> sessions) {
    final mean = _Mean();
    for (final s in sessions) {
      mean.addNullable(s.safePain);
    }
    return mean.value;
  }

  /// Sessions the plan called for in this period and how many were done.
  ///
  /// Each prescription is counted from the day it was assigned (or the
  /// period start, whichever is later) up to yesterday: today isn't over
  /// yet, but sessions done today still count as done. With scheduled
  /// weekdays each scheduled day is one session; otherwise
  /// frequencyPerWeek is spread over the days. Both are null when nothing
  /// was planned yet.
  static (int?, int?) _plan(
    List<Prescription> prescriptions,
    List<ExerciseSession> cur,
    DateTime start,
    DateTime today,
  ) {
    if (prescriptions.isEmpty) return (null, null);

    // Completed (not ended early) sessions per prescription, built once
    // instead of re-scanning `cur` for every prescription.
    final doneByRx = <String, List<DateTime>>{};
    for (final s in cur) {
      final rx = s.prescriptionId;
      if (rx == null || s.endedEarly) continue;
      doneByRx.putIfAbsent(rx, () => []).add(s.startTime);
    }

    int? planned;
    int? plannedDone;
    for (final p in prescriptions) {
      final assigned = p.assignedAt;
      final assignedDay = assigned == null
          ? null
          : CalendarDays.startOf(assigned);
      final from = assignedDay != null && assignedDay.isAfter(start)
          ? assignedDay
          : start;
      // Assigned today or in the future (clock skew): nothing due yet.
      final spanDays = CalendarDays.between(from, today);
      if (spanDays <= 0) continue;

      // Only real weekdays (1 = Mon … 7 = Sun); bad values are ignored.
      final weekdays = {
        for (final d in p.schedule?.days ?? const <int>[])
          if (d >= 1 && d <= 7) d,
      };
      final int want;
      if (weekdays.isEmpty) {
        want = p.frequencyPerWeek <= 0
            ? 0
            : (p.frequencyPerWeek * spanDays / 7).floor();
      } else {
        var scheduled = 0;
        for (var i = 0; i < spanDays; i++) {
          // Weekday by arithmetic: no DateTime per day, no DST surprises.
          final weekday = (from.weekday - 1 + i) % 7 + 1;
          if (weekdays.contains(weekday)) scheduled++;
        }
        want = scheduled;
      }
      if (want <= 0) continue;

      final done = (doneByRx[p.id] ?? const <DateTime>[])
          .where((t) => !t.isBefore(from))
          .length;
      planned = (planned ?? 0) + want;
      plannedDone = (plannedDone ?? 0) + min(done, want);
    }
    return (planned, plannedDone);
  }

  /// Turns the numbers into a verdict and plain-language findings. These are
  /// encouragement and prompts to talk to the therapist, not clinical advice.
  static (ProgressStatus, List<Finding>) _assess({
    required int days,
    required int sessions,
    required int activeDays,
    required int endedEarly,
    required double? formScore,
    required double? previousFormScore,
    required double? pain,
    required double? previousPain,
    required int? planned,
    required int? plannedDone,
  }) {
    if (sessions == 0) {
      return (
        ProgressStatus.noData,
        const [
          Finding(
            FindingKind.info,
            'Complete an exercise to start seeing your progress here.',
          ),
        ],
      );
    }

    final good = <Finding>[];
    final warn = <Finding>[];
    final info = <Finding>[];
    var serious = false;

    // Consistency: against the plan if there is one, else active days.
    if (planned != null && planned > 0) {
      final pct = (min(1.0, plannedDone! / planned) * 100).round();
      final text =
          'Followed $pct% of your plan ($plannedDone of $planned sessions).';
      if (pct >= 80) {
        good.add(Finding(FindingKind.good, text));
      } else if (pct >= 50) {
        info.add(Finding(FindingKind.info, text));
      } else {
        warn.add(Finding(FindingKind.warning, text));
      }
    } else {
      final perWeek = activeDays * 7 / days;
      final text =
          'Exercised on $activeDays of the last $days day${days == 1 ? '' : 's'}.';
      if (perWeek >= 3) {
        good.add(Finding(FindingKind.good, text));
      } else if (perWeek >= 1.5) {
        info.add(Finding(FindingKind.info, text));
      } else {
        warn.add(
          Finding(FindingKind.warning, '$text Try to exercise more often.'),
        );
      }
    }

    // Form.
    if (formScore != null) {
      final f = formScore.round();
      final change = previousFormScore == null
          ? null
          : (formScore - previousFormScore).round();
      final trend = change == null || change.abs() < 3
          ? ''
          : (change > 0 ? ', up $change points' : ', down ${-change} points');
      if (formScore >= 80) {
        good.add(
          Finding(FindingKind.good, 'Good form: average score $f%$trend.'),
        );
      } else if (formScore >= 60) {
        info.add(
          Finding(
            FindingKind.info,
            'Form score $f%$trend. Slow, controlled reps help.',
          ),
        );
      } else {
        warn.add(
          Finding(
            FindingKind.warning,
            'Form score $f%$trend. Watch the on-screen tips and move slowly.',
          ),
        );
      }
    }

    // Pain (patient-reported, 0–10).
    if (pain != null) {
      final p = pain.toStringAsFixed(1);
      final change = previousPain == null ? null : pain - previousPain;
      if (pain >= 6) {
        serious = true;
        warn.add(
          Finding(
            FindingKind.warning,
            'Average pain $p/10. Please let your therapist know.',
          ),
        );
      } else if (change != null && change >= 2) {
        serious = true;
        warn.add(
          Finding(
            FindingKind.warning,
            'Pain went up to $p/10 (from ${previousPain!.toStringAsFixed(1)}). Tell your therapist.',
          ),
        );
      } else if (change != null && change <= -1) {
        good.add(
          Finding(
            FindingKind.good,
            'Pain is down to $p/10 (from ${previousPain!.toStringAsFixed(1)}).',
          ),
        );
      } else {
        info.add(Finding(FindingKind.info, 'Average pain $p/10.'));
      }
    }

    // Sessions stopped early.
    if (endedEarly > 0) {
      final share = endedEarly / sessions;
      final text =
          '$endedEarly session${endedEarly == 1 ? ' was' : 's were'} ended early.';
      if (share > 0.3) {
        warn.add(Finding(FindingKind.warning, text));
      } else {
        info.add(Finding(FindingKind.info, text));
      }
    }

    final ProgressStatus status;
    if (serious || warn.length >= 2) {
      status = ProgressStatus.needsAttention;
    } else if (warn.isEmpty && good.length >= 2) {
      status = ProgressStatus.great;
    } else {
      status = ProgressStatus.onTrack;
    }
    // Warnings first, so the important thing is read first.
    return (status, [...warn, ...good, ...info]);
  }
}

/// Running mean that ignores missing (null) and non-finite values.
class _Mean {
  double _sum = 0;
  int _count = 0;

  void addNullable(double? value) {
    if (value == null || !value.isFinite) return;
    _sum += value;
    _count++;
  }

  double? get value => _count == 0 ? null : _sum / _count;
}

/// Accumulates one exercise's sessions for [ExerciseSummary].
class _ExerciseTotals {
  int sessions = 0;
  DateTime? lastDone;
  final form = _Mean();
  final pain = _Mean();

  void add(ExerciseSession s) {
    sessions++;
    final last = lastDone;
    if (last == null || s.startTime.isAfter(last)) lastDone = s.startTime;
    form.addNullable(s.safeFormScore);
    pain.addNullable(s.safePain);
  }
}
