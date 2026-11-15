// Widget tests for Profile > Care plan & clearance (sections and screen
// with injected data) and for the clinician lock on exercise cards.
// No Firebase: every widget here takes plain data.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/app_palette.dart';
import 'package:rehabplus/models/clearance_record.dart';
import 'package:rehabplus/models/clinical_profile.dart';
import 'package:rehabplus/models/exercise_model.dart';
import 'package:rehabplus/models/prescription.dart';
import 'package:rehabplus/models/session.dart';
import 'package:rehabplus/screens/care_plan_screen.dart';
import 'package:rehabplus/screens/exercise_page.dart';
import 'package:rehabplus/services/care_gate.dart';
import 'package:rehabplus/services/care_plan_data.dart';
import 'package:rehabplus/services/clinical_service.dart';
import 'package:rehabplus/widgets/care_plan_sections.dart';

Prescription rx(String id, {String type = 'kneeExtension', int? required}) =>
    Prescription(
      id: id,
      exerciseType: type,
      targetReps: 10,
      frequencyPerWeek: 3,
      requiredSessions: required,
    );

var _n = 0;
ExerciseSession session(String rxId) => ExerciseSession(
  id: 's${_n++}',
  exerciseId: 'kneeExtension',
  exerciseName: 'Knee Extension',
  startTime: DateTime(2026, 11, 10),
  targetReps: 10,
  targetSets: 1,
  prescriptionId: rxId,
  repComplianceScores: const [1, 1, 1, 0],
);

final ClearanceRecord clearedRecord = ClearanceRecord(
  id: 'c1',
  decision: ClearanceDecision.cleared,
  signedAt: DateTime(2026, 11, 14, 15),
  assessedAt: DateTime(2026, 11, 14),
  physicianName: 'Dr. Ana Reyes',
  physicianLicense: '0123456',
  findings: 'Full knee range of motion, no pain on loading.',
);

