// Unit tests for lib/services/exercise_geometry.dart with synthetic ML Kit
// landmarks, in image pixels (y grows downward).
//
// Two base bodies are used:
//   - FRONT view: standing, facing the camera, left/right side by side.
//   - SIDE view: standing side-on, both sides of the body overlapping.
// Each test moves a few landmarks to make the position it checks.

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:rehabplus/models/exercise_model.dart';
import 'package:rehabplus/services/exercise_geometry.dart';
import 'package:rehabplus/services/form_checker.dart';

typedef Xy = (double, double);

const Map<PoseLandmarkType, Xy> _front = {
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

/// Side-on body: shoulder (200,100), hip (200,300), knee (200,400),
/// ankle (200,500), arms hanging. Left and right overlap.
final Map<PoseLandmarkType, Xy> _side = {
  for (final side in ['left', 'right']) ...{
    _type('${side}Shoulder'): (200, 100),
    _type('${side}Elbow'): (200, 200),
    _type('${side}Wrist'): (200, 280),
    _type('${side}Hip'): (200, 300),
    _type('${side}Knee'): (200, 400),
    _type('${side}Ankle'): (200, 500),
  },
};

PoseLandmarkType _type(String name) =>
    PoseLandmarkType.values.firstWhere((t) => t.name == name);

/// All 33 landmarks: [base] moved by [moved]; anything else sits on the head.
Map<PoseLandmarkType, PoseLandmark> _pose(
  Map<PoseLandmarkType, Xy> base, [
  Map<PoseLandmarkType, Xy> moved = const {},
]) {
  return {
    for (final type in PoseLandmarkType.values)
      type: PoseLandmark(
        type: type,
        x: (moved[type] ?? base[type] ?? (200, 50)).$1,
        y: (moved[type] ?? base[type] ?? (200, 50)).$2,
        z: 0,
        likelihood: 0.95,
      ),
  };
}

ExerciseConfig _exercise(ExerciseType type) =>
    availableExercises.firstWhere((e) => e.type == type);

RepReading _read(ExerciseType type, Map<PoseLandmarkType, PoseLandmark> lm) {
  final reading = ExerciseGeometry.readRep(_exercise(type), lm);
  expect(reading, isNotNull, reason: 'landmarks were all present');
  return reading!;
}

Set<FormIssueCode> _faults(
  ExerciseType type,
  Map<PoseLandmarkType, PoseLandmark> lm,
) => ExerciseGeometry.extraFaults(
  type,
  lm,
  minLikelihood: 0.5,
).map((issue) => issue.code).toSet();

void main() {
  test('every new exercise is in the catalog and handled here', () {
    for (final type in ExerciseGeometry.handledTypes) {
      expect(
        availableExercises.where((e) => e.type == type),
        hasLength(1),
        reason: '$type needs exactly one ExerciseConfig',
      );
      expect(_exercise(type).isHold, isFalse);
    }
  });

  test('missing landmarks give no reading instead of a wrong angle', () {
    for (final type in ExerciseGeometry.handledTypes) {
      expect(ExerciseGeometry.readRep(_exercise(type), const {}), isNull);
    }
  });

  test('a genuine 0 deg reading is never reported as 0.0 (the screen '
      'treats 0.0 as "could not measure")', () {
    // Side view, arm hanging exactly along the body: hip-shoulder-wrist = 0.
    final reading = _read(ExerciseType.overheadRaise, _pose(_side));
    expect(reading.angle, greaterThan(0));
    expect(reading.atTarget, isFalse);
  });

  group('jointAngle (shared by geometry, form checker and the screen)', () {
    PoseLandmark at(double x, double y) => PoseLandmark(
      type: PoseLandmarkType.nose,
      x: x,
      y: y,
      z: 0,
      likelihood: 1,
    );

    test('straight limb is 180, right angle is 90', () {
      expect(
        ExerciseGeometry.jointAngle(at(0, 0), at(0, 100), at(0, 200)),
        closeTo(180, 1e-9),
      );
      expect(
        ExerciseGeometry.jointAngle(at(0, 0), at(0, 100), at(100, 100)),
        closeTo(90, 1e-9),
      );
    });

    test('never goes above 180, whichever way the limb bends', () {
      // 45 degrees, bent to the left and to the right of the joint.
      expect(
        ExerciseGeometry.jointAngle(at(0, 0), at(0, 100), at(100, 0)),
        closeTo(45, 1e-9),
      );
      expect(
        ExerciseGeometry.jointAngle(at(0, 0), at(0, 100), at(-100, 0)),
        closeTo(45, 1e-9),
      );
    });
  });

  group('Mini Squat', () {
    const type = ExerciseType.miniSquat;

    test('standing is not the target, a ~45 deg knee bend is', () {
      expect(_read(type, _pose(_side)).atTarget, isFalse);
      final bent = _pose(_side, {
        PoseLandmarkType.leftKnee: (245, 400),
        PoseLandmarkType.rightKnee: (245, 400),
      });
      final reading = _read(type, bent);
      expect(reading.angle, closeTo(131.5, 1));
      expect(reading.atTarget, isTrue);
      expect(_faults(type, bent), isEmpty);
    });

    test('squatting much deeper than a mini squat is a fault', () {
      final deep = _pose(_side, {
        PoseLandmarkType.leftKnee: (300, 400),
        PoseLandmarkType.rightKnee: (300, 400),
      });
      expect(_faults(type, deep), contains(FormIssueCode.shortRange));
    });

    test('knees caving inward (front view) is a fault', () {
      final caving = _pose(_front, {
        PoseLandmarkType.leftAnkle: (150, 500),
        PoseLandmarkType.rightAnkle: (250, 500),
        PoseLandmarkType.leftKnee: (190, 400),
        PoseLandmarkType.rightKnee: (210, 400),
      });
      expect(_faults(type, caving), contains(FormIssueCode.kneesIn));
    });

    test('knees over the toes with the same stance is fine', () {
      final good = _pose(_front, {
        PoseLandmarkType.leftAnkle: (150, 500),
        PoseLandmarkType.rightAnkle: (250, 500),
        PoseLandmarkType.leftKnee: (150, 400),
        PoseLandmarkType.rightKnee: (250, 400),
      });
      expect(_faults(type, good), isNot(contains(FormIssueCode.kneesIn)));
    });
  });

  group('Standing Hip Abduction', () {
    const type = ExerciseType.hipAbduction;

    test('feet together is rest, the leg ~35 deg out is the target', () {
      expect(_read(type, _pose(_front)).angle, lessThan(5));
      final lifted = _pose(_front, {
        PoseLandmarkType.leftKnee: (128, 382),
        PoseLandmarkType.leftAnkle: (71, 464),
      });
      final reading = _read(type, lifted);
      expect(reading.angle, inInclusiveRange(30, 40));
      expect(reading.atTarget, isTrue);
      expect(_faults(type, lifted), isEmpty);
    });

    test('a leg crossing inward does not count as a lift', () {
      final crossed = _pose(_front, {PoseLandmarkType.leftKnee: (240, 395)});
      expect(_read(type, crossed).angle, lessThan(5));
    });

    test('a bent working knee and leaning sideways are faults', () {
      final cheating = _pose(_front, {
        PoseLandmarkType.leftKnee: (128, 382),
        PoseLandmarkType.leftAnkle: (128, 480), // shin hangs down: knee bent
        PoseLandmarkType.leftShoulder: (240, 100),
        PoseLandmarkType.rightShoulder: (280, 100),
      });
      expect(
        _faults(type, cheating),
        containsAll([FormIssueCode.kneeBent, FormIssueCode.trunkLean]),
      );
    });
  });

  group('Standing Hamstring Curl', () {
    const type = ExerciseType.hamstringCurl;

    test('a heel curled to 90 deg reaches the target, thigh kept down', () {
      expect(_read(type, _pose(_side)).atTarget, isFalse);
      final curled = _pose(_side, {PoseLandmarkType.leftAnkle: (100, 400)});
      final reading = _read(type, curled);
      expect(reading.angle, closeTo(90, 1));
      expect(reading.atTarget, isTrue);
      expect(_faults(type, curled), isEmpty);
    });

    test('swinging the thigh forward is a fault', () {
      final swung = _pose(_side, {
        PoseLandmarkType.leftKnee: (280, 360),
        PoseLandmarkType.leftAnkle: (200, 400),
      });
      expect(_faults(type, swung), contains(FormIssueCode.thighDrift));
    });

    test('bending the standing leg is a fault', () {
      final both = _pose(_side, {
        PoseLandmarkType.leftAnkle: (100, 400), // working leg curled
        PoseLandmarkType.rightKnee: (240, 400), // standing knee bent
      });
      expect(_faults(type, both), contains(FormIssueCode.kneeBent));
    });
  });

  group('Marching in Place', () {
    const type = ExerciseType.marching;

    test('a knee lifted to hip height is the target', () {
      expect(_read(type, _pose(_side)).atTarget, isFalse);
      final lifted = _pose(_side, {
        PoseLandmarkType.leftKnee: (290, 300),
        PoseLandmarkType.leftAnkle: (290, 400),
      });
      final reading = _read(type, lifted);
      expect(reading.angle, closeTo(90, 1));
      expect(reading.atTarget, isTrue);
      expect(_faults(type, lifted), isEmpty);
    });

    test('either leg counts, so alternating legs both count', () {
      final rightLifted = _pose(_side, {
        PoseLandmarkType.rightKnee: (290, 300),
      });
      expect(_read(type, rightLifted).atTarget, isTrue);
    });

    test('a bent standing leg is a fault', () {
      final sagging = _pose(_side, {
        PoseLandmarkType.leftKnee: (290, 300),
        PoseLandmarkType.rightKnee: (250, 400),
      });
      expect(_faults(type, sagging), contains(FormIssueCode.kneeBent));
    });
  });

  group('Overhead Arm Raise', () {
    const type = ExerciseType.overheadRaise;

    test('arm by the side is rest, arm beside the ear is the target', () {
      expect(_read(type, _pose(_side)).atTarget, isFalse);
      final raised = _pose(_side, {
        PoseLandmarkType.leftElbow: (215, 20),
        PoseLandmarkType.leftWrist: (230, -60),
      });
      final reading = _read(type, raised);
      expect(reading.angle, greaterThan(150));
      expect(reading.atTarget, isTrue);
      expect(_faults(type, raised), isEmpty);
    });

    test('leaning back to get the arm up is a fault', () {
      final arched = _pose(_side, {
        PoseLandmarkType.leftShoulder: (120, 100),
        PoseLandmarkType.rightShoulder: (120, 100),
      });
      expect(_faults(type, arched), contains(FormIssueCode.trunkLean));
    });
  });

  test('every new exercise has its own "not far enough" hint', () {
    for (final type in ExerciseGeometry.handledTypes) {
      final hint = ExerciseGeometry.rangeFeedback(type);
      expect(hint.message, isNot('Move through the full range.'));
      expect(hint.landmarks, isNotEmpty);
    }
  });

  group('Knee Extension leg detection (seated, side-on)', () {
    // Seated side-on: shoulder above hip, thigh horizontal, shin hanging.
    const seated = <PoseLandmarkType, Xy>{
      PoseLandmarkType.leftShoulder: (200, 100),
      PoseLandmarkType.rightShoulder: (200, 100),
      PoseLandmarkType.leftHip: (200, 300),
      PoseLandmarkType.rightHip: (200, 300),
      PoseLandmarkType.leftKnee: (300, 300),
      PoseLandmarkType.rightKnee: (300, 300),
      PoseLandmarkType.leftAnkle: (300, 400),
      PoseLandmarkType.rightAnkle: (300, 400),
    };
    const extendedAnkle = (390.0, 280.0); // knee ~167 deg

    Map<PoseLandmarkType, PoseLandmark> pose(
      Map<PoseLandmarkType, Xy> moved, {
      Set<PoseLandmarkType> unsure = const {},
    }) => {
      for (final type in PoseLandmarkType.values)
        type: PoseLandmark(
          type: type,
          x: (moved[type] ?? seated[type] ?? (200, 50)).$1,
          y: (moved[type] ?? seated[type] ?? (200, 50)).$2,
          z: 0,
          likelihood: unsure.contains(type) ? 0.2 : 0.95,
        ),
    };

    ({double working, double? resting}) legs(
      Map<PoseLandmarkType, PoseLandmark> lm,
    ) => ExerciseGeometry.kneeExtensionLegs(lm, minLikelihood: 0.5)!;

    test('hidden far leg drawn on top of the lifted one: counts '
        '(this was the "170 deg but no rep" bug)', () {
      final result = legs(
        pose({
          PoseLandmarkType.leftAnkle: extendedAnkle,
          PoseLandmarkType.rightAnkle: extendedAnkle,
        }),
      );
      expect(result.working, greaterThan(160));
      expect(result.resting, isNull, reason: 'overlapping legs are one leg');
    });

    test('far leg guessed with low confidence is ignored', () {
      final result = legs(
        pose(
          {
            PoseLandmarkType.leftAnkle: extendedAnkle,
            PoseLandmarkType.rightAnkle: (395, 290), // garbage guess
          },
          unsure: {PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle},
        ),
      );
      expect(result.working, greaterThan(160));
      expect(result.resting, isNull);
    });

    test('a clearly visible, bent other leg is reported as resting', () {
      final result = legs(pose({PoseLandmarkType.leftAnkle: extendedAnkle}));
      expect(result.working, greaterThan(160));
      expect(result.resting, closeTo(90, 1));
    });

    test('a clearly visible other leg that is also straight is reported '
        '(so the screen can still block lifting both legs)', () {
      final result = legs(
        pose({
          PoseLandmarkType.leftAnkle: extendedAnkle,
          PoseLandmarkType.rightAnkle: (385, 345),
        }),
      );
      expect(result.resting, greaterThan(120));
    });

    test('resting (both legs down) reads about 90 deg', () {
      expect(legs(pose(const {})).working, closeTo(90, 1));
    });
  });
}
