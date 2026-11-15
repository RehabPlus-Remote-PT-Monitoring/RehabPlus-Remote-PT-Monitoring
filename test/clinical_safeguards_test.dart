// Clinical safeguards: parsing of the clinical profile, clearance records
// and prescriptions' requiredSessions, the completion gate (same cases as
// the dashboard's PHP tests) and the patient-facing clearance status.
// Pure Dart: no Firebase.

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/screens/notification_page.dart';
import 'package:rehabplus/models/clearance_record.dart';
import 'package:rehabplus/models/clinical_profile.dart';
import 'package:rehabplus/models/exercise_model.dart';
import 'package:rehabplus/models/prescription.dart';
import 'package:rehabplus/models/session.dart';
import 'package:rehabplus/services/care_gate.dart';
import 'package:rehabplus/services/care_plan_data.dart';
import 'package:rehabplus/services/clinical_service.dart';
import 'package:rehabplus/widgets/clinical_start_dialogs.dart';

Prescription rx(
  String id, {
  String type = 'kneeExtension',
  int? required,
  bool active = true,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => Prescription(
  id: id,
  exerciseType: type,
  targetReps: 10,
  frequencyPerWeek: 3,
  requiredSessions: required,
  active: active,
  assignedAt: createdAt,
  updatedAt: updatedAt,
);

var _sessionCount = 0;

ExerciseSession session(
  String? prescriptionId, {
  bool endedEarly = false,
  List<double> scores = const [1, 1, 0, 1],
  DateTime? start,
}) => ExerciseSession(
  id: 's${_sessionCount++}',
  exerciseId: 'kneeExtension',
  exerciseName: 'Knee Extension',
  startTime: start ?? DateTime(2026, 11, 10, 9),
  targetReps: 10,
  targetSets: 1,
  prescriptionId: prescriptionId,
  endedEarly: endedEarly,
  repComplianceScores: scores,
);

ClearanceRecord record(
  ClearanceDecision decision,
  DateTime signedAt, {
  String id = 'c1',
}) => ClearanceRecord(
  id: id,
  decision: decision,
  signedAt: signedAt,
  physicianName: 'Dr. Reyes',
  physicianLicense: '0123456',
  findings: 'Full range of motion.',
);

void main() {
  group('Prescription.requiredSessions', () {
    Map<String, dynamic> doc(Object? required) => {
      'exerciseType': 'kneeExtension',
      'targetReps': 10,
      'requiredSessions': required,
    };

    test('reads a valid target', () {
      final p = Prescription.parse('r1', doc(12));
      expect(p.value!.requiredSessions, 12);
      expect(p.repaired, isEmpty);
    });

    test('missing means no target, not an error', () {
      final p = Prescription.parse('r1', {
        'exerciseType': 'kneeExtension',
        'targetReps': 10,
      });
      expect(p.isOk, isTrue);
      expect(p.value!.requiredSessions, isNull);
      expect(p.value!.active, isTrue);
    });

    test('invalid values become null and are reported', () {
      for (final bad in [0, -3, 501, 'ten', true]) {
        final p = Prescription.parse('r1', doc(bad));
        expect(p.isOk, isTrue, reason: '$bad');
        expect(p.value!.requiredSessions, isNull, reason: '$bad');
        expect(p.repaired, contains('requiredSessions'), reason: '$bad');
      }
    });

    test('reads updatedAt and active', () {
      final p = Prescription.parse('r1', {
        ...doc(3),
        'active': false,
        'updatedAt': Timestamp.fromDate(DateTime(2026, 11, 2)),
      });
      expect(p.value!.active, isFalse);
      expect(p.value!.updatedAt, DateTime(2026, 11, 2));
    });
  });

  group('ClinicalProfile.parse', () {
    test('reads a full dashboard profile', () {
      final p = ClinicalProfile.parse({
        'precautions': 'Avoid deep knee bends.',
        'dietaryNotes': 'Small frequent meals.',
        'nutritionFlags': [
          'diabetes',
          'low_intake',
          'unknown_code',
          'diabetes',
        ],
        'restrictedExercises': ['wallSit', 'notAnExercise'],
        'lowTolerance': true,
        'toleranceNote': 'Gets dizzy after 5 minutes',
        'validatedBy': 'uid-1',
        'validatedByName': 'Dr. Cruz',
        'validatedAt': Timestamp.fromDate(DateTime(2026, 11, 3)),
        'nextReassessmentAt': Timestamp.fromDate(DateTime(2026, 12, 1)),
      });
      expect(p.isOk, isTrue);
      final profile = p.value!;
      expect(profile.precautions, 'Avoid deep knee bends.');
      expect(profile.nutritionFlags, [
        NutritionFlag.diabetes,
        NutritionFlag.lowIntake,
      ]);
      expect(profile.nutritionFlags.map((f) => f.label), [
        'Diabetes',
        'Low food intake',
      ]);
      expect(profile.restrictedExercises, {ExerciseType.wallSit});
      expect(profile.restricts(ExerciseType.wallSit), isTrue);
      expect(profile.restricts(ExerciseType.kneeExtension), isFalse);
      expect(profile.lowTolerance, isTrue);
      expect(profile.validatedByName, 'Dr. Cruz');
      expect(profile.validatedAt, DateTime(2026, 11, 3));
      expect(profile.nextReassessmentAt, DateTime(2026, 12, 1));
      // Unknown codes are ignored silently, not reported as repairs.
      expect(p.repaired, isEmpty);
    });

    test('every flag code has the agreed label', () {
      expect(
        {for (final f in NutritionFlag.values) f.code: f.label},
        {
          'diabetes': 'Diabetes',
          'hypertension': 'High blood pressure',
          'low_intake': 'Low food intake',
          'dehydration_risk': 'Dehydration risk',
          'anemia': 'Anemia',
          'weight_management': 'Weight management',
          'renal_diet': 'Kidney (renal) diet',
          'food_allergy': 'Food allergy',
        },
      );
    });

    test('bad fields default instead of failing', () {
      final p = ClinicalProfile.parse({
        'precautions': 42,
        'nutritionFlags': 'diabetes',
        'restrictedExercises': [1, 'wallSit'],
        'lowTolerance': 'yes',
        'validatedAt': 'not a date',
      });
      expect(p.isOk, isTrue);
      final profile = p.value!;
      expect(profile.precautions, isNull);
      expect(profile.nutritionFlags, isEmpty);
      expect(profile.restrictedExercises, {ExerciseType.wallSit});
      expect(profile.lowTolerance, isFalse);
      expect(
        p.repaired,
        containsAll([
          'precautions',
          'nutritionFlags',
          'restrictedExercises',
          'lowTolerance',
          'validatedAt',
        ]),
      );
    });

    test('an empty doc is an empty profile', () {
      final profile = ClinicalProfile.parse({}).value!;
      expect(profile.isEmpty, isTrue);
      expect(profile.lowTolerance, isFalse);
    });
  });

  group('ClearanceRecord.parse', () {
    Map<String, dynamic> doc({
      Object? decision = 'cleared',
      Object? signedAt,
    }) => {
      'decision': decision,
      'physicianName': 'Dr. Reyes',
      'physicianLicense': '0123456',
      'assessedAt': Timestamp.fromDate(DateTime(2026, 11, 14)),
      'findings': 'Full range of motion.',
      'recommendations': 'Keep walking daily.',
      'signedByName': 'Admin',
      'signedAt': signedAt ?? Timestamp.fromDate(DateTime(2026, 11, 14, 15)),
    };

    test('reads both decisions', () {
      final cleared = ClearanceRecord.parse('c1', doc()).value!;
      expect(cleared.decision, ClearanceDecision.cleared);
      expect(cleared.isCleared, isTrue);
      expect(cleared.physicianName, 'Dr. Reyes');
      expect(cleared.physicianLicense, '0123456');
      expect(cleared.assessedAt, DateTime(2026, 11, 14));
      expect(cleared.findings, 'Full range of motion.');
      expect(cleared.recommendations, 'Keep walking daily.');
      expect(cleared.signedAt, DateTime(2026, 11, 14, 15));

      final notCleared = ClearanceRecord.parse(
        'c2',
        doc(decision: 'not_cleared'),
      ).value!;
      expect(notCleared.decision, ClearanceDecision.notCleared);
    });

    test('an unknown or missing decision skips the record', () {
      for (final bad in ['CLEARED', 'maybe', null, true]) {
        final p = ClearanceRecord.parse('c1', doc(decision: bad));
        expect(p.isOk, isFalse, reason: '$bad');
        expect(p.error, contains('decision'));
      }
    });

    test('a missing signedAt skips the record', () {
      final data = doc()..remove('signedAt');
      expect(ClearanceRecord.parse('c1', data).isOk, isFalse);
    });

    test('newest wins by signedAt, whatever the order', () {
      final older = record(ClearanceDecision.cleared, DateTime(2026, 10, 1));
      final newer = record(
        ClearanceDecision.notCleared,
        DateTime(2026, 11, 1),
        id: 'c2',
      );
      expect(ClearanceRecord.newest([older, newer]), same(newer));
      expect(ClearanceRecord.newest([newer, older]), same(newer));
      expect(ClearanceRecord.newest(const []), isNull);
    });

    test(
      'ClinicalService.parseClearanceDocs skips bad docs, sorts newest first',
      () {
        final records = ClinicalService.parseClearanceDocs([
          MapEntry(
            'old',
            doc(signedAt: Timestamp.fromDate(DateTime(2026, 1, 1))),
          ),
          MapEntry('bad', doc(decision: 'auto_cleared')),
          MapEntry(
            'new',
            doc(signedAt: Timestamp.fromDate(DateTime(2026, 6, 1))),
          ),
        ]);
        expect(records.map((r) => r.id), ['new', 'old']);
      },
    );
  });

  group('ClinicalService.parseProfileDoc', () {
    test('no document = loaded, no profile', () {
      final result = ClinicalService.parseProfileDoc(null);
      expect(result.available, isTrue);
      expect(result.profile, isNull);
    });

    test('a document = loaded profile', () {
      final result = ClinicalService.parseProfileDoc({'lowTolerance': true});
      expect(result.available, isTrue);
      expect(result.profile!.lowTolerance, isTrue);
    });
  });

  group('evaluateCareGate (same cases as the dashboard)', () {
    test('(a) no prescriptions -> noProgram', () {
      final gate = evaluateCareGate(
        prescriptions: [],
        sessions: [session('x')],
      );
      expect(gate.state, CareGateState.noProgram);
      expect(gate.requirements, isEmpty);
    });

    test('(b) required 3, 2 finished + 1 ended early -> inProgress 2/3', () {
      final gate = evaluateCareGate(
        prescriptions: [rx('r1', required: 3)],
        sessions: [
          session('r1'),
          session('r1'),
          session('r1', endedEarly: true),
        ],
      );
      expect(gate.state, CareGateState.inProgress);
      final req = gate.requirements.single;
      expect(req.finished, 2);
      expect(req.required, 3);
      expect(req.isMet, isFalse);
      expect(req.exerciseName, 'Knee Extension');
      expect(req.statusText, '2 of 3 sessions');
      expect(gate.missing, [req]);
    });

    test('(c) no requiredSessions -> inProgress, no target', () {
      final gate = evaluateCareGate(
        prescriptions: [rx('r1')],
        sessions: [for (var i = 0; i < 20; i++) session('r1')],
      );
      expect(gate.state, CareGateState.inProgress);
      final req = gate.requirements.single;
      expect(req.hasTarget, isFalse);
      expect(req.finished, 20);
      expect(req.statusText, 'no completion target set');
    });

    test('(d) two prescriptions both met -> readyForReview', () {
      final gate = evaluateCareGate(
        prescriptions: [
          rx('r1', required: 2),
          rx('r2', type: 'heelSlide', required: 1),
        ],
        sessions: [session('r1'), session('r1'), session('r1'), session('r2')],
      );
      expect(gate.state, CareGateState.readyForReview);
      expect(gate.missing, isEmpty);
    });

    test(
      '(e) met prescription with a restricted type -> inProgress restricted',
      () {
        final gate = evaluateCareGate(
          prescriptions: [rx('r1', type: 'wallSit', required: 1)],
          sessions: [session('r1'), session('r1')],
          restricted: {ExerciseType.wallSit},
        );
        expect(gate.state, CareGateState.inProgress);
        final req = gate.requirements.single;
        expect(req.restricted, isTrue);
        expect(req.isMet, isFalse);
        expect(req.statusText, 'restricted by your clinician');
      },
    );

    test('(f) sessions for other or no prescription do not count', () {
      final gate = evaluateCareGate(
        prescriptions: [rx('r1', required: 2)],
        sessions: [session('r1'), session('other'), session(null)],
      );
      expect(gate.state, CareGateState.inProgress);
      expect(gate.requirements.single.finished, 1);
    });

    test('(g) inactive prescriptions are ignored', () {
      final onlyInactive = evaluateCareGate(
        prescriptions: [rx('old', required: 5, active: false)],
        sessions: const [],
      );
      expect(onlyInactive.state, CareGateState.noProgram);

      final mixed = evaluateCareGate(
        prescriptions: [
          rx('old', required: 5, active: false),
          rx('r1', required: 1),
        ],
        sessions: [session('r1')],
      );
      expect(mixed.state, CareGateState.readyForReview);
      expect(mixed.requirements.map((r) => r.prescriptionId), ['r1']);
    });

    test('an unknown exercise type still blocks, shown by its code', () {
      final gate = evaluateCareGate(
        prescriptions: [rx('r1', type: 'futureExercise')],
        sessions: const [],
      );
      expect(gate.requirements.single.exerciseName, 'futureExercise');
      expect(gate.state, CareGateState.inProgress);
    });
  });

  group('resolveClearance', () {
    final complete = evaluateCareGate(
      prescriptions: [rx('r1', required: 1)],
      sessions: [session('r1')],
    );
    final incomplete = evaluateCareGate(
      prescriptions: [rx('r1', required: 3)],
      sessions: [session('r1')],
    );

    test('a complete program with NO record is never cleared', () {
      final status = resolveClearance(gate: complete, records: const []);
      expect(status.kind, ClearanceStatusKind.readyForReview);
      expect(status.kind, isNot(ClearanceStatusKind.cleared));
      expect(status.record, isNull);
    });

    test('incomplete with no record -> notEligible with the missing list', () {
      final status = resolveClearance(gate: incomplete, records: const []);
      expect(status.kind, ClearanceStatusKind.notEligible);
      expect(status.missing.single.statusText, '1 of 3 sessions');
    });

    test('unreadable records -> unavailable, never cleared', () {
      expect(
        resolveClearance(gate: complete, records: null).kind,
        ClearanceStatusKind.unavailable,
      );
    });

    test('newest record decides: not cleared', () {
      final status = resolveClearance(
        gate: complete,
        records: [
          record(ClearanceDecision.cleared, DateTime(2026, 10, 1)),
          record(ClearanceDecision.notCleared, DateTime(2026, 11, 1), id: 'c2'),
        ],
      );
      expect(status.kind, ClearanceStatusKind.notCleared);
      expect(status.record!.id, 'c2');
    });

    test(
      'a cleared record shows cleared even if the program changed since',
      () {
        final signed = DateTime(2026, 11, 1);
        final changed = [
          rx('r1', required: 3, createdAt: DateTime(2026, 10, 1)),
          rx('r2', required: 3, updatedAt: DateTime(2026, 11, 5)),
        ];
        final status = resolveClearance(
          gate: evaluateCareGate(prescriptions: changed, sessions: const []),
          records: [record(ClearanceDecision.cleared, signed)],
          prescriptions: changed,
        );
        expect(status.kind, ClearanceStatusKind.cleared);
        expect(status.programChangedSinceClearance, isTrue);
      },
    );

    test('no program-changed note when timestamps are older or missing', () {
      final status = resolveClearance(
        gate: complete,
        records: [record(ClearanceDecision.cleared, DateTime(2026, 11, 1))],
        prescriptions: [
          rx('r1', required: 1, createdAt: DateTime(2026, 9, 1)),
          rx('r2', required: 1),
          // Inactive ones don't count as a program change.
          rx('r3', active: false, updatedAt: DateTime(2026, 12, 1)),
        ],
      );
      expect(status.kind, ClearanceStatusKind.cleared);
      expect(status.programChangedSinceClearance, isFalse);
    });
  });

  group('CarePlanView.build', () {
    test(
      'profile restrictions feed the gate; all reads unavailable -> unavailable',
      () {
        final view = CarePlanView.build(
          snapshot: const CarePlanSnapshot(
            prescriptions: null,
            profile: ClinicalProfileResult.unavailable(),
            clearances: null,
          ),
          sessions: const [],
          now: DateTime(2026, 11, 15),
        );
        expect(view.gate, isNull);
        expect(view.clearance.kind, ClearanceStatusKind.unavailable);
      },
    );

    test('restricted exercise from the profile blocks the program', () {
      final view = CarePlanView.build(
        snapshot: CarePlanSnapshot(
          prescriptions: [rx('r1', type: 'wallSit', required: 1)],
          profile: const ClinicalProfileResult.loaded(
            ClinicalProfile(restrictedExercises: {ExerciseType.wallSit}),
          ),
          clearances: const [],
        ),
        sessions: [session('r1')],
        now: DateTime(2026, 11, 15),
      );
      expect(view.gate!.state, CareGateState.inProgress);
      expect(view.clearance.kind, ClearanceStatusKind.notEligible);
    });

    test('compliance: accuracy from finished sessions only', () {
      final summary = ComplianceSummary.from(
        sessions: [
          session('r1', scores: [1, 1]),
          session('r1', scores: [1, 0]),
          session('r1', endedEarly: true, scores: [0, 0]),
        ],
        prescriptions: const [],
        now: DateTime(2026, 11, 15),
      );
      expect(summary.finishedSessions, 2);
      expect(summary.formAccuracy, closeTo(75, 0.001));
      expect(summary.weekAdherence, isNull);
    });
  });

  group('checkExerciseStart', () {
    test('no profile behaves as before', () {
      expect(
        checkExerciseStart(null, ExerciseType.wallSit),
        ExerciseStartCheck.allowed,
      );
    });

    test('restricted wins over low tolerance', () {
      const profile = ClinicalProfile(
        restrictedExercises: {ExerciseType.wallSit},
        lowTolerance: true,
      );
      expect(
        checkExerciseStart(profile, ExerciseType.wallSit),
        ExerciseStartCheck.restricted,
      );
      expect(
        checkExerciseStart(profile, ExerciseType.kneeExtension),
        ExerciseStartCheck.caution,
      );
    });

    test('caution text quotes the note', () {
      expect(
        lowToleranceMessage('Gets dizzy after 5 minutes.'),
        'Your clinician noted low exercise tolerance: Gets dizzy after 5 '
        'minutes. Stop if pain increases.',
      );
      expect(
        lowToleranceMessage(null),
        'Your clinician noted low exercise tolerance. Stop if pain increases.',
      );
    });
  });

  group('care_update notifications', () {
    test('open Care plan & clearance; other types keep their own behaviour', () {
      expect(notificationOpensCarePlan('care_update'), isTrue);
      expect(notificationOpensCarePlan('message'), isFalse);
      expect(notificationOpensCarePlan('progress'), isFalse);
      expect(notificationOpensCarePlan('exercise_assigned'), isFalse);
    });
  });
}
