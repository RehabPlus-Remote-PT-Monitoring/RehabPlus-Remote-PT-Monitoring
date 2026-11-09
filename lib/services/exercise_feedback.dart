// lib/services/exercise_feedback.dart
//
// Pure, patient-facing feedback helpers for the live exercise screen
// (lib/screens/pose_detector_screen.dart). Nothing here touches the camera,
// ML Kit or the rep-counting rules: these functions only turn what the
// screen already knows (issue codes, angles, landmarks, the rep stage, the
// per-rep scores) into words, positions and small numbers for the overlays.
//
// Kept pure (no Flutter widgets, no clocks, no logging) so every rule can be
// unit tested in test/exercise_feedback_test.dart, and cheap enough to call
// on every processed frame (no allocation in the per-frame paths).

import 'dart:ui' show Size;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/exercise_model.dart';
import 'form_checker.dart';

// ---------------------------------------------------------------------------
// 1. "Why red" in plain language
// ---------------------------------------------------------------------------

/// One short, everyday sentence per [FormIssueCode], for the "why is the
/// skeleton red" line on the bottom card.
///
/// Why a separate text from [FormIssue.message]: the issue message is the
/// exercise-specific *instruction* already shown in the top banner ("Keep
/// your elbows by your sides. Only bend the elbow."). This line explains
/// *what the camera saw*, so it reads well next to that banner and also
/// works for several issues at once. The switch has no default, so adding
/// a code to the enum fails to compile until it gets a sentence here.
String formIssueExplanation(FormIssueCode code) => switch (code) {
  FormIssueCode.armsMoving => 'Your arms are moving. Keep them still.',
  FormIssueCode.legsMoving => 'Your legs are moving. Keep them still.',
  FormIssueCode.elbowDrift => 'Your elbow moved away from your side.',
  FormIssueCode.thighDrift => 'Your thigh moved. Only the lower leg moves.',
  FormIssueCode.armBent => 'Your arm is bending. Keep it straight.',
  FormIssueCode.bodySway => 'Your body is swaying. Stand steady.',
  FormIssueCode.trunkLean => 'You are leaning. Keep your back upright.',
  FormIssueCode.tooFast => 'That was too fast. Move slowly and smoothly.',
  FormIssueCode.kneeBent => 'Your knee is bending. Keep it straight.',
  FormIssueCode.kneesIn => 'Your knees are falling inward.',
  FormIssueCode.otherLeg => 'Your other leg is moving. Keep it relaxed.',
  FormIssueCode.shortRange => 'Not at the target position yet.',
  FormIssueCode.notInFrame => 'The camera cannot see all of you.',
};

/// The "why red" line for the bottom card: the plain sentence for each
/// distinct issue, at most [maxReasons] of them (more would not fit on a
/// phone at large text sizes; the first issue is the most important one).
/// Returns null when there is nothing wrong.
String? whyRedSummary(Iterable<FormIssueCode> codes, {int maxReasons = 2}) {
  final distinct = <FormIssueCode>[];
  for (final code in codes) {
    if (distinct.contains(code)) continue;
    distinct.add(code);
    if (distinct.length == maxReasons) break;
  }
  if (distinct.isEmpty) return null;
  return distinct.map(formIssueExplanation).join(' ');
}

// ---------------------------------------------------------------------------
// 2. Range gauge (rest .. target)
// ---------------------------------------------------------------------------

/// Maps a joint angle onto a 0..1 gauge running from the rest position
/// (0) through the target (at [targetStart]) to a little past the target
/// (1). The part from [targetStart] to 1 is drawn as the target zone.
///
/// Direction-aware: for a curl the target (70 deg) is BELOW rest (170 deg),
/// for a raise it is above, and both read left (rest) to right (target).
/// The gauge only displays the angle; whether a rep counts is still decided
/// by the screen's own rules.
class RangeGaugeScale {
  const RangeGaugeScale({
    required this.restAngle,
    required this.targetAngle,
    this.overshoot = 0.25,
  });

  final double restAngle;
  final double targetAngle;

  /// How far past the target the gauge reaches, as a fraction of the
  /// rest-to-target span. Leaves room to show the marker inside the zone.
  final double overshoot;

  /// Spans under this many degrees can't be drawn meaningfully.
  static const double _minSpanDeg = 1.0;

  /// Gauge position where the target zone starts (0..1).
  double get targetStart => 1 / (1 + overshoot);

  /// Marker position for [angle], clamped to 0..1, or null when there is
  /// nothing sensible to show (unknown angle or a degenerate range).
  double? position(double angle) {
    final span = targetAngle - restAngle;
    if (!angle.isFinite || span.abs() < _minSpanDeg) return null;
    final raw = (angle - restAngle) / (span * (1 + overshoot));
    return raw.clamp(0.0, 1.0).toDouble();
  }

  /// True when [angle] is at or past the target, in the exercise's
  /// direction.
  bool isInTarget(double angle) =>
      targetAngle >= restAngle ? angle >= targetAngle : angle <= targetAngle;
}

// ---------------------------------------------------------------------------
// 5. "Step back / move closer"
// ---------------------------------------------------------------------------

enum FramingHint { ok, tooClose, tooFar }

/// Thresholds for [framingHintFor], as fractions of the image height. Each
/// hint has an "enter" and a looser "leave" line (hysteresis), so the
/// banner doesn't flicker when the patient stands right on a boundary.
const double framingTooCloseEnter = 0.95;
const double framingTooCloseLeave = 0.90;
const double framingTooFarEnter = 0.35;
const double framingTooFarLeave = 0.40;

