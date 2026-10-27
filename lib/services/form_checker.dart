// lib/services/form_checker.dart
//
// Frame-by-frame "is this good form?" judge that sits next to the rep logic
// in PoseDetectorScreen. It never counts reps; it only answers:
//   - is the patient in frame?
//   - is anything moving that should be still (flailing arms, swaying body)?
//   - is the working limb moving too fast / uncontrolled?
//   - is the trunk leaning when the exercise needs an upright back?
//   - exercise-specific faults (other leg not bent, knee bent on a leg raise)
//
// All motion is measured in TORSO LENGTHS (shoulder-mid to hip-mid distance),
// so thresholds don't depend on how far the patient stands from the phone.

import 'dart:collection';
import 'dart:math';
import 'dart:ui' show Offset;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../core/diagnostic_logger.dart';
import '../models/exercise_model.dart';
import 'exercise_geometry.dart';

// Declared in priority order: lower index is shown first in the banner.
enum FormIssueCode {
  armsMoving,
  legsMoving,
  elbowDrift,
  thighDrift,
  armBent,
  bodySway,
  trunkLean,
  tooFast,
  kneeBent,
  kneesIn,
  otherLeg,
  shortRange,
  notInFrame,
}

class FormIssue {
  final FormIssueCode code;

  /// Patient-facing text, shown in the banner and in the on-skeleton callout.
  final String message;

  /// Landmarks to highlight in red.
  final Set<PoseLandmarkType> landmarks;

  /// Landmark the callout bubble points at (falls back to any of [landmarks]).
  final PoseLandmarkType? anchor;

  const FormIssue({
    required this.code,
    required this.message,
    required this.landmarks,
    this.anchor,
  });

  FormIssue withMessage(String m) =>
      FormIssue(code: code, message: m, landmarks: landmarks, anchor: anchor);
}

enum FormStatus { ok, wrongForm, notInFrame }

class FormResult {
  final FormStatus status;
  final List<FormIssue> issues;

  const FormResult(this.status, this.issues);

  static const FormResult ok = FormResult(FormStatus.ok, []);

  bool get isOk => status == FormStatus.ok;
  bool get isWrong => status == FormStatus.wrongForm;
  bool get isNotInFrame => status == FormStatus.notInFrame;
  FormIssue? get primary => issues.isEmpty ? null : issues.first;

  Set<PoseLandmarkType> get flagged => {for (final i in issues) ...i.landmarks};

  /// Returns a copy with [issue] put first (used for one-off events such as
  /// "rep not counted" that outlive the frame that caused them).
  FormResult plus(FormIssue issue) {
    if (isNotInFrame) return this;
    return FormResult(FormStatus.wrongForm, [
      issue,
      ...issues.where((i) => i.code != issue.code),
    ]);
  }
}

/// All tunable numbers in one place. [strict] is what the app uses; loosen
/// via [standard] (or build your own) after testing with real patients.
class FormThresholds {
  /// Landmarks below this ML Kit confidence are ignored.
  final double minLikelihood;

  /// Max wander (in torso lengths, over [window]) for limbs that should be still.
  final double stationaryRange;

  /// Max wander for the shoulders/hips when the body should stay put.
  final double torsoSwayRange;

  /// Max speed (torso lengths per second) for limbs that are meant to move.
  final double maxWorkingSpeed;

  /// Max trunk lean from vertical, in degrees, for upright exercises.
  final double maxTrunkLeanDeg;

  /// Bicep curl: max angle between upper arm and trunk (elbow must stay pinned).
  final double maxUpperArmSwingDeg;

  /// Raises: the arm must stay at least this straight (elbow angle, degrees).
  final double minStraightArmDeg;

  /// How much recent history is used for the wander measurement.
  final Duration window;

  /// A fault must persist this long before it's reported (kills flicker).
  final Duration confirm;

  /// A reported fault stays on screen this long after it stops.
  final Duration hold;

