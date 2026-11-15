// lib/services/care_plan_data.dart
//
// What the "Care plan & clearance" page shows, assembled from plain data so
// it is unit-tested without Firebase. The page loads the raw pieces through
// ClinicalService and the session history through AppProvider; this file
// turns them into the four sections' inputs.

import '../models/clearance_record.dart';
import '../models/prescription.dart';
import '../models/session.dart';
import 'care_gate.dart';
import 'clinical_service.dart';
import 'progress_report.dart';
import 'progress_stats.dart';

/// The raw reads behind the page. A null list means that read failed.
class CarePlanSnapshot {
  const CarePlanSnapshot({
    required this.prescriptions,
    required this.profile,
    required this.clearances,
  });

  /// Active prescriptions, or null when they couldn't be read.
  final List<Prescription>? prescriptions;
  final ClinicalProfileResult profile;

  /// Clearance records, or null when they couldn't be read.
  final List<ClearanceRecord>? clearances;

  /// Loads all three reads in parallel. Never throws (ClinicalService logs
  /// and returns "unavailable" for each read that fails).
  static Future<CarePlanSnapshot> load(ClinicalService service) async {
    final prescriptions = service.loadActivePrescriptions();
    final profile = service.loadProfile();
    final clearances = service.loadClearances();
    return CarePlanSnapshot(
      prescriptions: await prescriptions,
      profile: await profile,
      clearances: await clearances,
    );
  }
}

/// "How well and how regularly" numbers for the Compliance section. These
/// are not a medical result.
class ComplianceSummary {
  const ComplianceSummary({
    required this.formAccuracy,
    required this.finishedSessions,
    required this.weekAdherence,
  });

  /// Mean form accuracy of finished sessions, 0–100 (null = none yet).
  /// Same per-session score as the progress report (counted reps out of
  /// attempts), which is the stored `overallCompliance` made safe.
  final double? formAccuracy;

  /// Finished (not ended early) sessions the accuracy is based on.
  final int finishedSessions;

  /// Sessions done ÷ sessions planned over the last 7 days, 0–1, from the
  /// progress report's plan-adherence rule (null = nothing planned yet).
  final double? weekAdherence;

  static ComplianceSummary from({
    required List<ExerciseSession> sessions,
    required List<Prescription> prescriptions,
    required DateTime now,
  }) {
    var sum = 0.0;
    var counted = 0;
    var finished = 0;
    for (final session in sessions) {
      if (session.endedEarly) continue;
      finished++;
      final score = session.safeFormScore;
      if (score == null) continue;
      sum += score;
      counted++;
    }
    final week = ProgressReport.build(
      sessions,
      now,
      days: 7,
      prescriptions: [
        for (final p in prescriptions)
          if (p.active) p,
      ],
    );
    return ComplianceSummary(
      formAccuracy: counted == 0 ? null : sum / counted,
      finishedSessions: finished,
      weekAdherence: week.adherence,
    );
  }
}

/// Everything the four sections need.
class CarePlanView {
  const CarePlanView({
    required this.gate,
    required this.compliance,
    required this.clearance,
    required this.profile,
  });

  /// Null when the prescriptions couldn't be read.
  final CareGateResult? gate;
  final ComplianceSummary compliance;
  final ClearanceStatus clearance;
  final ClinicalProfileResult profile;

  static CarePlanView build({
    required CarePlanSnapshot snapshot,
    required List<ExerciseSession> sessions,
    required DateTime now,
  }) {
    final prescriptions = snapshot.prescriptions;
    final restricted =
        snapshot.profile.profile?.restrictedExercises ?? const {};
    final gate = prescriptions == null
        ? null
        : evaluateCareGate(
            prescriptions: prescriptions,
            sessions: sessions,
            restricted: restricted,
          );

    // Without the program the gate can't be judged, so the clearance can
    // only come from a record; with no record either it is "unavailable".
    final ClearanceStatus clearance;
    if (gate == null) {
      final latest = snapshot.clearances == null
          ? null
          : ClearanceRecord.newest(snapshot.clearances!);
      clearance = latest == null
          ? const ClearanceStatus(kind: ClearanceStatusKind.unavailable)
          : resolveClearance(
              gate: const CareGateResult(
                state: CareGateState.inProgress,
                requirements: [],
              ),
              records: snapshot.clearances,
            );
    } else {
      clearance = resolveClearance(
        gate: gate,
        records: snapshot.clearances,
        prescriptions: prescriptions!,
      );
    }

    return CarePlanView(
      gate: gate,
      compliance: ComplianceSummary.from(
        sessions: sessions,
        prescriptions: prescriptions ?? const [],
        now: now,
      ),
      clearance: clearance,
      profile: snapshot.profile,
    );
  }
}