/// A confident landmark this close to the top or bottom edge counts as
/// "touching" it; touching both means the body is cut off.
const double framingEdgeMargin = 0.03;

/// Fewer confident landmarks than this: too little to judge the framing.
const int framingMinLandmarks = 4;

/// Whether the patient should step back, come closer, or is fine, from how
/// much of the image height the confidently seen landmarks cover.
///
/// [imageSize] must be in the same (upright) coordinates as the landmarks,
/// i.e. the screen's rotated image size. Only landmarks with a likelihood of
/// at least [minLikelihood] count, because ML Kit also returns guessed
/// points for body parts outside the image. [previous] is the hint shown
/// last time, for the hysteresis. Loops over the map once, no allocation.
FramingHint framingHintFor(
  Map<PoseLandmarkType, PoseLandmark> landmarks,
  Size imageSize, {
  FramingHint previous = FramingHint.ok,
  double minLikelihood = 0.5,
}) {
  final height = imageSize.height;
  if (height <= 0) return FramingHint.ok;

  var count = 0;
  var top = double.infinity;
  var bottom = double.negativeInfinity;
  for (final p in landmarks.values) {
    if (p.likelihood < minLikelihood) continue;
    count++;
    if (p.y < top) top = p.y;
    if (p.y > bottom) bottom = p.y;
  }
  if (count < framingMinLandmarks) return FramingHint.ok;

  final span = (bottom - top) / height;
  final margin = framingEdgeMargin * height;
  final cutOff = top <= margin && bottom >= height - margin;

  final closeLimit = previous == FramingHint.tooClose
      ? framingTooCloseLeave
      : framingTooCloseEnter;
  if (span > closeLimit || cutOff) return FramingHint.tooClose;

  final farLimit = previous == FramingHint.tooFar
      ? framingTooFarLeave
      : framingTooFarEnter;
  if (span < farLimit) return FramingHint.tooFar;

  return FramingHint.ok;
}

/// Banner text for a framing hint, or null when no banner is needed.
String? framingHintMessage(FramingHint hint) => switch (hint) {
  FramingHint.ok => null,
  FramingHint.tooClose =>
    'Step back a little so the camera can see all of you.',
  FramingHint.tooFar => 'Move a little closer to the camera.',
};

// ---------------------------------------------------------------------------
// 6. Standing-position outline
// ---------------------------------------------------------------------------

/// Whether to draw the faint "stand here" outline: until the camera finds a
/// body, and again whenever the patient is out of frame after the
/// countdown (during the countdown the outline would only compete with the
/// big number once the body is found).
bool showStandingGuide({
  required bool poseFound,
  required bool countingDown,
  required bool notInFrame,
}) => !poseFound || (!countingDown && notInFrame);

/// Caption under the outline. Only the wording follows the camera view; the
/// outline itself is the same for front and side views.
String standingGuideCaption(CameraView view) => switch (view) {
  CameraView.front => 'Stand inside the outline, facing the camera.',
  CameraView.side => 'Stand inside the outline, side-on to the camera.',
  CameraView.either =>
    'Stand inside the outline, facing the camera or side-on.',
};

// ---------------------------------------------------------------------------
// 7. Tempo cue
// ---------------------------------------------------------------------------

/// Where the patient is in one rep, for the "Lift... hold... lower" cue.
enum TempoPhase { ready, lifting, holding, lowering }

/// The tempo phase from the screen's existing rep-cycle state (read only):
///  - [cycleActive]: the joint has left rest (a rep is in progress)
///  - [reachedTarget]: the target was reached this rep (stage "up")
///  - [atTarget]: the joint is still at the target right now
///  - [awaitingRest]: the rep was already judged; waiting to get back down
TempoPhase tempoPhaseFor({
  required bool cycleActive,
  required bool reachedTarget,
  required bool atTarget,
  required bool awaitingRest,
}) {
  if (awaitingRest) return TempoPhase.lowering;
  if (!cycleActive) return TempoPhase.ready;
  if (!reachedTarget) return TempoPhase.lifting;
  return atTarget ? TempoPhase.holding : TempoPhase.lowering;
}

/// Short cue text. Generic verbs on purpose ("lift" also reads fine for a
/// push or a bend), so one wording works for every rep exercise.
String tempoCueText(TempoPhase phase) => switch (phase) {
  TempoPhase.ready => 'Ready: lift slowly',
  TempoPhase.lifting => 'Lift slowly...',
  TempoPhase.holding => 'Hold...',
  TempoPhase.lowering => 'Lower slowly...',
};

// ---------------------------------------------------------------------------
// 9. End-of-session summary
// ---------------------------------------------------------------------------

/// Accuracy for the completion dialog, from the screen's per-attempt scores
/// (1.0 = counted, 0.0 = not counted).
class SessionAccuracy {
  const SessionAccuracy({required this.counted, required this.attempts});

  factory SessionAccuracy.fromScores(List<double> scores) {
    var counted = 0;
    for (final s in scores) {
      if (s >= 0.5) counted++;
    }
    return SessionAccuracy(counted: counted, attempts: scores.length);
  }

  final int counted;
  final int attempts;

  /// Rounded percentage, or null when nothing was attempted (0 of 0 is not
  /// "0 % accurate").
  int? get percent => attempts == 0 ? null : (counted * 100 / attempts).round();
}