Widget host(Widget child, {ThemeMode mode = ThemeMode.light}) => MaterialApp(
  theme: ThemeData(extensions: const [AppPalette.light]),
  darkTheme: ThemeData(
    brightness: Brightness.dark,
    extensions: const [AppPalette.dark],
  ),
  themeMode: mode,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('ExerciseCompletionSection', () {
    testWidgets('shows finished / required and the missing list', (
      tester,
    ) async {
      final gate = evaluateCareGate(
        prescriptions: [
          rx('r1', required: 3),
          rx('r2', type: 'heelSlide'),
        ],
        sessions: [session('r1'), session('r1')],
      );
      await tester.pumpWidget(host(ExerciseCompletionSection(gate: gate)));

      expect(find.text('Exercise completion'), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('Still missing'), findsOneWidget);
      expect(find.text('Knee Extension: 2 of 3 sessions'), findsOneWidget);
      expect(
        find.text('Heel Slides: no completion target set'),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    });

    testWidgets('unavailable and empty states', (tester) async {
      await tester.pumpWidget(
        host(const ExerciseCompletionSection(gate: null)),
      );
      expect(find.textContaining('Not available right now'), findsOneWidget);

      await tester.pumpWidget(
        host(
          ExerciseCompletionSection(
            gate: evaluateCareGate(prescriptions: [], sessions: []),
          ),
        ),
      );
      expect(find.text('No exercise program assigned yet.'), findsOneWidget);
    });
  });

  group('MedicalClearanceSection', () {
    testWidgets('cleared shows the physician, license, date and findings', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          MedicalClearanceSection(
            status: ClearanceStatus(
              kind: ClearanceStatusKind.cleared,
              record: clearedRecord,
              programChangedSinceClearance: true,
            ),
          ),
        ),
      );
      expect(find.text('Medical clearance'), findsOneWidget);
      expect(
        find.textContaining('Only your physician can clear you'),
        findsOneWidget,
      );
      expect(find.text('Cleared by your physician'), findsOneWidget);
      expect(find.text('Dr. Ana Reyes'), findsOneWidget);
      expect(find.text('PRC license no.'), findsOneWidget);
      expect(find.text('0123456'), findsOneWidget);
      expect(find.text('14 Nov 2026'), findsOneWidget);
      expect(
        find.text('Full knee range of motion, no pain on loading.'),
        findsOneWidget,
      );
      expect(
        find.text('Your program was updated after this clearance.'),
        findsOneWidget,
      );
    });

    testWidgets('ready for review never says cleared', (tester) async {
      await tester.pumpWidget(
        host(
          const MedicalClearanceSection(
            status: ClearanceStatus(kind: ClearanceStatusKind.readyForReview),
          ),
        ),
      );
      expect(find.text('Ready for physician assessment'), findsOneWidget);
      expect(find.text('Cleared by your physician'), findsNothing);
    });

    testWidgets('unavailable says not available yet, not cleared', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const MedicalClearanceSection(
            status: ClearanceStatus(kind: ClearanceStatusKind.unavailable),
          ),
        ),
      );
      expect(find.text('Not available yet'), findsOneWidget);
      expect(
        find.textContaining('does not mean you are cleared'),
        findsOneWidget,
      );
      expect(find.text('Cleared by your physician'), findsNothing);
    });

    testWidgets('not eligible lists what is missing', (tester) async {
      final gate = evaluateCareGate(
        prescriptions: [rx('r1', required: 4)],
        sessions: [session('r1')],
      );
      await tester.pumpWidget(
        host(
          MedicalClearanceSection(
            status: resolveClearance(gate: gate, records: const []),
          ),
        ),
      );
      expect(find.text('Not ready for assessment yet'), findsOneWidget);
      expect(find.text('• Knee Extension: 1 of 4 sessions'), findsOneWidget);
    });
  });

  group('ComplianceSection', () {
    testWidgets('shows accuracy and adherence with the disclaimer', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ComplianceSection(
            summary: ComplianceSummary(
              formAccuracy: 82.4,
              finishedSessions: 5,
              weekAdherence: 0.5,
            ),
          ),
        ),
      );
      expect(find.text('Compliance'), findsOneWidget);
      expect(
        find.text(
          'How well and how regularly you did your exercises. This is not '
          'a medical result.',
        ),
        findsOneWidget,
      );
      expect(find.text('82% (5 finished sessions)'), findsOneWidget);
      expect(find.text('50% of planned sessions'), findsOneWidget);
    });
  });

  group('PrecautionsSection', () {
    testWidgets(
      'shows precautions, restrictions, diet context and validation',
      (tester) async {
        await tester.pumpWidget(
          host(
            PrecautionsSection(
              result: ClinicalProfileResult.loaded(
                ClinicalProfile(
                  precautions: 'Avoid deep knee bends.',
                  lowTolerance: true,
                  toleranceNote: 'Gets dizzy after 5 minutes',
                  restrictedExercises: const {ExerciseType.wallSit},
                  nutritionFlags: const [NutritionFlag.renalDiet],
                  dietaryNotes: 'Low-salt meals.',
                  validatedByName: 'Dr. Cruz',
                  validatedAt: DateTime(2026, 11, 3),
                  nextReassessmentAt: DateTime(2026, 12, 1),
                ),
              ),
            ),
          ),
        );
        expect(find.text('Precautions from your clinician'), findsOneWidget);
        expect(find.text('Avoid deep knee bends.'), findsOneWidget);
        expect(find.text('Gets dizzy after 5 minutes'), findsOneWidget);
        expect(find.text('Wall Sit'), findsOneWidget);
        expect(find.text(PrecautionsSection.dietaryLabel), findsOneWidget);
        expect(find.text('Kidney (renal) diet'), findsOneWidget);
        expect(find.text('Low-salt meals.'), findsOneWidget);
        expect(
          find.text('Validated by Dr. Cruz on 3 Nov 2026'),
          findsOneWidget,
        );
        expect(find.text('Next reassessment: 1 Dec 2026'), findsOneWidget);
      },
    );

    testWidgets('unavailable and none-set states', (tester) async {
      await tester.pumpWidget(
        host(
          const PrecautionsSection(result: ClinicalProfileResult.unavailable()),
        ),
      );
      expect(find.textContaining('Not available yet'), findsOneWidget);

      await tester.pumpWidget(
        host(
          const PrecautionsSection(result: ClinicalProfileResult.loaded(null)),
        ),
      );
      expect(
        find.text('Your clinician has not added any precautions.'),
        findsOneWidget,
      );
    });
  });

  group('CarePlanScreen', () {
    Future<void> pumpScreen(
      WidgetTester tester,
      CarePlanSnapshot snapshot, {
      ThemeMode mode = ThemeMode.light,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppPalette.light]),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [AppPalette.dark],
          ),
          themeMode: mode,
          home: CarePlanScreen(
            key: ValueKey(mode), // fresh scroll position per theme
            loader: () async => snapshot,
            sessions: [session('r1')],
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the four sections in order, also in dark mode', (
      tester,
    ) async {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await pumpScreen(
          tester,
          CarePlanSnapshot(
            prescriptions: [rx('r1', required: 1)],
            profile: const ClinicalProfileResult.loaded(null),
            clearances: const [],
          ),
          mode: mode,
        );
        expect(find.text('Care plan & clearance'), findsOneWidget);
        // Program complete, no record: ready for assessment, never cleared.
        expect(find.text('Ready for physician assessment'), findsOneWidget);
        expect(find.text('Cleared by your physician'), findsNothing);

        final headings = [
          'Exercise completion',
          'Compliance',
          'Medical clearance',
          'Precautions from your clinician',
        ];
        for (final heading in headings) {
          await tester.scrollUntilVisible(find.text(heading), 100);
          expect(find.text(heading), findsOneWidget);
        }
      }
    });

    testWidgets('everything unavailable is shown as unavailable', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const CarePlanSnapshot(
          prescriptions: null,
          profile: ClinicalProfileResult.unavailable(),
          clearances: null,
        ),
      );
      await tester.scrollUntilVisible(find.text('Not available yet'), 100);
      expect(find.text('Not available yet'), findsOneWidget);
      expect(find.text('Cleared by your physician'), findsNothing);
    });

    testWidgets('pull to refresh reloads the data', (tester) async {
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppPalette.light]),
          home: CarePlanScreen(
            loader: () async {
              loads++;
              return const CarePlanSnapshot(
                prescriptions: [],
                profile: ClinicalProfileResult.loaded(null),
                clearances: [],
              );
            },
            sessions: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(loads, 1);
      await tester.fling(
        find.text('Exercise completion'),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(loads, 2);
    });
  });

  group('Exercise card clinician lock', () {
    late List<Route<dynamic>> pushed;

    Future<void> pumpCard(WidgetTester tester, ClinicalProfile profile) async {
      pushed = [];
      final config = availableExercises.firstWhere(
        (c) => c.type == ExerciseType.kneeExtension,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppPalette.light]),
          navigatorObservers: [_RecordingObserver(pushed)],
          home: Scaffold(
            body: ListView(
              children: [
                AnimatedExerciseCard(
                  index: 0,
                  config: config,
                  clinical: profile,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      pushed.clear(); // drop the home route
    }

    testWidgets('a restricted exercise is locked and never opens the camera', (
      tester,
    ) async {
      await pumpCard(
        tester,
        const ClinicalProfile(
          restrictedExercises: {ExerciseType.kneeExtension},
        ),
      );
      expect(find.text('Paused by your clinician'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsWidgets);

      await tester.tap(find.text('Knee Extension'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Message your therapist'), findsOneWidget);
      expect(pushed.whereType<MaterialPageRoute<dynamic>>(), isEmpty);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(pushed.whereType<MaterialPageRoute<dynamic>>(), isEmpty);
    });

    testWidgets('low tolerance asks first; Cancel does not start', (
      tester,
    ) async {
      await pumpCard(
        tester,
        const ClinicalProfile(
          lowTolerance: true,
          toleranceNote: 'Gets dizzy after 5 minutes',
        ),
      );
      expect(find.text('Paused by your clinician'), findsNothing);

      await tester.tap(find.text('Knee Extension'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Your clinician noted low exercise tolerance: Gets dizzy after 5 '
          'minutes. Stop if pain increases.',
        ),
        findsOneWidget,
      );
      expect(find.text('Start'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(pushed.whereType<MaterialPageRoute<dynamic>>(), isEmpty);
    });
  });
}

class _RecordingObserver extends NavigatorObserver {
  _RecordingObserver(this.routes);

  final List<Route<dynamic>> routes;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }
}