  /// Fraction of the rest->target movement that counts as an honest attempt.
  /// Used by the screen to detect partial reps.
  final double attemptProgress;

  const FormThresholds({
    required this.minLikelihood,
    required this.stationaryRange,
    required this.torsoSwayRange,
    required this.maxWorkingSpeed,
    required this.maxTrunkLeanDeg,
    required this.maxUpperArmSwingDeg,
    required this.minStraightArmDeg,
    required this.window,
    required this.confirm,
    required this.hold,
    required this.attemptProgress,
  });

  static const FormThresholds strict = FormThresholds(
    minLikelihood: 0.5,
    stationaryRange: 0.25,
    torsoSwayRange: 0.15,
    maxWorkingSpeed: 2.2,
    maxTrunkLeanDeg: 20,
    maxUpperArmSwingDeg: 30,
    minStraightArmDeg: 150,
    window: Duration(milliseconds: 800),
    confirm: Duration(milliseconds: 120),
    hold: Duration(milliseconds: 700),
    attemptProgress: 0.3,
  );

  static const FormThresholds standard = FormThresholds(
    minLikelihood: 0.5,
    stationaryRange: 0.40,
    torsoSwayRange: 0.25,
    maxWorkingSpeed: 3.5,
    maxTrunkLeanDeg: 30,
    maxUpperArmSwingDeg: 45,
    minStraightArmDeg: 140,
    window: Duration(milliseconds: 800),
    confirm: Duration(milliseconds: 200),
    hold: Duration(milliseconds: 700),
    attemptProgress: 0.4,
  );
}

// ---------------------------------------------------------------------------
// Landmark groups
// ---------------------------------------------------------------------------

final Set<PoseLandmarkType> _shoulders = {
  PoseLandmarkType.leftShoulder,
  PoseLandmarkType.rightShoulder,
};
final Set<PoseLandmarkType> _hips = {
  PoseLandmarkType.leftHip,
  PoseLandmarkType.rightHip,
};
final Set<PoseLandmarkType> _elbows = {
  PoseLandmarkType.leftElbow,
  PoseLandmarkType.rightElbow,
};
final Set<PoseLandmarkType> _wrists = {
  PoseLandmarkType.leftWrist,
  PoseLandmarkType.rightWrist,
};
final Set<PoseLandmarkType> _knees = {
  PoseLandmarkType.leftKnee,
  PoseLandmarkType.rightKnee,
};
final Set<PoseLandmarkType> _ankles = {
  PoseLandmarkType.leftAnkle,
  PoseLandmarkType.rightAnkle,
};
final Set<PoseLandmarkType> _arms = {..._elbows, ..._wrists};
final Set<PoseLandmarkType> _legs = {..._knees, ..._ankles};
final Set<PoseLandmarkType> _torso = {..._shoulders, ..._hips};

/// What each exercise expects from the body besides the working joint.
class _Profile {
  /// Limbs that must stay put (checked by how far they wander).
  final Set<PoseLandmarkType> stationary;

  /// Limbs that are supposed to move (checked by speed only).
  final Set<PoseLandmarkType> working;

  /// Shoulders/hips must not sway around.
  final bool torsoStill;

  /// Back must stay upright (seated / standing exercises).
  final bool upright;

  /// Which limbs must be in frame before tracking starts.
  final bool needsLegs;
  final bool needsArms;

  _Profile({
    required this.stationary,
    required this.working,
    required this.torsoStill,
    required this.upright,
    this.needsLegs = false,
    this.needsArms = false,
  });
}

