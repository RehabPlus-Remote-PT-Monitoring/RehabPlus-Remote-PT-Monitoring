import 'dart:math';

import '../models/prescription.dart';
import '../models/session.dart';

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

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  static double? _avg(Iterable<double> xs) {
    final list = xs.toList();
    if (list.isEmpty) return null;
    return list.reduce((a, b) => a + b) / list.length;
  }

  static double? _form(Iterable<ExerciseSession> s) => _avg(
    s
        .where((x) => x.repComplianceScores.isNotEmpty)
        .map((x) => x.overallCompliance * 100),
  );

  static double? _pain(Iterable<ExerciseSession> s) => _avg(
    s.where((x) => x.painLevel != null).map((x) => x.painLevel!.toDouble()),
  );

  /// Chart grouping: daily for a week, 5-day groups for a month, weekly after.
  static int bucketDaysFor(int days) => days <= 7 ? 1 : (days <= 30 ? 5 : 7);

  factory ProgressReport.build(
    List<ExerciseSession> all,
    DateTime now, {
    required int days,
    List<Prescription> prescriptions = const [],
  }) {
    final end = _day(now).add(const Duration(days: 1));
    final start = end.subtract(Duration(days: days));
    final prevStart = start.subtract(Duration(days: days));

    bool inRange(ExerciseSession s, DateTime a, DateTime b) =>
        !s.startTime.isBefore(a) && s.startTime.isBefore(b);

    final cur = all.where((s) => inRange(s, start, end)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final prev = all.where((s) => inRange(s, prevStart, start)).toList();

    var time = Duration.zero;
    var repsDone = 0;
    var repsTarget = 0;
    for (final s in cur) {
      final e = s.endTime;
      if (e != null && e.isAfter(s.startTime)) {
        time += e.difference(s.startTime);
      }
      repsDone += s.completedReps;
      repsTarget += s.targetReps;
    }

    // Chart buckets, oldest first, the last one ending today.
    final bucket = bucketDaysFor(days);
    final count = (days / bucket).ceil();
    final points = <ProgressPoint>[];
    for (var i = count - 1; i >= 0; i--) {
      final bEnd = end.subtract(Duration(days: i * bucket));
      final bStart = bEnd.subtract(Duration(days: bucket));
      final inBucket = cur.where((s) => inRange(s, bStart, bEnd));
      points.add(
        ProgressPoint(
          start: bStart,
          days: bucket,
          sessions: inBucket.length,
          formScore: _form(inBucket),
          pain: _pain(inBucket),
        ),
      );
    }

    // Per exercise, most practised first.
    final byName = <String, List<ExerciseSession>>{};
    for (final s in cur) {
      byName.putIfAbsent(s.exerciseName, () => []).add(s);
    }
    final exercises =
        byName.entries
            .map(
              (e) => ExerciseSummary(
                name: e.key,
                sessions: e.value.length,
                lastDone: e.value.last.startTime,
                formScore: _form(e.value),
                pain: _pain(e.value),
              ),
            )
            .toList()
          ..sort((a, b) => b.sessions.compareTo(a.sessions));

    // The therapist's plan, counted from when each prescription was
    // assigned up to yesterday (today isn't over yet; sessions done today
    // still count). With scheduled weekdays, each scheduled day is one
    // session; otherwise frequencyPerWeek spread over the days.
    int? planned;
    int? plannedDone;
    final today = _day(now);
    for (final p in prescriptions) {
      final assigned = p.assignedAt;
      final from = assigned != null && _day(assigned).isAfter(start)
          ? _day(assigned)
          : start;
      final spanDays = today.difference(from).inDays;
      if (spanDays <= 0) continue;
      final weekdays = p.schedule?.days ?? const <int>[];
      final want = weekdays.isEmpty
          ? (p.frequencyPerWeek * spanDays / 7).floor()
          : [
              for (var i = 0; i < spanDays; i++) from.add(Duration(days: i)),
            ].where((d) => weekdays.contains(d.weekday)).length;
      if (want == 0) continue;
      final done = cur
          .where(
            (s) =>
                s.prescriptionId == p.id &&
                !s.endedEarly &&
                !s.startTime.isBefore(from),
          )
          .length;
      planned = (planned ?? 0) + want;
      plannedDone = (plannedDone ?? 0) + min(done, want);
    }

    final formScore = _form(cur);
    final previousFormScore = _form(prev);
    final pain = _pain(cur);
    final previousPain = _pain(prev);
    final activeDays = cur.map((s) => _day(s.startTime)).toSet().length;
    final endedEarly = cur.where((s) => s.endedEarly).length;

    final (status, findings) = _assess(
      days: days,
      sessions: cur.length,
      activeDays: activeDays,
      endedEarly: endedEarly,
      formScore: formScore,
      previousFormScore: previousFormScore,
      pain: pain,
      previousPain: previousPain,
      planned: planned,
      plannedDone: plannedDone,
    );

    return ProgressReport._(
      days: days,
      sessions: cur.length,
      activeDays: activeDays,
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
