// lib/services/exercise_geometry.dart
//
// Camera geometry for the exercises added in the second exercise batch:
// Mini Squat, Standing Hip Abduction, Standing Hamstring Curl, Marching in
// Place and Overhead Arm Raise.
//
// Why a separate file
// -------------------
// The original exercises keep their measurements inside PoseDetectorScreen.
// These newer ones live here as pure functions instead (no widgets, no
// camera), so they can be unit-tested with synthetic landmarks
// (test/exercise_geometry_test.dart). The screen calls [readRep] for the
// angle it counts on and [extraFaults] for the per-exercise form checks; the
// rep cycle itself (leave rest, reach target, come back, anti-flail rules)
// is the same shared logic every exercise uses.
//
// Conventions
// -----------
//   - Landmark x/y are image pixels; y grows DOWNWARD.
//   - All angles are in degrees, measured in the 2D image. That is why each
//     exercise has a required camera view (front or side): a movement that
//     goes towards the camera can't be measured.
//   - Measuring uses landmarks even when ML Kit is unsure of them (like the
//     original exercises), so counting doesn't stall. Fault checks only use
//     confidently-visible landmarks, so a guessed point never turns the
//     skeleton red.
//
// Tuning knobs are the `static const` values in [ExerciseGeometry]. The rep
// target and rest angles themselves are in lib/models/exercise_model.dart.
// These numbers are starting points from general physiotherapy guidance and
// must be confirmed with the clinic and tuned on a real phone.

import 'dart:math';

import 'package:collection/collection.dart' show IterableDoubleExtension;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/exercise_model.dart';
import 'form_checker.dart';

/// One frame's reading for a rep-based exercise.
class RepReading {
  const RepReading({required this.angle, required this.atTarget});

  /// The angle the rep is counted on (see each exercise in [readRep]).
  final double angle;

  /// True when the target position is reached in this frame.
  final bool atTarget;

  @override
  String toString() =>
      'RepReading(angle: ${angle.toStringAsFixed(1)}, '
      'atTarget: $atTarget)';
}

typedef Landmarks = Map<PoseLandmarkType, PoseLandmark>;

class ExerciseGeometry {
  ExerciseGeometry._();

  /// The exercise types this file handles.
  static const Set<ExerciseType> handledTypes = {
    ExerciseType.miniSquat,
    ExerciseType.hipAbduction,
    ExerciseType.hamstringCurl,
    ExerciseType.marching,
    ExerciseType.overheadRaise,
  };

  // ---------------------------------------------------------------------
  // TUNING
  // ---------------------------------------------------------------------

  /// A standing (supporting) knee bent more than this is a fault.
  static const double straightKneeDeg = 150.0;

  /// Mini squat: a knee angle below this is deeper than a mini squat.
  static const double miniSquatTooDeepDeg = 100.0;

  /// Mini squat: forward trunk lean allowed (some lean is normal).
  static const double miniSquatMaxLeanDeg = 45.0;

  /// Mini squat (front view): knees closer together than this fraction of
  /// the ankle width means they are caving inward.
  static const double kneesInRatio = 0.75;

  /// Mini squat: the knee-cave check only runs once the knees bend past
  /// this angle (standing straight with feet apart is not a fault).
  static const double kneesInCheckBelowDeg = 160.0;

  /// Mini squat: the knee-cave check needs the feet visibly apart (front
  /// view), as a fraction of torso length. In a side view the legs overlap.
  static const double frontViewMinAnkleGap = 0.3;

  /// Hip abduction: sideways trunk lean allowed (leaning away from the
  /// lifted leg is the usual way to cheat this exercise).
  static const double hipAbductionMaxSideLeanDeg = 15.0;

  /// Hamstring curl: the thigh must stay down; a hip angle (shoulder-hip-
  /// knee) below this means the thigh is swinging forward.
  static const double hamstringMinHipDeg = 145.0;

  /// Overhead raise: leaning back (arching) more than this is a fault.
  static const double overheadMaxBackLeanDeg = 20.0;

  /// Smallest angle ever reported by [readRep]. PoseDetectorScreen treats
  /// an angle of exactly 0.0 as "could not measure" and skips the frame;
  /// an arm hanging along the body or a leg at rest can genuinely read 0,
  /// and skipping those frames would hide the rest position.
  static const double _minReportedDeg = 0.5;

  // ---------------------------------------------------------------------
  // Rep measurement
  // ---------------------------------------------------------------------