_Profile _profileFor(ExerciseType type) {
  switch (type) {
    case ExerciseType.kneeExtension: // seated
      // Arms are not checked: seated side-on, the hidden far arm's guessed
      // landmarks jitter and rejected real reps as "arms moving" in testing,
      // and arm movement doesn't affect a knee extension.
      return _Profile(
        stationary: <PoseLandmarkType>{},
        working: _legs,
        torsoStill: true,
        upright: true,
        needsLegs: true,
      );

    // Lying-down leg work. Flip `upright` to true for kneeFlexion if your
    // clinic performs it standing (hamstring curl) instead of lying prone.
    case ExerciseType.straightLegRaise:
    case ExerciseType.heelSlide:
    case ExerciseType.kneeFlexion:
      return _Profile(
        stationary: _arms,
        working: _legs,
        torsoStill: true,
        upright: false,
        needsLegs: true,
      );

    case ExerciseType.sitToStand:
    case ExerciseType.gluteBridge:
      // The torso legitimately travels in these two.
      return _Profile(
        stationary: _arms,
        working: _legs,
        torsoStill: false,
        upright: false,
        needsLegs: true,
      );

    case ExerciseType.bicepCurl:
      return _Profile(
        stationary: {..._elbows, ..._legs}, // elbows pinned to the sides
        working: _wrists,
        torsoStill: true,
        upright: true,
        needsArms: true,
      );

    case ExerciseType.forwardRaise:
    case ExerciseType.sideRaise:
    case ExerciseType.forwardPush:
      return _Profile(
        stationary: _legs, // feet stay planted
        working: _arms,
        torsoStill: true,
        upright: true,
        needsArms: true,
      );

    case ExerciseType.singleLegBalance:
      return _Profile(
        stationary: _arms,
        working: _legs,
        torsoStill: true,
        upright: true,
        needsLegs: true,
      );

    case ExerciseType.wallSit:
      return _Profile(
        stationary: {..._arms, ..._legs},
        working: <PoseLandmarkType>{},
        torsoStill: true,
        upright: true,
        needsLegs: true,
      );

    // --- Second batch (measured in exercise_geometry.dart) ---

    case ExerciseType.miniSquat:
      // Arms often reach forward for balance, and the torso travels down,
      // so neither is checked. Forward lean has its own, looser limit in
      // exercise_geometry.dart instead of the strict upright check.
      return _Profile(
        stationary: <PoseLandmarkType>{},
        working: _legs,
        torsoStill: false,
        upright: false,
        needsLegs: true,
      );

    case ExerciseType.hipAbduction:
    case ExerciseType.hamstringCurl:
      // Hands rest on a chair or the hips. The hips shift a little as the
      // weight moves onto the standing leg, so torso sway isn't checked.
      return _Profile(
        stationary: _arms,
        working: _legs,
        torsoStill: false,
        upright: true,
        needsLegs: true,
      );

    case ExerciseType.marching:
      // Arms may swing naturally while marching.
      return _Profile(
        stationary: <PoseLandmarkType>{},
        working: _legs,
        torsoStill: false,
        upright: true,
        needsLegs: true,
      );

    case ExerciseType.overheadRaise:
      return _Profile(
        stationary: _legs, // feet stay planted
        working: _arms,
        torsoStill: true,
        upright: true,
        needsArms: true,
      );
  }
}

class _Sample {
  final int t; // ms since epoch
  final Map<PoseLandmarkType, Offset> points;
  _Sample(this.t, this.points);
}

/// The checker's overall verdict, for change-only diagnostic logging.
enum _Verdict { ok, wrongForm, noPose, landmarksHidden }

class FormChecker {
  final ExerciseConfig exercise;
  final FormThresholds th;
  final _Profile _profile;
  final DiagnosticLogger _logger;

  FormChecker(
    this.exercise, {
    FormThresholds thresholds = FormThresholds.strict,
    DiagnosticLogger? logger,
  }) : th = thresholds,
       _profile = _profileFor(exercise.type),
       _logger = logger ?? DiagnosticLogger.I {
    _logger.info('FormChecker', 'Initialized', {
      'type': exercise.type.name,
      'thresholds': _presetName(thresholds),
      'stationaryRange': thresholds.stationaryRange,
      'torsoSwayRange': thresholds.torsoSwayRange,
      'maxWorkingSpeed': thresholds.maxWorkingSpeed,
      'maxTrunkLeanDeg': thresholds.maxTrunkLeanDeg,
      'maxUpperArmSwingDeg': thresholds.maxUpperArmSwingDeg,
      'confirmMs': thresholds.confirm.inMilliseconds,
      'holdMs': thresholds.hold.inMilliseconds,
    });
  }

