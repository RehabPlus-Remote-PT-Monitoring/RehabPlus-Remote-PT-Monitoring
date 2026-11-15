// lib/services/care_gate.dart
//
// The exercise-completion gate and the patient-facing clearance status.
// Pure Dart, no Firebase, unit-tested in test/care_gate_test.dart.
//
// The SAME rules run on the clinic dashboard (PHP), with the same test
// cases, so the patient and the clinician always see the same answer
// (docs/superpowers/specs/2026-11-15-clinical-safeguards-design.md §3):
//   - Per active prescription, "finished" = sessions with
//     prescriptionId == prescription id and endedEarly == false.
//   - A prescription is complete when requiredSessions is set and
//     finished >= requiredSessions. Without requiredSessions it can't be
//     complete ("no completion target set").
//   - An active prescription for an exercise the clinician restricted is a
//     blocking requirement even if its sessions are done.
//   - The program is complete (ready for review) when there is at least one
//     active prescription and every one of them is complete and allowed.
//
// The gate NEVER produces "cleared". Clearance only comes from the newest
// physician-signed ClearanceRecord ([resolveClearance]).

import '../models/clearance_record.dart';
import '../models/exercise_model.dart';
import '../models/prescription.dart';
import '../models/session.dart';

/// The three gate states (design doc §3).
enum CareGateState {
  /// No active prescription.
  noProgram,

  /// Some active prescription is incomplete or restricted.
  inProgress,

  /// Every active prescription is complete: ready for physician assessment.
  readyForReview,
}

/// One active prescription's progress toward its completion target.
class GateRequirement {
  const GateRequirement({
    required this.prescriptionId,
    required this.exerciseType,
    required this.exerciseName,
    required this.finished,
    required this.required,
    required this.restricted,
  });

  final String prescriptionId;

  /// Exercise type code, e.g. `kneeExtension`.
  final String exerciseType;

  /// What the patient sees, e.g. "Knee Extension".
  final String exerciseName;

  /// Sessions finished for this prescription (not ended early).
  final int finished;

  /// Sessions needed, or null when the clinician set no target.
  final int? required;

  /// The clinician restricted this exercise; the program must be adjusted.
  final bool restricted;

  bool get hasTarget => required != null;

  /// Complete and allowed: counts toward a complete program.
  bool get isMet => !restricted && required != null && finished >= required!;

  /// 0–1 share of the target done, or null without a target.
  double? get fraction {
    final target = required;
    if (target == null || target <= 0) return null;
    return (finished / target).clamp(0.0, 1.0);
  }

  /// Plain-language status for the missing list, e.g. "2 of 3 sessions".
  String get statusText {
    if (restricted) return 'restricted by your clinician';
    final target = required;
    if (target == null) return 'no completion target set';
    return '$finished of $target sessions';
  }
}

/// The gate's answer for a whole program.
class CareGateResult {
  const CareGateResult({required this.state, required this.requirements});

  final CareGateState state;

  /// Every active prescription, in input order.
  final List<GateRequirement> requirements;

  /// The requirements still blocking a complete program.
  List<GateRequirement> get missing => [
    for (final r in requirements)
      if (!r.isMet) r,
  ];
}

/// Display name for an exercise type code, falling back to the code itself
/// for a type this app version doesn't know.
String exerciseNameFor(String typeCode) {
  for (final config in availableExercises) {
    if (config.type.name == typeCode) return config.title;
  }
  return typeCode;
}