  /// The counted angle for [exercise] in this frame, or null when a needed
  /// landmark is missing (the screen then skips the frame).
  ///
  /// Direction: when the target angle is larger than the rest angle the
  /// target is reached by going ABOVE it, otherwise by going BELOW it.
  static RepReading? readRep(ExerciseConfig exercise, Landmarks lm) {
    final double? angle = switch (exercise.type) {
      // Knee bend, both legs averaged (front or side view).
      ExerciseType.miniSquat => _mean([
        _angle(lm, _left.hip, _left.knee, _left.ankle),
        _angle(lm, _right.hip, _right.knee, _right.ankle),
      ]),

      // Degrees the leg is out from the line of the body (front view),
      // taking the leg that is further out.
      ExerciseType.hipAbduction => [
        _abduction(lm, _left),
        _abduction(lm, _right),
      ].nonNulls.maxOrNull,

      // Knee bend of the working leg, which is the more bent one (side view).
      ExerciseType.hamstringCurl => [
        _angle(lm, _left.hip, _left.knee, _left.ankle),
        _angle(lm, _right.hip, _right.knee, _right.ankle),
      ].nonNulls.minOrNull,

      // Hip angle (shoulder-hip-knee) of the lifted leg, the smaller one
      // (side view). Legs alternate, and each lift is one rep.
      ExerciseType.marching => [
        _angle(lm, _left.shoulder, _left.hip, _left.knee),
        _angle(lm, _right.shoulder, _right.hip, _right.knee),
      ].nonNulls.minOrNull,

      // Arm against the body (hip-shoulder-wrist), the higher arm (side view).
      ExerciseType.overheadRaise => [
        _angle(lm, _left.hip, _left.shoulder, _left.wrist),
        _angle(lm, _right.hip, _right.shoulder, _right.wrist),
      ].nonNulls.maxOrNull,

      _ => null,
    };
    if (angle == null || !angle.isFinite) return null;
    final measured = max(angle, _minReportedDeg);

    final increasing = exercise.targetAngle > exercise.restAngle;
    final atTarget = increasing
        ? measured >= exercise.targetAngle
        : measured <= exercise.targetAngle;
    return RepReading(angle: measured, atTarget: atTarget);
  }

  // ---------------------------------------------------------------------
  // Knee Extension (an original exercise, whose "which leg is which" logic
  // lives here so it can be tested)
  // ---------------------------------------------------------------------

  /// The two legs must be at least this far apart at the ankles (in torso
  /// lengths) before they count as two separate legs. Seated side-on, the
  /// thighs overlap, so the ankles are what tells the legs apart.
  static const double distinctAnklesMinGap = 0.25;

  /// Knee angles for Knee Extension: the [working] (more extended) leg, and
  /// the [resting] leg ONLY when it can really be seen as a separate leg.
  ///
  /// Why: from the side, the far leg is hidden behind the near one. ML Kit
  /// still guesses its landmarks, usually right on top of the leg being
  /// lifted, so it also reads ~170 deg. Requiring that "other leg" to be
  /// bent then silently blocked every rep. So the other leg only counts
  /// when its landmarks are confident AND its ankle is clearly apart from
  /// the working ankle. When it can't be seen, [resting] is null and the
  /// visible leg is judged on its own.
  ///
  /// Returns null when no leg can be measured.
  static ({double working, double? resting})? kneeExtensionLegs(
    Landmarks lm, {
    required double minLikelihood,
  }) {
    final leftSure = _angle(
      lm,
      _left.hip,
      _left.knee,
      _left.ankle,
      minLikelihood: minLikelihood,
    );
    final rightSure = _angle(
      lm,
      _right.hip,
      _right.knee,
      _right.ankle,
      minLikelihood: minLikelihood,
    );

    if (leftSure != null && rightSure != null) {
      final working = max(leftSure, rightSure);
      final resting = min(leftSure, rightSure);
      return (working: working, resting: anklesApart(lm) ? resting : null);
    }

    // One leg (or neither) is confidently visible: judge the visible one.
    // Guessed landmarks are only used when nothing better exists, so that
    // counting doesn't stall in poor light (same as the other exercises).
    final visible = leftSure ?? rightSure;
    if (visible != null) return (working: visible, resting: null);
    final guessed = [
      _angle(lm, _left.hip, _left.knee, _left.ankle),
      _angle(lm, _right.hip, _right.knee, _right.ankle),
    ].nonNulls.maxOrNull;
    return guessed == null ? null : (working: guessed, resting: null);
  }