  static String _presetName(FormThresholds t) {
    if (identical(t, FormThresholds.strict)) return 'strict';
    if (identical(t, FormThresholds.standard)) return 'standard';
    return 'custom';
  }

  static const double _smoothing = 0.6; // EMA weight of the newest frame
  static const int _gapMs = 300; // a fault that vanishes this long restarts

  final Queue<_Sample> _history = Queue<_Sample>();
  final Map<PoseLandmarkType, Offset> _smooth = {};
  double? _torsoLen;
  int _now = 0;

  final Map<FormIssueCode, int> _firstSeen = {};
  final Map<FormIssueCode, int> _lastSeen = {};
  final Map<FormIssueCode, FormIssue> _latest = {};

  // ---- Diagnostics: log CHANGES of the verdict, never every frame. ----
  // evaluate() runs ~15 times a second; one log per frame would flood the
  // console and the log file. These remember what was logged last.
  _Verdict _loggedVerdict = _Verdict.ok;
  int _loggedMask = 0; // issue-code bits (wrong form) or missing-group bits

  static final FormIssue _notInFrameIssue = FormIssue(
    code: FormIssueCode.notInFrame,
    message:
        'Please step into the frame and center your body to begin tracking.',
    landmarks: <PoseLandmarkType>{},
  );

  FormResult get _notInFrame =>
      FormResult(FormStatus.notInFrame, [_notInFrameIssue]);

  void reset() {
    if (_logger.isVerbose && _history.isNotEmpty) {
      _logger.verbose('FormChecker', 'State reset', {
        'samples': _history.length,
      });
    }
    _history.clear();
    _smooth.clear();
    _torsoLen = null;
    _firstSeen.clear();
    _lastSeen.clear();
    _latest.clear();
  }

  /// Call when ML Kit found nobody in the frame.
  FormResult evaluateNoPose() {
    reset();
    _logVerdict(_Verdict.noPose, 0);
    return _notInFrame;
  }

  FormResult evaluate(Map<PoseLandmarkType, PoseLandmark> lm, {DateTime? now}) {
    _now = (now ?? DateTime.now()).millisecondsSinceEpoch;

    final missing = _missingGroups(lm);
    if (missing != 0) {
      reset();
      _logVerdict(_Verdict.landmarksHidden, missing);
      return _notInFrame;
    }

    _ingest(lm);

    final raw = <FormIssue>[];
    final torso = _torsoLen;

    if (torso != null) {
      _checkStationary(raw, torso);
      _checkTorsoSway(raw, torso);
      _checkSpeed(raw, torso);
    }
    _checkTrunkLean(raw);
    _checkExerciseSpecific(raw, lm);

    final result = _stabilise(raw);
    if (result.isWrong) {
      var mask = 0;
      for (final issue in result.issues) {
        mask |= 1 << issue.code.index;
      }
      _logVerdict(_Verdict.wrongForm, mask);
    } else {
      _logVerdict(_Verdict.ok, 0);
    }
    return result;
  }

