// Pure helpers behind the exercise screen's patient-facing feedback
// (lib/services/exercise_feedback.dart).

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:rehabplus/models/exercise_model.dart';
import 'package:rehabplus/services/exercise_feedback.dart';
import 'package:rehabplus/services/form_checker.dart';

/// Landmark map with the given points, all confidently seen unless
/// [likelihood] says otherwise.
Map<PoseLandmarkType, PoseLandmark> _pose(
  Map<PoseLandmarkType, Offset> points, {
  double likelihood = 0.9,
}) => {
  for (final e in points.entries)
    e.key: PoseLandmark(
      type: e.key,
      x: e.value.dx,
      y: e.value.dy,
      z: 0,
      likelihood: likelihood,
    ),
};

/// A standing body from [top] (nose) to [bottom] (ankles), centred at x=200.
Map<PoseLandmarkType, PoseLandmark> _body(double top, double bottom) {
  final h = bottom - top;
  return _pose({
    PoseLandmarkType.nose: Offset(200, top),
    PoseLandmarkType.leftShoulder: Offset(180, top + h * 0.2),
    PoseLandmarkType.rightShoulder: Offset(220, top + h * 0.2),
    PoseLandmarkType.leftHip: Offset(185, top + h * 0.55),
    PoseLandmarkType.rightHip: Offset(215, top + h * 0.55),
    PoseLandmarkType.leftAnkle: Offset(185, bottom),
    PoseLandmarkType.rightAnkle: Offset(215, bottom),
  });
}