  /// True when the two ankles are clearly apart (two separate legs), not
  /// overlapping as they do when one leg hides the other.
  static bool anklesApart(Landmarks lm) {
    final leftAnkle = lm[_left.ankle];
    final rightAnkle = lm[_right.ankle];
    final torso = _torsoPx(lm);
    if (leftAnkle == null || rightAnkle == null || torso == null) return false;
    final dx = leftAnkle.x - rightAnkle.x;
    final dy = leftAnkle.y - rightAnkle.y;
    return sqrt(dx * dx + dy * dy) >= distinctAnklesMinGap * torso;
  }

  /// Shoulder-mid to hip-mid distance in pixels, or null if not available.
  static double? _torsoPx(Landmarks lm) {
    final shoulders = [
      lm[_left.shoulder],
      lm[_right.shoulder],
    ].whereType<PoseLandmark>().toList();
    final hips = [
      lm[_left.hip],
      lm[_right.hip],
    ].whereType<PoseLandmark>().toList();
    if (shoulders.isEmpty || hips.isEmpty) return null;
    double meanX(List<PoseLandmark> ps) => ps.map((p) => p.x).sum / ps.length;
    double meanY(List<PoseLandmark> ps) => ps.map((p) => p.y).sum / ps.length;
    final dx = meanX(shoulders) - meanX(hips);
    final dy = meanY(shoulders) - meanY(hips);
    final length = sqrt(dx * dx + dy * dy);
    return length > 0 ? length : null;
  }

  // ---------------------------------------------------------------------
  // Form faults
  // ---------------------------------------------------------------------

  /// Instant (un-debounced) faults for [type] in this frame. The screen
  /// debounces them for display and counts them per rep to reject reps.
  /// Only confidently-visible landmarks (>= [minLikelihood]) are used.
  static List<FormIssue> extraFaults(
    ExerciseType type,
    Landmarks lm, {
    required double minLikelihood,
  }) {
    final faults = <FormIssue>[];

    // Knee bend (hip-knee-ankle) and hip bend (shoulder-hip-knee) of one
    // side, from confident landmarks only.
    double? kneeAngle(_Side s) =>
        _angle(lm, s.hip, s.knee, s.ankle, minLikelihood: minLikelihood);
    double? hipAngle(_Side s) =>
        _angle(lm, s.shoulder, s.hip, s.knee, minLikelihood: minLikelihood);

    // Front view: sideways lean. Side view: forward/back lean.
    final lean = _trunkLeanDeg(lm, minLikelihood);

    switch (type) {
      case ExerciseType.miniSquat:
        final knees = _mean([kneeAngle(_left), kneeAngle(_right)]);
        if (knees != null && knees < miniSquatTooDeepDeg) {
          faults.add(
            FormIssue(
              code: FormIssueCode.shortRange,
              message: 'Too deep. Only bend your knees partway.',
              landmarks: {_left.knee, _right.knee},
              anchor: _left.knee,
            ),
          );
        }
        if (knees != null &&
            knees < kneesInCheckBelowDeg &&
            _kneesCaveIn(lm, minLikelihood)) {
          faults.add(
            FormIssue(
              code: FormIssueCode.kneesIn,
              message:
                  "Keep your knees over your toes. Don't let them fall inward.",
              landmarks: {_left.knee, _right.knee},
              anchor: _left.knee,
            ),
          );
        }
        if (lean != null && lean > miniSquatMaxLeanDeg) {
          faults.add(
            _leanIssue("Keep your chest up. Don't lean too far forward."),
          );
        }

      case ExerciseType.hipAbduction:
        // The working leg is the one further out; it must stay straight.
        final left = _abduction(lm, _left, minLikelihood: minLikelihood);
        final right = _abduction(lm, _right, minLikelihood: minLikelihood);
        if (left != null || right != null) {
          final working = (left ?? -1) >= (right ?? -1) ? _left : _right;
          final knee = kneeAngle(working);
          if (knee != null && knee < straightKneeDeg) {
            faults.add(_kneeBentIssue(working, 'Keep your leg straight.'));
          }
        }
        if (lean != null && lean > hipAbductionMaxSideLeanDeg) {
          faults.add(_leanIssue("Stand tall. Don't lean to the side."));
        }

      case ExerciseType.hamstringCurl:
        final left = kneeAngle(_left);
        final right = kneeAngle(_right);
        if (left != null && right != null) {
          // The working leg is the more bent one; the other one stands.
          final leftWorks = left <= right;
          final working = leftWorks ? _left : _right;
          final standing = leftWorks ? _right : _left;
          final standingKnee = leftWorks ? right : left;
          if (standingKnee < straightKneeDeg) {
            faults.add(
              _kneeBentIssue(standing, 'Keep your standing leg straight.'),
            );
          }
          final workingHip = hipAngle(working);
          if (workingHip != null && workingHip < hamstringMinHipDeg) {
            faults.add(
              FormIssue(
                code: FormIssueCode.thighDrift,
                message: 'Keep your thigh pointing down. Only bend the knee.',
                landmarks: {working.hip, working.knee},
                anchor: working.knee,
              ),
            );
          }
        }

      case ExerciseType.marching:
        final left = hipAngle(_left);
        final right = hipAngle(_right);
        if (left != null && right != null) {
          // The standing leg has the larger (straighter) hip angle.
          final standing = left >= right ? _left : _right;
          final knee = kneeAngle(standing);
          if (knee != null && knee < straightKneeDeg) {
            faults.add(
              _kneeBentIssue(standing, 'Keep your standing leg straight.'),
            );
          }
        }

      case ExerciseType.overheadRaise:
        if (lean != null && lean > overheadMaxBackLeanDeg) {
          faults.add(_leanIssue("Don't lean back. Keep your back straight."));
        }

      default:
        break;
    }
    return faults;
  }

