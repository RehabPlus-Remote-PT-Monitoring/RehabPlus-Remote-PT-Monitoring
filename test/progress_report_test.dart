import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/models/prescription.dart';
import 'package:rehabplus/models/session.dart';
import 'package:rehabplus/services/progress_report.dart';

// Friday 16 Oct 2026, 3 pm.
final now = DateTime(2026, 10, 16, 15);

ExerciseSession s(
  DateTime start, {
  String name = 'Knee Extension',
  List<double> scores = const [1, 1, 1],
  int? pain,
  bool endedEarly = false,
  String? prescriptionId,
  int reps = 10,
}) => ExerciseSession(
  id: '${start.toIso8601String()}$name',
  exerciseId: name,
  exerciseName: name,
  startTime: start,
  endTime: start.add(const Duration(minutes: 10)),
  targetReps: 10,
  targetSets: 1,
  completedReps: reps,
  repComplianceScores: scores,
  painLevel: pain,
  endedEarly: endedEarly,
  prescriptionId: prescriptionId,
);

DateTime daysAgo(int d, [int hour = 9]) =>
    DateTime(now.year, now.month, now.day - d, hour);

void main() {
  test('no sessions: no data', () {
    final r = ProgressReport.build([], now, days: 7);
    expect(r.status, ProgressStatus.noData);
    expect(r.points, hasLength(7));
    expect(r.points.every((p) => p.sessions == 0), isTrue);
  });

  test('regular sessions with good form and falling pain: doing great', () {
    final sessions = [
      for (final d in [0, 1, 3, 5]) s(daysAgo(d), pain: 2),
      // Previous week: more pain.
      for (final d in [8, 10]) s(daysAgo(d), pain: 4),
    ];
    final r = ProgressReport.build(sessions, now, days: 7);
    expect(r.sessions, 4);
    expect(r.activeDays, 4);
    expect(r.formScore, 100);
    expect(r.pain, 2);
    expect(r.previousPain, 4);
    expect(r.status, ProgressStatus.great);
    expect(r.findings.first.kind, FindingKind.good);
  });

  test('high pain always needs attention, and is listed first', () {
    final sessions = [
      for (final d in [0, 1, 2, 3]) s(daysAgo(d), pain: 7),
    ];
    final r = ProgressReport.build(sessions, now, days: 7);
    expect(r.status, ProgressStatus.needsAttention);
    expect(r.findings.first.kind, FindingKind.warning);
    expect(r.findings.first.text, contains('therapist'));
  });

  test('pain rising by 2 or more needs attention', () {
    final sessions = [
      s(daysAgo(1), pain: 5),
      s(daysAgo(2), pain: 5),
      s(daysAgo(9), pain: 2),
    ];
    final r = ProgressReport.build(sessions, now, days: 7);
    expect(r.status, ProgressStatus.needsAttention);
  });

  test('form score trend compares with the previous period', () {
    final sessions = [
      s(daysAgo(1), scores: [1, 1, 0.8, 0.8]), // 90%
      s(daysAgo(9), scores: [0.8, 0.8]), // 80%
    ];
    final r = ProgressReport.build(sessions, now, days: 7);
    expect(r.formScore!.round(), 90);
    expect(r.previousFormScore!.round(), 80);
    expect(r.findings.any((f) => f.text.contains('up 10 points')), isTrue);
  });

  test('plan: frequency-based, from assignment up to yesterday', () {
    final rx = Prescription(
      id: 'rx1',
      exerciseType: 'kneeExtension',
      targetReps: 10,
      frequencyPerWeek: 7, // daily
      assignedAt: daysAgo(4, 8), // 4 full days before today
    );
    final sessions = [
      s(daysAgo(0), prescriptionId: 'rx1'), // today still counts
      s(daysAgo(1), prescriptionId: 'rx1'),
      s(daysAgo(2), prescriptionId: 'rx1', endedEarly: true), // not counted
      s(daysAgo(5), prescriptionId: 'rx1'), // before it was assigned
    ];
    final r = ProgressReport.build(sessions, now, days: 7, prescriptions: [rx]);
    expect(r.plannedSessions, 4);
    expect(r.plannedDone, 2);
    expect(r.adherence, 0.5);
  });

  test('plan: scheduled weekdays only', () {
    // Mon/Wed/Fri. The 7-day window is Sat 10 .. Fri 16 (today, not counted
    // yet), so the scheduled days so far are Mon 12 and Wed 14.
    final rx = Prescription(
      id: 'rx2',
      exerciseType: 'bicepCurl',
      targetReps: 12,
      frequencyPerWeek: 3,
      schedule: const PrescriptionSchedule(days: [1, 3, 5]),
    );
    final r = ProgressReport.build(
      [s(daysAgo(2), prescriptionId: 'rx2')],
      now,
      days: 7,
      prescriptions: [rx],
    );
    expect(r.plannedSessions, 2);
    expect(r.plannedDone, 1);
  });

  test('plan assigned today: no plan figure yet', () {
    final rx = Prescription(
      id: 'rx3',
      exerciseType: 'sideRaise',
      targetReps: 8,
      frequencyPerWeek: 3,
      assignedAt: daysAgo(0, 7),
    );
    final r = ProgressReport.build(
      [s(daysAgo(0))],
      now,
      days: 7,
      prescriptions: [rx],
    );
    expect(r.plannedSessions, isNull);
    expect(r.adherence, isNull);
  });

  test('chart buckets: daily for 7, 5-day for 30, weekly for 90', () {
    final sessions = [s(daysAgo(0)), s(daysAgo(0, 18)), s(daysAgo(6))];
    final week = ProgressReport.build(sessions, now, days: 7);
    expect(week.points, hasLength(7));
    expect(week.points.last.sessions, 2); // today
    expect(week.points.first.sessions, 1); // 6 days ago
    expect(week.points.last.start, DateTime(2026, 10, 16));

    expect(ProgressReport.build(sessions, now, days: 30).points, hasLength(6));
    final quarter = ProgressReport.build(sessions, now, days: 90);
    expect(quarter.points, hasLength(13));
    expect(quarter.points.last.sessions, 3); // last 7 days
  });

  test('per-exercise breakdown, most practised first', () {
    final sessions = [
      s(daysAgo(1), name: 'Bicep Curl', pain: 1),
      s(daysAgo(2), name: 'Wall Sit'),
      s(daysAgo(3), name: 'Bicep Curl', pain: 3),
    ];
    final r = ProgressReport.build(sessions, now, days: 7);
    expect(r.exercises.map((e) => e.name), ['Bicep Curl', 'Wall Sit']);
    expect(r.exercises.first.sessions, 2);
    expect(r.exercises.first.pain, 2);
  });
}