/// Computes the completion gate. See the file comment for the rules.
///
/// [restricted] are the clinician's restricted exercise types (from the
/// clinical profile; empty when there is none or it couldn't be read).
CareGateResult evaluateCareGate({
  required List<Prescription> prescriptions,
  required List<ExerciseSession> sessions,
  Set<ExerciseType> restricted = const {},
}) {
  // Step 1: only active prescriptions are part of the program.
  final active = [
    for (final p in prescriptions)
      if (p.active) p,
  ];
  if (active.isEmpty) {
    return const CareGateResult(
      state: CareGateState.noProgram,
      requirements: [],
    );
  }

  // Step 2: count finished sessions per prescription id, once. Sessions
  // without a prescription id (free practice) never count.
  final finishedByRx = <String, int>{};
  for (final session in sessions) {
    final rxId = session.prescriptionId;
    if (rxId == null || session.endedEarly) continue;
    finishedByRx[rxId] = (finishedByRx[rxId] ?? 0) + 1;
  }

  // Step 3: one requirement per active prescription.
  final restrictedCodes = {for (final type in restricted) type.name};
  final requirements = [
    for (final p in active)
      GateRequirement(
        prescriptionId: p.id,
        exerciseType: p.exerciseType,
        exerciseName: exerciseNameFor(p.exerciseType),
        finished: finishedByRx[p.id] ?? 0,
        required: p.requiredSessions,
        restricted: restrictedCodes.contains(p.exerciseType),
      ),
  ];

  // Step 4: the program is complete only when every requirement is met.
  final complete = requirements.every((r) => r.isMet);
  return CareGateResult(
    state: complete ? CareGateState.readyForReview : CareGateState.inProgress,
    requirements: requirements,
  );
}

/// What the Medical clearance section tells the patient.
enum ClearanceStatusKind {
  /// The newest record says cleared (the only way to get here).
  cleared,

  /// The newest record says not cleared: continue the program.
  notCleared,

  /// Program complete, no decision yet: "Ready for physician assessment".
  readyForReview,

  /// Program not complete (or none assigned), no decision yet.
  notEligible,

  /// Clearance records couldn't be read (offline, rules not deployed).
  unavailable,
}

class ClearanceStatus {
  const ClearanceStatus({
    required this.kind,
    this.record,
    this.missing = const [],
    this.programChangedSinceClearance = false,
  });

  final ClearanceStatusKind kind;

  /// The newest record behind [kind] (cleared / notCleared only).
  final ClearanceRecord? record;

  /// What still blocks a complete program (notEligible only).
  final List<GateRequirement> missing;

  /// Cleared, but an active prescription was created or edited after the
  /// record was signed ("Your program was updated after this clearance").
  final bool programChangedSinceClearance;
}

/// Combines the gate with the newest clearance record.
///
/// [records] is null when the clearances couldn't be read: the answer is
/// then [ClearanceStatusKind.unavailable], never cleared. A record decides
/// on its own (a physician's decision outranks the gate); without one the
/// gate only says whether the patient is ready to be assessed.
ClearanceStatus resolveClearance({
  required CareGateResult gate,
  required List<ClearanceRecord>? records,
  List<Prescription> prescriptions = const [],
}) {
  if (records == null) {
    return const ClearanceStatus(kind: ClearanceStatusKind.unavailable);
  }

  final latest = ClearanceRecord.newest(records);
  if (latest != null) {
    if (latest.isCleared) {
      return ClearanceStatus(
        kind: ClearanceStatusKind.cleared,
        record: latest,
        programChangedSinceClearance: _programChangedAfter(
          latest.signedAt,
          prescriptions,
        ),
      );
    }
    return ClearanceStatus(
      kind: ClearanceStatusKind.notCleared,
      record: latest,
      missing: gate.missing,
    );
  }

  if (gate.state == CareGateState.readyForReview) {
    return const ClearanceStatus(kind: ClearanceStatusKind.readyForReview);
  }
  return ClearanceStatus(
    kind: ClearanceStatusKind.notEligible,
    missing: gate.missing,
  );
}

/// True when an active prescription's createdAt or updatedAt is after
/// [signedAt]. Prescriptions without those timestamps can't tell, so they
/// don't trigger the note.
bool _programChangedAfter(DateTime signedAt, List<Prescription> prescriptions) {
  for (final p in prescriptions) {
    if (!p.active) continue;
    final created = p.assignedAt;
    final updated = p.updatedAt;
    if (created != null && created.isAfter(signedAt)) return true;
    if (updated != null && updated.isAfter(signedAt)) return true;
  }
  return false;
}