  /// Patient-facing hint when a rep was started but didn't reach the target.
  static ({String message, Set<PoseLandmarkType> landmarks}) rangeFeedback(
    ExerciseType type,
  ) {
    return switch (type) {
      ExerciseType.miniSquat => (
        message: 'Bend your knees a little more.',
        landmarks: {_left.knee, _right.knee},
      ),
      ExerciseType.hipAbduction => (
        message: 'Lift your leg further out to the side.',
        landmarks: {_left.ankle, _right.ankle},
      ),
      ExerciseType.hamstringCurl => (
        message: 'Bring your heel up higher.',
        landmarks: {_left.ankle, _right.ankle},
      ),
      ExerciseType.marching => (
        message: 'Lift your knee higher.',
        landmarks: {_left.knee, _right.knee},
      ),
      ExerciseType.overheadRaise => (
        message: 'Raise your arm higher, up beside your ear.',
        landmarks: {_left.wrist, _right.wrist},
      ),
      _ => (message: 'Move through the full range.', landmarks: const {}),
    };
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  /// Joint angle at [b] between the limbs going to [a] and [c], in degrees
  /// (0..180). For example hip-knee-ankle gives the knee bend: 180 is a
  /// straight leg. Pure math, no visibility checks: callers decide which
  /// landmarks are confident enough to use.
  ///
  /// This is the one shared copy of the formula; ExerciseGeometry,
  /// FormChecker and the exercise screen all call it.
  static double jointAngle(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
    final radians =
        atan2(c.y - b.y, c.x - b.x) - atan2(a.y - b.y, a.x - b.x);
    var degrees = (radians * 180 / pi).abs();
    if (degrees > 180) degrees = 360 - degrees;
    return degrees;
  }

  /// Angle at [b] between [a] and [c], in degrees (0..180). Null if a
  /// landmark is missing, or below [minLikelihood] when one is given.
  static double? _angle(
    Landmarks lm,
    PoseLandmarkType a,
    PoseLandmarkType b,
    PoseLandmarkType c, {
    double? minLikelihood,
  }) {
    final p1 = lm[a], p2 = lm[b], p3 = lm[c];
    if (p1 == null || p2 == null || p3 == null) return null;
    if (minLikelihood != null &&
        (p1.likelihood < minLikelihood ||
            p2.likelihood < minLikelihood ||
            p3.likelihood < minLikelihood)) {
      return null;
    }
    return jointAngle(p1, p2, p3);
  }

  /// How far (degrees) the thigh on [side] is out from the line of the
  /// trunk, counting only OUTWARD movement (away from the body's midline),
  /// so a leg crossing inward doesn't count as a lift.
  static double? _abduction(Landmarks lm, _Side side, {double? minLikelihood}) {
    final angle = _angle(
      lm,
      side.shoulder,
      side.hip,
      side.knee,
      minLikelihood: minLikelihood,
    );
    final hip = lm[side.hip];
    final knee = lm[side.knee];
    final otherHip = lm[side.other.hip];
    if (angle == null || hip == null || knee == null || otherHip == null) {
      return null;
    }
    final midlineX = (hip.x + otherHip.x) / 2;
    final hipOffset = hip.x - midlineX;
    final kneeOffset = knee.x - midlineX;
    // Outward = the knee is on the same side of the midline as its hip, and
    // further from it. A knee that crossed the midline moved inward.
    final kneeIsOutward =
        kneeOffset.sign == hipOffset.sign &&
        kneeOffset.abs() >= hipOffset.abs();
    return kneeIsOutward ? 180 - angle : 0.0;
  }

  /// True when the knees are much closer together than the ankles, seen
  /// from the front (the feet must be visibly apart, or it's a side view).
  static bool _kneesCaveIn(Landmarks lm, double minLikelihood) {
    final points = [
      _left.knee,
      _right.knee,
      _left.ankle,
      _right.ankle,
      _left.shoulder,
      _left.hip,
    ].map((t) => lm[t]).toList();
    if (points.any((p) => p == null || p.likelihood < minLikelihood)) {
      return false;
    }
    final kneeGap = (lm[_left.knee]!.x - lm[_right.knee]!.x).abs();
    final ankleGap = (lm[_left.ankle]!.x - lm[_right.ankle]!.x).abs();
    final torso = (lm[_left.hip]!.y - lm[_left.shoulder]!.y).abs();
    if (torso <= 0 || ankleGap < frontViewMinAnkleGap * torso) return false;
    return kneeGap < kneesInRatio * ankleGap;
  }

  /// Trunk lean from vertical in degrees (shoulder-mid above hip-mid = 0).
  /// A 2D image only shows the lean across the picture: sideways in a front
  /// view, forward/back in a side view. Each exercise's limit assumes its
  /// own camera view.
  static double? _trunkLeanDeg(Landmarks lm, double minLikelihood) {
    final shoulders = _confident(lm, [
      _left.shoulder,
      _right.shoulder,
    ], minLikelihood);
    final hips = _confident(lm, [_left.hip, _right.hip], minLikelihood);
    if (shoulders.isEmpty || hips.isEmpty) return null;
    double meanX(List<PoseLandmark> ps) => ps.map((p) => p.x).sum / ps.length;
    double meanY(List<PoseLandmark> ps) => ps.map((p) => p.y).sum / ps.length;
    final dx = (meanX(shoulders) - meanX(hips)).abs();
    final up = meanY(hips) - meanY(shoulders); // y grows downward
    return atan2(dx, up) * 180 / pi;
  }

  static List<PoseLandmark> _confident(
    Landmarks lm,
    List<PoseLandmarkType> types,
    double minLikelihood,
  ) => types
      .map((type) => lm[type])
      .whereType<PoseLandmark>()
      .where((p) => p.likelihood >= minLikelihood)
      .toList();

  static FormIssue _leanIssue(String message) => FormIssue(
    code: FormIssueCode.trunkLean,
    message: message,
    landmarks: {_left.shoulder, _right.shoulder, _left.hip, _right.hip},
    anchor: _left.shoulder,
  );

  static FormIssue _kneeBentIssue(_Side side, String message) => FormIssue(
    code: FormIssueCode.kneeBent,
    message: message,
    landmarks: {side.knee, side.ankle},
    anchor: side.knee,
  );

  /// Mean of the values that are present, or null when none are.
  /// (Not collection's `.average`: that uses a running mean, whose rounding
  /// can differ in the last digit from sum / count.)
  static double? _mean(List<double?> values) {
    final present = values.nonNulls.toList();
    if (present.isEmpty) return null;
    return present.sum / present.length;
  }
}

/// The landmarks of one side of the body.
class _Side {
  const _Side._({
    required this.shoulder,
    required this.wrist,
    required this.hip,
    required this.knee,
    required this.ankle,
    required this.isLeft,
  });

  final PoseLandmarkType shoulder, wrist, hip, knee, ankle;
  final bool isLeft;

  _Side get other => isLeft ? _right : _left;
}

const _left = _Side._(
  shoulder: PoseLandmarkType.leftShoulder,
  wrist: PoseLandmarkType.leftWrist,
  hip: PoseLandmarkType.leftHip,
  knee: PoseLandmarkType.leftKnee,
  ankle: PoseLandmarkType.leftAnkle,
  isLeft: true,
);

const _right = _Side._(
  shoulder: PoseLandmarkType.rightShoulder,
  wrist: PoseLandmarkType.rightWrist,
  hip: PoseLandmarkType.rightHip,
  knee: PoseLandmarkType.rightKnee,
  ankle: PoseLandmarkType.rightAnkle,
  isLeft: false,
);