  /// Logs the checker's own verdict when it changes. "Not in frame" is
  /// info level and names the missing body parts, because that is the most
  /// common "why isn't it counting?" question. Wrong-form changes are
  /// verbose here: the screen logs its final (merged, filtered) verdict.
  void _logVerdict(_Verdict verdict, int mask) {
    if (verdict == _loggedVerdict && mask == _loggedMask) return;
    _loggedVerdict = verdict;
    _loggedMask = mask;
    switch (verdict) {
      case _Verdict.noPose:
        _logger.info('FormChecker', 'No pose detected', {
          'type': exercise.type.name,
        });
      case _Verdict.landmarksHidden:
        _logger.info('FormChecker', 'Required landmarks not visible', {
          'type': exercise.type.name,
          'missing': _groupNames(mask),
          'minLikelihood': th.minLikelihood,
        });
      case _Verdict.wrongForm:
        if (_logger.isVerbose) {
          _logger.verbose('FormChecker', 'Form issues changed', {
            'issues': [
              for (final code in FormIssueCode.values)
                if (mask & (1 << code.index) != 0) code.name,
            ],
          });
        }
      case _Verdict.ok:
        _logger.verbose('FormChecker', 'Form ok');
    }
  }

  // -------------------------------------------------------------------------
  // Visibility
  // -------------------------------------------------------------------------

  bool _ok(PoseLandmark? p) => p != null && p.likelihood >= th.minLikelihood;

  // Bits for [_missingGroups]; names are what the log shows.
  static const int _missShoulders = 1 << 0;
  static const int _missHips = 1 << 1;
  static const int _missKnees = 1 << 2;
  static const int _missAnkles = 1 << 3;
  static const int _missElbows = 1 << 4;
  static const int _missWrists = 1 << 5;
  static const Map<int, String> _groupLabels = {
    _missShoulders: 'shoulders',
    _missHips: 'hips',
    _missKnees: 'knees',
    _missAnkles: 'ankles',
    _missElbows: 'elbows',
    _missWrists: 'wrists',
  };

  static List<String> _groupNames(int mask) => [
    for (final entry in _groupLabels.entries)
      if (mask & entry.key != 0) entry.value,
  ];

  /// 0 when everything this exercise needs is confidently visible;
  /// otherwise one bit per missing body-part group. (An int, not a list, so
  /// the every-frame check allocates nothing.)
  int _missingGroups(Map<PoseLandmarkType, PoseLandmark> lm) {
    // At least one side of each pair must be visible (a side-on camera
    // usually hides the far limb).
    bool pair(PoseLandmarkType l, PoseLandmarkType r) =>
        _ok(lm[l]) || _ok(lm[r]);

    var missing = 0;
    if (!pair(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder)) {
      missing |= _missShoulders;
    }
    if (!pair(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip)) {
      missing |= _missHips;
    }
    if (_profile.needsLegs) {
      if (!pair(PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee)) {
        missing |= _missKnees;
      }
      if (!pair(PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle)) {
        missing |= _missAnkles;
      }
    }
    if (_profile.needsArms) {
      if (!pair(PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow)) {
        missing |= _missElbows;
      }
      if (!pair(PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist)) {
        missing |= _missWrists;
      }
    }
    return missing;
  }

  // -------------------------------------------------------------------------
  // History / smoothing
  // -------------------------------------------------------------------------

  void _ingest(Map<PoseLandmarkType, PoseLandmark> lm) {
    final sample = <PoseLandmarkType, Offset>{};
    for (final e in lm.entries) {
      if (!_ok(e.value)) {
        _smooth.remove(e.key);
        continue;
      }
      final raw = Offset(e.value.x, e.value.y);
      final prev = _smooth[e.key];
      final s = prev == null ? raw : prev + (raw - prev) * _smoothing;
      _smooth[e.key] = s;
      sample[e.key] = s;
    }
    _history.add(_Sample(_now, sample));

    final cutoff = _now - th.window.inMilliseconds - 300;
    while (_history.isNotEmpty && _history.first.t < cutoff) {
      _history.removeFirst();
    }

    final s = _meanOf(_shoulders);
    final h = _meanOf(_hips);
    if (s != null && h != null) {
      final len = (s - h).distance;
      if (len > 20) {
        // slow EMA so one noisy frame can't change the yardstick
        _torsoLen = _torsoLen == null ? len : _torsoLen! * 0.9 + len * 0.1;
      }
    }
  }