void main() {
  group('formIssueExplanation', () {
    test('every issue code has a plain sentence (exhaustive)', () {
      final seen = <String>{};
      for (final code in FormIssueCode.values) {
        final text = formIssueExplanation(code);
        expect(text.trim(), isNotEmpty, reason: code.name);
        expect(text, isNot(contains(code.name)), reason: code.name);
        expect(text.endsWith('.'), isTrue, reason: '$code: "$text"');
        // No camelCase identifiers leaking through.
        expect(RegExp(r'[a-z][A-Z]').hasMatch(text), isFalse, reason: text);
        expect(seen.add(text), isTrue, reason: 'duplicate text for $code');
      }
    });

    test('elbow drift is explained in everyday words', () {
      expect(formIssueExplanation(FormIssueCode.elbowDrift), contains('elbow'));
    });
  });

  group('whyRedSummary', () {
    test('null when nothing is wrong', () {
      expect(whyRedSummary(const []), isNull);
    });

    test('one code gives its sentence', () {
      expect(
        whyRedSummary(const [FormIssueCode.tooFast]),
        formIssueExplanation(FormIssueCode.tooFast),
      );
    });

    test('duplicates are dropped and at most two reasons are shown', () {
      final text = whyRedSummary(const [
        FormIssueCode.elbowDrift,
        FormIssueCode.elbowDrift,
        FormIssueCode.trunkLean,
        FormIssueCode.bodySway,
      ])!;
      expect(
        text,
        '${formIssueExplanation(FormIssueCode.elbowDrift)} '
        '${formIssueExplanation(FormIssueCode.trunkLean)}',
      );
    });
  });

  group('RangeGaugeScale', () {
    test('increasing range: rest is 0, target sits at targetStart', () {
      const g = RangeGaugeScale(restAngle: 20, targetAngle: 90);
      expect(g.position(20), 0.0);
      expect(g.position(90), closeTo(g.targetStart, 1e-9));
      expect(g.position(55), closeTo(g.targetStart / 2, 1e-9));
      expect(g.targetStart, greaterThan(0.5));
      expect(g.targetStart, lessThan(1.0));
    });

    test('decreasing range (curl: 170 rest, 70 target) is direction-aware', () {
      const g = RangeGaugeScale(restAngle: 170, targetAngle: 70);
      expect(g.position(170), 0.0);
      expect(g.position(70), closeTo(g.targetStart, 1e-9));
      expect(g.position(120), closeTo(g.targetStart / 2, 1e-9));
    });

    test('clamped to 0..1 both ways', () {
      const g = RangeGaugeScale(restAngle: 170, targetAngle: 70);
      expect(g.position(200), 0.0); // further than rest
      expect(g.position(0.5), 1.0); // far past target
    });

    test('unknown or degenerate input gives no marker', () {
      const g = RangeGaugeScale(restAngle: 90, targetAngle: 90);
      expect(g.position(90), isNull);
      const ok = RangeGaugeScale(restAngle: 20, targetAngle: 90);
      expect(ok.position(double.nan), isNull);
    });

    test('isInTarget follows the direction', () {
      const up = RangeGaugeScale(restAngle: 20, targetAngle: 90);
      expect(up.isInTarget(95), isTrue);
      expect(up.isInTarget(80), isFalse);
      const down = RangeGaugeScale(restAngle: 170, targetAngle: 70);
      expect(down.isInTarget(60), isTrue);
      expect(down.isInTarget(80), isFalse);
    });
  });

  group('framingHintFor', () {
    const frame = Size(400, 800);

    test('body of comfortable size is ok', () {
      expect(framingHintFor(_body(150, 650), frame), FramingHint.ok);
    });

    test('body filling the frame is too close', () {
      expect(framingHintFor(_body(5, 795), frame), FramingHint.tooClose);
    });

    test('body touching top and bottom edges is too close', () {
      // 0.945 of the height, but cut off at both edges.
      expect(framingHintFor(_body(22, 778), frame), FramingHint.tooClose);
    });

    test('small body is too far', () {
      expect(framingHintFor(_body(350, 550), frame), FramingHint.tooFar);
    });

    test('hysteresis: stays too far until clearly bigger', () {
      // 0.37 of the frame: between the enter (0.35) and leave (0.40) lines.
      final borderline = _body(300, 596);
      expect(framingHintFor(borderline, frame), FramingHint.ok);
      expect(
        framingHintFor(borderline, frame, previous: FramingHint.tooFar),
        FramingHint.tooFar,
      );
    });

    test('hysteresis: stays too close until clearly smaller', () {
      // 0.93 of the frame, not touching the edges.
      final borderline = _body(28, 772);
      expect(framingHintFor(borderline, frame), FramingHint.ok);
      expect(
        framingHintFor(borderline, frame, previous: FramingHint.tooClose),
        FramingHint.tooClose,
      );
    });

    test('low-confidence landmarks are ignored', () {
      final guessed = _pose({
        PoseLandmarkType.nose: const Offset(200, 0),
        PoseLandmarkType.leftAnkle: const Offset(200, 800),
      }, likelihood: 0.1);
      expect(
        framingHintFor({..._body(150, 650), ...guessed}, frame),
        FramingHint.ok,
      );
    });

    test('too few confident landmarks: no hint', () {
      final few = _pose({
        PoseLandmarkType.nose: const Offset(200, 380),
        PoseLandmarkType.leftShoulder: const Offset(190, 400),
      });
      expect(framingHintFor(few, frame), FramingHint.ok);
      expect(framingHintFor(const {}, frame), FramingHint.ok);
      expect(framingHintFor(_body(150, 650), Size.zero), FramingHint.ok);
    });

    test('every hint has a message except ok', () {
      expect(framingHintMessage(FramingHint.ok), isNull);
      expect(framingHintMessage(FramingHint.tooClose), contains('back'));
      expect(framingHintMessage(FramingHint.tooFar), contains('closer'));
    });
  });

  group('standing guide', () {
    test('shown until a pose is found', () {
      expect(
        showStandingGuide(
          poseFound: false,
          countingDown: true,
          notInFrame: false,
        ),
        isTrue,
      );
      expect(
        showStandingGuide(
          poseFound: true,
          countingDown: true,
          notInFrame: false,
        ),
        isFalse,
      );
    });

    test('shown again when not in frame after the countdown', () {
      expect(
        showStandingGuide(
          poseFound: true,
          countingDown: false,
          notInFrame: true,
        ),
        isTrue,
      );
      expect(
        showStandingGuide(
          poseFound: true,
          countingDown: false,
          notInFrame: false,
        ),
        isFalse,
      );
    });

    test('caption wording follows the camera view', () {
      expect(standingGuideCaption(CameraView.front), contains('facing'));
      expect(standingGuideCaption(CameraView.side), contains('side-on'));
      final either = standingGuideCaption(CameraView.either);
      expect(either, contains('facing'));
      expect(either, contains('side-on'));
    });
  });

  group('tempo cue', () {
    test('phase follows the rep cycle', () {
      expect(
        tempoPhaseFor(
          cycleActive: false,
          reachedTarget: false,
          atTarget: false,
          awaitingRest: false,
        ),
        TempoPhase.ready,
      );
      expect(
        tempoPhaseFor(
          cycleActive: true,
          reachedTarget: false,
          atTarget: false,
          awaitingRest: false,
        ),
        TempoPhase.lifting,
      );
      expect(
        tempoPhaseFor(
          cycleActive: true,
          reachedTarget: true,
          atTarget: true,
          awaitingRest: false,
        ),
        TempoPhase.holding,
      );
      expect(
        tempoPhaseFor(
          cycleActive: true,
          reachedTarget: true,
          atTarget: false,
          awaitingRest: false,
        ),
        TempoPhase.lowering,
      );
      // Already judged, waiting to get back to rest.
      expect(
        tempoPhaseFor(
          cycleActive: true,
          reachedTarget: true,
          atTarget: true,
          awaitingRest: true,
        ),
        TempoPhase.lowering,
      );
    });

    test('every phase has short cue text', () {
      for (final phase in TempoPhase.values) {
        final text = tempoCueText(phase);
        expect(text, isNotEmpty);
        expect(text.length, lessThan(30), reason: text);
      }
      expect(tempoCueText(TempoPhase.lifting).toLowerCase(), contains('lift'));
      expect(tempoCueText(TempoPhase.holding).toLowerCase(), contains('hold'));
      expect(
        tempoCueText(TempoPhase.lowering).toLowerCase(),
        contains('lower'),
      );
    });
  });

  group('SessionAccuracy', () {
    test('counted over attempts, rounded', () {
      final a = SessionAccuracy.fromScores(const [1, 1, 0, 1]);
      expect(a.counted, 3);
      expect(a.attempts, 4);
      expect(a.percent, 75);
    });

    test('rounds to the nearest percent', () {
      expect(SessionAccuracy.fromScores(const [1, 1, 0]).percent, 67);
    });

    test('no attempts: no percent', () {
      final a = SessionAccuracy.fromScores(const []);
      expect(a.attempts, 0);
      expect(a.percent, isNull);
    });
  });
}
