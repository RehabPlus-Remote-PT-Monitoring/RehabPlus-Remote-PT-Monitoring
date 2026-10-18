// Unit tests for FormChecker with synthetic ML Kit landmarks.
//
// The body below is a person standing upright, facing the camera, in image
// pixels (y grows downward). Torso length (shoulder-mid to hip-mid) is
// 200 px, which is the yardstick all motion thresholds are measured in.

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:rehabplus/core/diagnostic_logger.dart';
import 'package:rehabplus/models/exercise_model.dart';
import 'package:rehabplus/services/form_checker.dart';

const Map<PoseLandmarkType, (double, double)> _standing = {
  PoseLandmarkType.leftShoulder: (180, 100),
  PoseLandmarkType.rightShoulder: (220, 100),
  PoseLandmarkType.leftElbow: (180, 200),
  PoseLandmarkType.rightElbow: (220, 200),
  PoseLandmarkType.leftWrist: (180, 280),
  PoseLandmarkType.rightWrist: (220, 280),
  PoseLandmarkType.leftHip: (185, 300),
  PoseLandmarkType.rightHip: (215, 300),
  PoseLandmarkType.leftKnee: (185, 400),
  PoseLandmarkType.rightKnee: (215, 400),
  PoseLandmarkType.leftAnkle: (185, 500),
  PoseLandmarkType.rightAnkle: (215, 500),
};

/// All 33 landmarks; the ones in [_standing] (optionally moved by [moved])
/// are where a standing person's would be, the rest sit on the head.
Map<PoseLandmarkType, PoseLandmark> _pose({
  Map<PoseLandmarkType, (double, double)> moved = const {},
  Set<PoseLandmarkType> hidden = const {},
}) {
  return {
    for (final type in PoseLandmarkType.values)
      type: PoseLandmark(
        type: type,
        x: (moved[type] ?? _standing[type] ?? (200, 50)).$1,
        y: (moved[type] ?? _standing[type] ?? (200, 50)).$2,
        z: 0,
        likelihood: hidden.contains(type) ? 0.1 : 0.95,
      ),
  };
}

ExerciseConfig _exercise(ExerciseType type) =>
    availableExercises.firstWhere((e) => e.type == type);

/// Info-or-higher FormChecker events logged since the buffer was cleared.
List<DiagnosticEvent> _checkerEvents() => DiagnosticLogger.I
    .recent(limit: DiagnosticLogger.bufferCapacity)
    .where((e) => e.tag == 'FormChecker')
    .toList();

void main() {
  final start = DateTime(2026, 10, 18, 9);
  DateTime frame(int i) => start.add(Duration(milliseconds: 66 * i));

  setUp(() {
    DiagnosticLogger.I.setSink(null); // keep test output quiet
    DiagnosticLogger.I.clearBuffer();
  });

  test('a still, upright body is ok and logs nothing per frame', () {
    final checker = FormChecker(
      _exercise(ExerciseType.bicepCurl),
      thresholds: FormThresholds.standard,
    );
    FormResult result = FormResult.ok;
    for (var i = 0; i < 30; i++) {
      result = checker.evaluate(_pose(), now: frame(i));
    }
    expect(result.isOk, isTrue);

    final events = _checkerEvents();
    expect(events.map((e) => e.message), ['Initialized']);
    expect(events.single.data?['thresholds'], 'standard');
  });

  test('hidden required landmarks -> not in frame, logged once with '
      'the missing body parts', () {
    final checker = FormChecker(
      _exercise(ExerciseType.bicepCurl),
      thresholds: FormThresholds.standard,
    );
    late FormResult result;
    for (var i = 0; i < 10; i++) {
      result = checker.evaluate(
        _pose(
          hidden: {PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist},
        ),
        now: frame(i),
      );
    }
    expect(result.isNotInFrame, isTrue);
    expect(result.primary?.code, FormIssueCode.notInFrame);

    final hiddenEvents = _checkerEvents()
        .where((e) => e.message == 'Required landmarks not visible')
        .toList();
    expect(hiddenEvents, hasLength(1));
    expect(hiddenEvents.single.data?['missing'], ['wrists']);
  });

  test('one side of each pair is enough (side-on camera)', () {
    final checker = FormChecker(
      _exercise(ExerciseType.bicepCurl),
      thresholds: FormThresholds.standard,
    );
    final result = checker.evaluate(
      _pose(hidden: {PoseLandmarkType.leftWrist, PoseLandmarkType.leftElbow}),
      now: frame(0),
    );
    expect(result.isNotInFrame, isFalse);
  });

  test('no pose: not in frame, logged once however many frames', () {
    final checker = FormChecker(_exercise(ExerciseType.sideRaise));
    for (var i = 0; i < 10; i++) {
      expect(checker.evaluateNoPose().isNotInFrame, isTrue);
    }
    final noPose = _checkerEvents()
        .where((e) => e.message == 'No pose detected')
        .toList();
    expect(noPose, hasLength(1));
  });

  test('stepping feet during a side raise -> legsMoving after confirm', () {
    final checker = FormChecker(
      _exercise(ExerciseType.sideRaise),
      thresholds: FormThresholds.standard,
    );
    FormResult result = FormResult.ok;
    for (var i = 0; i < 20; i++) {
      // Right foot shuffles 120 px left and right every frame. Smoothing
      // (EMA 0.6) shrinks that to ~100 px of wander = 0.5 torso, over the
      // 0.40 limit of FormThresholds.standard.
      final dx = i.isEven ? -120.0 : 120.0;
      result = checker.evaluate(
        _pose(moved: {PoseLandmarkType.rightAnkle: (215 + dx, 500)}),
        now: frame(i),
      );
    }
    expect(result.isWrong, isTrue);
    expect(result.issues.map((i) => i.code), contains(FormIssueCode.legsMoving));
    expect(result.flagged, contains(PoseLandmarkType.rightAnkle));
  });

  test('a fault must persist for the confirm time before it is shown', () {
    final checker = FormChecker(
      _exercise(ExerciseType.kneeExtension),
      thresholds: FormThresholds.standard,
    );
    // Both legs straight: "keep your other leg bent" for kneeExtension. The
    // ankles are spread so the legs are clearly two separate legs (the
    // rule ignores overlapping legs, see ExerciseGeometry.anklesApart).
    final spread = {
      PoseLandmarkType.leftAnkle: (140.0, 500.0),
      PoseLandmarkType.rightAnkle: (260.0, 500.0),
    };
    final first = checker.evaluate(_pose(moved: spread), now: frame(0));
    expect(first.isOk, isTrue, reason: 'not confirmed yet (200 ms)');

    FormResult result = first;
    for (var i = 1; i < 10; i++) {
      result = checker.evaluate(_pose(moved: spread), now: frame(i));
    }
    expect(result.isWrong, isTrue);
    expect(result.primary?.code, FormIssueCode.otherLeg);
  });

  test('FormResult.plus puts a one-off issue first and keeps not-in-frame', () {
    const flash = FormIssue(
      code: FormIssueCode.tooFast,
      message: 'Rep not counted.',
      landmarks: <PoseLandmarkType>{},
    );
    final combined = FormResult.ok.plus(flash);
    expect(combined.isWrong, isTrue);
    expect(combined.primary, same(flash));

    final checker = FormChecker(_exercise(ExerciseType.sideRaise));
    final notInFrame = checker.evaluateNoPose();
    expect(notInFrame.plus(flash), same(notInFrame));
  });
}