  Offset? _meanOf(Iterable<PoseLandmarkType> types) {
    var sum = Offset.zero;
    var n = 0;
    for (final t in types) {
      final p = _smooth[t];
      if (p != null) {
        sum += p;
        n++;
      }
    }
    return n == 0 ? null : sum / n.toDouble();
  }

  /// How far [type] wandered inside the window, in torso lengths.
  double? _range(PoseLandmarkType type, double torso) {
    final cutoff = _now - th.window.inMilliseconds;
    double? minX, maxX, minY, maxY;
    var n = 0;
    for (final s in _history) {
      if (s.t < cutoff) continue;
      final p = s.points[type];
      if (p == null) continue;
      minX = minX == null ? p.dx : min(minX, p.dx);
      maxX = maxX == null ? p.dx : max(maxX, p.dx);
      minY = minY == null ? p.dy : min(minY, p.dy);
      maxY = maxY == null ? p.dy : max(maxY, p.dy);
      n++;
    }
    if (n < 3) {
      return null; // not enough evidence yet (3 keeps it working at low fps)
    }
    return Offset(maxX! - minX!, maxY! - minY!).distance / torso;
  }

  /// Speed of [type] over roughly the last 120-500 ms, in torso lengths / s.
  double? _speed(PoseLandmarkType type, double torso) {
    if (_history.isEmpty) return null;
    final newest = _history.last.points[type];
    if (newest == null) return null;
    for (final s in _history) {
      final dt = _now - s.t;
      final p = s.points[type];
      if (dt >= 120 && dt <= 500 && p != null) {
        return (newest - p).distance / torso / (dt / 1000.0);
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Checks
  // -------------------------------------------------------------------------

  PoseLandmarkType _firstOf(
    Set<PoseLandmarkType> set, [
    PoseLandmarkType? prefer,
  ]) {
    if (prefer != null && set.contains(prefer)) return prefer;
    return set.first;
  }

  /// Limbs that should stay put but wander (flailing arms, stepping feet).
  void _checkStationary(List<FormIssue> out, double torso) {
    final armsBad = <PoseLandmarkType>{};
    final legsBad = <PoseLandmarkType>{};
    for (final t in _profile.stationary) {
      final r = _range(t, torso);
      if (r == null || r <= th.stationaryRange) continue;
      (_arms.contains(t) ? armsBad : legsBad).add(t);
    }
    if (armsBad.isNotEmpty) {
      out.add(
        FormIssue(
          code: FormIssueCode.armsMoving,
          message: 'Arms are moving too much. Keep them still.',
          landmarks: armsBad,
          anchor: _firstOf(armsBad, PoseLandmarkType.rightWrist),
        ),
      );
    }
    if (legsBad.isNotEmpty) {
      out.add(
        FormIssue(
          code: FormIssueCode.legsMoving,
          message: 'Keep your feet and legs still.',
          landmarks: legsBad,
          anchor: _firstOf(legsBad, PoseLandmarkType.rightAnkle),
        ),
      );
    }
  }

  void _checkTorsoSway(List<FormIssue> out, double torso) {
    if (!_profile.torsoStill) return;
    final ranges = <double>[];
    for (final t in _torso) {
      final r = _range(t, torso);
      if (r != null) ranges.add(r);
    }
    if (ranges.length < 2) return;
    ranges.sort();
    // Median, so one jittery landmark can't trigger it on its own.
    final median = ranges[(ranges.length - 1) ~/ 2];
    if (median > th.torsoSwayRange) {
      out.add(
        FormIssue(
          code: FormIssueCode.bodySway,
          message: 'Body is swaying. Stay steady.',
          landmarks: Set.of(_torso),
          anchor: _smooth.containsKey(PoseLandmarkType.leftShoulder)
              ? PoseLandmarkType.leftShoulder
              : PoseLandmarkType.rightShoulder,
        ),
      );
    }
  }

  void _checkSpeed(List<FormIssue> out, double torso) {
    final fast = <PoseLandmarkType>{};
    for (final t in _profile.working) {
      final v = _speed(t, torso);
      if (v != null && v > th.maxWorkingSpeed) fast.add(t);
    }
    if (fast.isNotEmpty) {
      out.add(
        FormIssue(
          code: FormIssueCode.tooFast,
          message: 'Too fast. Slow down and control the movement.',
          landmarks: fast,
          anchor: fast.first,
        ),
      );
    }
  }

  void _checkTrunkLean(List<FormIssue> out) {
    if (!_profile.upright) return;
    final s = _meanOf(_shoulders);
    final h = _meanOf(_hips);
    if (s == null || h == null) return;
    final d = s - h; // image y grows downward, so "up" is negative dy
    final lean = atan2(d.dx.abs(), -d.dy) * 180 / pi;
    if (lean > th.maxTrunkLeanDeg) {
      out.add(
        FormIssue(
          code: FormIssueCode.trunkLean,
          message: 'Your back is bent. Straighten your body.',
          landmarks: Set.of(_torso),
          anchor: _smooth.containsKey(PoseLandmarkType.leftShoulder)
              ? PoseLandmarkType.leftShoulder
              : PoseLandmarkType.rightShoulder,
        ),
      );
    }
  }

  double? _angle(
    Map<PoseLandmarkType, PoseLandmark> lm,
    PoseLandmarkType a,
    PoseLandmarkType b,
    PoseLandmarkType c,
  ) {
    final p1 = lm[a], p2 = lm[b], p3 = lm[c];
    if (!_ok(p1) || !_ok(p2) || !_ok(p3)) return null;
    return ExerciseGeometry.jointAngle(p1!, p2!, p3!);
  }

  void _checkExerciseSpecific(
    List<FormIssue> out,
    Map<PoseLandmarkType, PoseLandmark> lm,
  ) {
    switch (exercise.type) {
      case ExerciseType.kneeExtension:
        final l = _angle(
          lm,
          PoseLandmarkType.leftHip,
          PoseLandmarkType.leftKnee,
          PoseLandmarkType.leftAnkle,
        );
        final r = _angle(
          lm,
          PoseLandmarkType.rightHip,
          PoseLandmarkType.rightKnee,
          PoseLandmarkType.rightAnkle,
        );
        // Only when the other leg is really seen as a separate leg: from
        // the side, ML Kit draws the hidden far leg on top of the lifted
        // one (see ExerciseGeometry.kneeExtensionLegs).
        if (l != null && r != null && ExerciseGeometry.anklesApart(lm)) {
          final working = max(l, r);
          final resting = min(l, r);
          // Both legs straightened = cheating the rep.
          if (working >= exercise.targetAngle && resting >= 120) {
            final leftIsResting = l < r;
            out.add(
              FormIssue(
                code: FormIssueCode.otherLeg,
                message: 'Keep your other leg bent and still.',
                landmarks: {
                  leftIsResting
                      ? PoseLandmarkType.leftKnee
                      : PoseLandmarkType.rightKnee,
                  leftIsResting
                      ? PoseLandmarkType.leftAnkle
                      : PoseLandmarkType.rightAnkle,
                },
                anchor: leftIsResting
                    ? PoseLandmarkType.leftKnee
                    : PoseLandmarkType.rightKnee,
              ),
            );
          }
        }
        break;

      case ExerciseType.straightLegRaise:
        // Raised leg must stay straight.
        for (final side in const [true, false]) {
          final sh = side
              ? PoseLandmarkType.leftShoulder
              : PoseLandmarkType.rightShoulder;
          final hp = side
              ? PoseLandmarkType.leftHip
              : PoseLandmarkType.rightHip;
          final kn = side
              ? PoseLandmarkType.leftKnee
              : PoseLandmarkType.rightKnee;
          final an = side
              ? PoseLandmarkType.leftAnkle
              : PoseLandmarkType.rightAnkle;
          final hipAngle = _angle(lm, sh, hp, kn);
          final kneeAngle = _angle(lm, hp, kn, an);
          if (hipAngle == null || kneeAngle == null) continue;
          final lifted = hipAngle < exercise.restAngle - 10;
          if (lifted && kneeAngle < 150) {
            out.add(
              FormIssue(
                code: FormIssueCode.kneeBent,
                message: 'Keep your knee straight.',
                landmarks: {kn, an},
                anchor: kn,
              ),
            );
          }
          break; // first side with a full chain is enough
        }
        break;

      case ExerciseType.bicepCurl:
        {
          // A curl only bends the elbow. If the upper arm swings away from the
          // trunk, the patient is doing something else (circling, shrugging,
          // swinging) even if the wrist speed looks harmless.
          final swung = <PoseLandmarkType>{};
          void side(
            PoseLandmarkType hp,
            PoseLandmarkType sh,
            PoseLandmarkType el,
          ) {
            final a = _angle(lm, hp, sh, el);
            if (a != null && a > th.maxUpperArmSwingDeg) swung.add(el);
          }

          side(
            PoseLandmarkType.leftHip,
            PoseLandmarkType.leftShoulder,
            PoseLandmarkType.leftElbow,
          );
          side(
            PoseLandmarkType.rightHip,
            PoseLandmarkType.rightShoulder,
            PoseLandmarkType.rightElbow,
          );
          if (swung.isNotEmpty) {
            out.add(
              FormIssue(
                code: FormIssueCode.elbowDrift,
                message:
                    'Keep your elbows pinned to your sides. Only bend the elbow.',
                landmarks: swung,
                anchor: swung.first,
              ),
            );
          }
        }
        break;

      case ExerciseType.forwardRaise:
      case ExerciseType.sideRaise:
      case ExerciseType.overheadRaise:
        {
          // Assumes straight-arm raises. Delete this case if your clinic's
          // protocol allows a bent elbow.
          final bent = <PoseLandmarkType>{};
          void side(
            PoseLandmarkType sh,
            PoseLandmarkType el,
            PoseLandmarkType wr,
          ) {
            final a = _angle(lm, sh, el, wr);
            if (a != null && a < th.minStraightArmDeg) bent.add(el);
          }

          side(
            PoseLandmarkType.leftShoulder,
            PoseLandmarkType.leftElbow,
            PoseLandmarkType.leftWrist,
          );
          side(
            PoseLandmarkType.rightShoulder,
            PoseLandmarkType.rightElbow,
            PoseLandmarkType.rightWrist,
          );
          if (bent.isNotEmpty) {
            out.add(
              FormIssue(
                code: FormIssueCode.armBent,
                message: 'Keep your arm straight.',
                landmarks: bent,
                anchor: bent.first,
              ),
            );
          }
        }
        break;

      default:
        break;
    }
  }

  // -------------------------------------------------------------------------
  // Debounce: confirm faults before showing, hold them briefly after
  // -------------------------------------------------------------------------

  FormResult _stabilise(List<FormIssue> raw) {
    for (final i in raw) {
      final last = _lastSeen[i.code];
      if (last == null || _now - last > _gapMs) _firstSeen[i.code] = _now;
      _lastSeen[i.code] = _now;
      _latest[i.code] = i;
    }

    final holdMs = th.hold.inMilliseconds;
    final confirmMs = th.confirm.inMilliseconds;
    final active = <FormIssue>[];

    for (final code in _lastSeen.keys.toList()) {
      final last = _lastSeen[code]!;
      if (_now - last > holdMs) {
        _lastSeen.remove(code);
        _firstSeen.remove(code);
        _latest.remove(code);
        continue;
      }
      if (last - _firstSeen[code]! >= confirmMs) {
        active.add(_latest[code]!);
      }
    }

    if (active.isEmpty) return FormResult.ok;
    active.sort((a, b) => a.code.index.compareTo(b.code.index));
    return FormResult(FormStatus.wrongForm, active);
  }
}