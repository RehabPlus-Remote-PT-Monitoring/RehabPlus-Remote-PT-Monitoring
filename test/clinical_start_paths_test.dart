// Every Start button outside the exercise card (the "How to do it" sheet and
// Today's plan) must honour the clinician's safeguards too: a restricted
// exercise never opens the camera screen, and low tolerance asks first.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rehabplus/core/diagnostic_logger.dart';
import 'package:rehabplus/models/clinical_profile.dart';
import 'package:rehabplus/models/exercise_model.dart';
import 'package:rehabplus/screens/pose_detector_screen.dart';
import 'package:rehabplus/services/app_provider.dart';
import 'package:rehabplus/widgets/exercise_demo_sheet.dart';
import 'package:rehabplus/widgets/today_checklist_sheet.dart';

final _knee = availableExercises.firstWhere(
  (c) => c.type == ExerciseType.kneeExtension,
);

const _restricted = ClinicalProfile(
  restrictedExercises: {ExerciseType.kneeExtension},
);

const _lowTolerance = ClinicalProfile(
  lowTolerance: true,
  toleranceNote: 'Gets dizzy after 5 minutes',
);

bool _logged(String message) =>
    DiagnosticLogger.I.recent(limit: 200).any((e) => e.message == message);

/// A page with one button that opens [openSheet]. Tall surface so the whole
/// sheet is on screen.
Future<void> _pumpOpener(
  WidgetTester tester,
  void Function(BuildContext) openSheet,
) async {
  tester.view.physicalSize = const Size(500, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppProvider>(
      create: (_) => AppProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    DiagnosticLogger.I.setSink((_) {});
    DiagnosticLogger.I.clearBuffer();
  });

  group('How to do it sheet', () {
    testWidgets('a restricted exercise shows the dialog and keeps the sheet', (
      tester,
    ) async {
      await _pumpOpener(
        tester,
        (c) => ExerciseDemoSheet.show(c, _knee, clinical: _restricted),
      );
      await tester.tap(find.text('Start exercise'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Paused by your clinician'), findsOneWidget);
      expect(find.byType(PoseDetectorScreen), findsNothing);
      expect(_logged('Restricted exercise blocked'), isTrue);

      // OK closes the dialog; the sheet is still there and can be tried again.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(ExerciseDemoSheet), findsOneWidget);
      await tester.tap(find.text('Start exercise'));
      await tester.pumpAndSettle();
      expect(find.text('Paused by your clinician'), findsOneWidget);
    });

    testWidgets('low tolerance: Cancel does not start the exercise', (
      tester,
    ) async {
      await _pumpOpener(
        tester,
        (c) => ExerciseDemoSheet.show(c, _knee, clinical: _lowTolerance),
      );
      await tester.tap(find.text('Start exercise'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Gets dizzy after 5 minutes'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(PoseDetectorScreen), findsNothing);
      expect(find.byType(ExerciseDemoSheet), findsOneWidget);
    });
  });

  group("Today's plan sheet", () {
    testWidgets('a restricted exercise shows the dialog and starts nothing', (
      tester,
    ) async {
      await _pumpOpener(
        tester,
        (c) => TodayChecklistSheet.show(c, [_knee], clinical: _restricted),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(find.text('Paused by your clinician'), findsOneWidget);
      expect(find.byType(PoseDetectorScreen), findsNothing);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(TodayChecklistSheet), findsOneWidget);
    });

    testWidgets('low tolerance: Cancel keeps the sheet and starts nothing', (
      tester,
    ) async {
      await _pumpOpener(
        tester,
        (c) => TodayChecklistSheet.show(c, [_knee], clinical: _lowTolerance),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(PoseDetectorScreen), findsNothing);
      expect(find.byType(TodayChecklistSheet), findsOneWidget);
      expect(_logged('Low tolerance caution'), isTrue);
    });
  });
}
