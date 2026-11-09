// Widget tests for the exercise screen's overlay widgets
// (lib/widgets/exercise_*.dart). The camera screen itself needs a real
// camera and ML Kit, so each overlay is tested on its own here, at a 360 dp
// wide phone and at 1.6x text scale (the largest the app is checked at).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/widgets/exercise_controls.dart';
import 'package:rehabplus/widgets/exercise_hints.dart';
import 'package:rehabplus/widgets/exercise_range_gauge.dart';
import 'package:rehabplus/widgets/exercise_session_summary.dart';
import 'package:rehabplus/widgets/exercise_standing_guide.dart';

/// Pumps [child] on a 360 dp wide phone with dark camera-like background.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double textScale = 1.0,
  double width = 360,
  double height = 760,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Padding(
            // Same insets as the screen's bottom card (20 + 16 padding).
            padding: const EdgeInsets.all(36),
            child: Center(child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ExerciseRangeGauge', () {
    testWidgets('marker moves with the angle, direction-aware', (tester) async {
      Future<double> markerX(double angle) async {
        await _pump(
          tester,
          SizedBox(
            width: 200,
            child: ExerciseRangeGauge(
              angle: angle,
              restAngle: 170,
              targetAngle: 70,
              isCorrect: true,
            ),
          ),
        );
        return tester.getCenter(find.byKey(ExerciseRangeGauge.markerKey)).dx;
      }

      final atRest = await markerX(170);
      final halfway = await markerX(120);
      final atTarget = await markerX(70);
      expect(halfway, greaterThan(atRest));
      expect(atTarget, greaterThan(halfway));
    });

    testWidgets('no marker while the angle is unknown', (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: 200,
          child: ExerciseRangeGauge(
            angle: null,
            restAngle: 20,
            targetAngle: 90,
            isCorrect: true,
          ),
        ),
      );
      expect(find.byKey(ExerciseRangeGauge.markerKey), findsNothing);
      expect(find.text('Rest'), findsOneWidget);
      expect(find.text('Target'), findsOneWidget);
    });

    testWidgets('fits a narrow slot at 1.6x text', (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: 110, // what is left beside "10 / 10" at 1.6x
          child: ExerciseRangeGauge(
            angle: 60,
            restAngle: 20,
            targetAngle: 90,
            isCorrect: false,
          ),
        ),
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ExerciseSessionSummary', () {
    testWidgets('shows accuracy and one dot per attempt', (tester) async {
      await _pump(
        tester,
        const ExerciseSessionSummary(scores: [1, 1, 0, 1], unit: 'reps'),
      );
      expect(find.text('75%'), findsOneWidget);
      expect(find.textContaining('3 of 4'), findsOneWidget);
      final dots = tester.widgetList<ExerciseAttemptDot>(
        find.byType(ExerciseAttemptDot),
      );
      expect(dots.length, 4);
      final colors = [for (final d in dots) d.color];
      expect(colors[0], ExerciseSessionSummary.countedColor);
      expect(colors[2], ExerciseSessionSummary.missedColor);
    });

    testWidgets('nothing attempted: no percent, no dots', (tester) async {
      await _pump(
        tester,
        const ExerciseSessionSummary(scores: [], unit: 'reps'),
      );
      expect(find.textContaining('%'), findsNothing);
      expect(find.byType(ExerciseAttemptDot), findsNothing);
    });

    testWidgets('many attempts wrap without overflow at 1.6x', (tester) async {
      await _pump(
        tester,
        SizedBox(
          width: 240, // roughly an AlertDialog's content width on 360 dp
          child: ExerciseSessionSummary(
            scores: [for (var i = 0; i < 40; i++) i.isEven ? 1.0 : 0.0],
            unit: 'holds',
          ),
        ),
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ExerciseAttemptDot), findsNWidgets(40));
    });
  });

  group('ExerciseSessionControls and paused overlay', () {
    testWidgets('pause and end buttons call back', (tester) async {
      var paused = 0;
      var ended = 0;
      await _pump(
        tester,
        ExerciseSessionControls(
          canPause: true,
          onPause: () => paused++,
          onEnd: () => ended++,
        ),
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Pause'));
      await tester.tap(find.text('End'));
      expect(paused, 1);
      expect(ended, 1);
    });

    testWidgets('pause is disabled when it cannot be used', (tester) async {
      var paused = 0;
      await _pump(
        tester,
        ExerciseSessionControls(
          canPause: false,
          onPause: () => paused++,
          onEnd: () {},
        ),
      );
      await tester.tap(find.text('Pause'));
      expect(paused, 0);
    });

    testWidgets('paused overlay offers resume and end', (tester) async {
      var resumed = 0;
      var ended = 0;
      await _pump(
        tester,
        SizedBox.expand(
          child: ExercisePausedOverlay(
            onResume: () => resumed++,
            onEnd: () => ended++,
          ),
        ),
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Paused'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      await tester.tap(find.text('End session'));
      expect(resumed, 1);
      expect(ended, 1);
    });
  });

  group('hints', () {
    testWidgets('hint banner and tempo cue fit at 1.6x', (tester) async {
      await _pump(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExerciseHintBanner(
              icon: Icons.open_with,
              text: 'Step back a little so the camera can see all of you.',
            ),
            ExerciseTempoCue(text: 'Lower slowly...'),
          ],
        ),
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Lower slowly...'), findsOneWidget);
    });

    testWidgets('standing guide draws with its caption', (tester) async {
      await _pump(
        tester,
        const SizedBox.expand(
          child: ExerciseStandingGuide(
            caption: 'Stand inside the outline, facing the camera.',
          ),
        ),
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.textContaining('outline'), findsOneWidget);
    });

    testWidgets('standing guide without caption', (tester) async {
      await _pump(
        tester,
        const SizedBox.expand(child: ExerciseStandingGuide()),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
