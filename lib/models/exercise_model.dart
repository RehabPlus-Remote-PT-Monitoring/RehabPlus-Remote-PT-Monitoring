// lib/models/exercise_model.dart
import 'prescription.dart';

enum ExerciseType {
  kneeExtension,
  straightLegRaise,
  kneeFlexion,
  heelSlide,
  forwardRaise,
  sideRaise,
  forwardPush,
  // --- new ---
  bicepCurl,
  sitToStand,
  gluteBridge,
  // hold exercises (timed)
  singleLegBalance,
  wallSit,
  // --- second batch (geometry in lib/services/exercise_geometry.dart) ---
  miniSquat,
  hipAbduction,
  hamstringCurl,
  marching,
  overheadRaise,
}

/// Where the camera must be for the angles to be measurable. The camera
/// sees in 2D, so a movement towards or away from it can't be measured.
enum CameraView {
  /// The patient faces the camera.
  front,

  /// The patient is side-on (profile) to the camera.
  side,

  /// Either works.
  either;

  /// Short label for the exercise card.
  String get label => switch (this) {
    CameraView.front => 'Face the camera',
    CameraView.side => 'Side-on to the camera',
    CameraView.either => 'Front or side-on',
  };
}

enum ExerciseDifficulty {
  easy,
  moderate,
  hard;

  String get label => switch (this) {
    ExerciseDifficulty.easy => 'Easy',
    ExerciseDifficulty.moderate => 'Moderate',
    ExerciseDifficulty.hard => 'Hard',
  };
}

class ExerciseConfig {
  final ExerciseType type;
  final String title;
  final String category;
  final String repsText;
  final double targetAngle;
  final double restAngle;

  /// For hold exercises: how many seconds one hold must last.
  /// 0 means a normal rep-based exercise.
  final int holdSeconds;

  /// Hard limit for the session: how many reps (or, for hold exercises,
  /// how many completed holds) finish the exercise.
  final int targetReps;

  final ExerciseDifficulty difficulty;
  final int estimatedMinutes;

  /// Camera position the exercise is measured from (see [CameraView]).
  final CameraView cameraView;

  /// One-sentence set-up instruction shown before and at the start of the
  /// exercise ("Stand side-on to the camera, ...").
  final String setupTip;

  /// The therapist assignment this config came from, if any.
  final Prescription? prescription;

  const ExerciseConfig({
    required this.type,
    required this.title,
    required this.category,
    required this.repsText,
    required this.targetAngle,
    required this.restAngle,
    required this.targetReps,
    required this.difficulty,
    required this.estimatedMinutes,
    required this.cameraView,
    required this.setupTip,
    this.holdSeconds = 0,
    this.prescription,
  });

  bool get isHold => holdSeconds > 0;

  /// Returns a copy with just the therapist-assignable fields overridden.
  /// Pose-detection angles (targetAngle/restAngle) are never overridden —
  /// they're calibrated per exercise type in code, not set by a therapist.
  ExerciseConfig copyWith({
    int? targetReps,
    int? holdSeconds,
    String? repsText,
    Prescription? prescription,
  }) {
    return ExerciseConfig(
      type: type,
      title: title,
      category: category,
      repsText: repsText ?? this.repsText,
      targetAngle: targetAngle,
      restAngle: restAngle,
      difficulty: difficulty,
      estimatedMinutes: estimatedMinutes,
      cameraView: cameraView,
      setupTip: setupTip,
      targetReps: targetReps ?? this.targetReps,
      holdSeconds: holdSeconds ?? this.holdSeconds,
      prescription: prescription ?? this.prescription,
    );
  }
}

final List<ExerciseConfig> availableExercises = [
  // ---------------- Lower body ----------------
  const ExerciseConfig(
    type: ExerciseType.kneeExtension,
    title: 'Knee Extension',
    category: 'MCL Recovery',
    cameraView: CameraView.side,
    setupTip: 'Sit on a chair side-on to the camera, with both legs in view.',
    repsText: '1 Set | 10 Reps',
    targetReps: 10,
    difficulty: ExerciseDifficulty.moderate,
    estimatedMinutes: 12,
    // Tuned from a real session (seated side-on): the knee read ~105 deg
    // at rest and 165-170 deg fully extended. The old 110 -> 125 band was
    // only 15 deg wide, inside the ~10 deg frame-to-frame landmark jitter,
    // so jitter alone made dozens of "too fast" mini-reps. 120 -> 150 is
    // well clear of the jitter and still easy to reach (the pose model
    // rarely reads a full 180).
    targetAngle: 150.0, // extended
    restAngle: 120.0, // seated, knee relaxed (rest zone ends ~129 deg)
  ),
  const ExerciseConfig(
    type: ExerciseType.straightLegRaise,
    title: 'Straight Leg Raise',
    category: 'MCL Recovery',
    cameraView: CameraView.side,
    setupTip: 'Lie on your back side-on to the camera, with your whole body in view.',
    repsText: '1 Set | 10 Reps',
    targetReps: 10,
    difficulty: ExerciseDifficulty.moderate,
    estimatedMinutes: 12,
    targetAngle: 140.0, // Hip flexion target
    restAngle: 170.0,
  ),
  const ExerciseConfig(
    type: ExerciseType.kneeFlexion,
    title: 'Knee Flexion',
    category: 'MCL Recovery',
    cameraView: CameraView.side,
    setupTip: 'Lie face down side-on to the camera, with your whole body in view.',
    repsText: '1 Set | 10 Reps',
    targetReps: 10,
    difficulty: ExerciseDifficulty.easy,
    estimatedMinutes: 10,
    targetAngle: 90.0, // Fully bent knee
    restAngle: 160.0,
  ),
  const ExerciseConfig(
    type: ExerciseType.heelSlide,
    title: 'Heel Slides',
    category: 'MCL Recovery',
    cameraView: CameraView.side,
    setupTip: 'Lie on your back side-on to the camera, with your whole body in view.',
    repsText: '1 Set | 10 Reps',
    targetReps: 10,
    difficulty: ExerciseDifficulty.easy,
    estimatedMinutes: 10,
    targetAngle: 90.0,
    restAngle: 160.0,
  ),
  const ExerciseConfig(
    type: ExerciseType.sitToStand,
    title: 'Sit-to-Stand',
    category: 'Lower Body',
    cameraView: CameraView.side,
    setupTip: 'Sit on a chair side-on to the camera, with your whole body in view.',
    repsText: '1 Set | 10 Reps',
    targetReps: 10,
    difficulty: ExerciseDifficulty.moderate,
    estimatedMinutes: 15,
    targetAngle: 165.0, // standing, knees straight
    restAngle: 110.0, // seated
  ),
  const ExerciseConfig(
    type: ExerciseType.gluteBridge,
    title: 'Glute Bridge',
    category: 'Core & Hips',
    cameraView: CameraView.side,
    setupTip: 'Lie on your back side-on to the camera, knees bent, whole body in view.',
    repsText: '1 Set | 10 Reps',
    targetReps: 10,
    difficulty: ExerciseDifficulty.easy,
    estimatedMinutes: 10,
    targetAngle: 160.0, // hips lifted, body in a line
    restAngle: 135.0, // lying, knees bent
  ),

  // ---------------- Upper body ----------------
  const ExerciseConfig(
    type: ExerciseType.bicepCurl,
    title: 'Bicep Curl',
    category: 'Arm Rehabilitation',
    cameraView: CameraView.front,
    setupTip: 'Stand facing the camera, with your upper body and arms in view.',
    repsText: '1 Set | 10 Reps',
    targetReps: 10,
    difficulty: ExerciseDifficulty.easy,
    estimatedMinutes: 8,
    targetAngle: 70.0, // elbow bent
    restAngle: 140.0, // arm nearly straight
  ),
  const ExerciseConfig(
    type: ExerciseType.forwardRaise,
    title: 'Forward Raise',
    category: 'Arm Rehabilitation',
    cameraView: CameraView.side,
    setupTip: 'Stand side-on to the camera, with your upper body and arm in view.',
    repsText: '1 Set | 10 Reps',
    targetReps: 10,
    difficulty: ExerciseDifficulty.moderate,
    estimatedMinutes: 10,
    targetAngle: 90.0, // Arm parallel to ground
    restAngle: 20.0,
  ),
  const ExerciseConfig(
    type: ExerciseType.sideRaise,
    title: 'Side Raise',
    category: 'Arm Rehabilitation',
    cameraView: CameraView.front,
    setupTip: 'Stand facing the camera, with your upper body and both arms in view.',
    repsText: '1 Set | 10 Reps',
    targetReps: 10,
    difficulty: ExerciseDifficulty.moderate,
    estimatedMinutes: 10,
    targetAngle: 90.0,
    restAngle: 20.0,
  ),
  const ExerciseConfig(
    type: ExerciseType.forwardPush,
    title: 'Forward Push',
    category: 'Arm Rehabilitation',
    cameraView: CameraView.side,
    setupTip: 'Stand side-on to the camera, with your upper body and arm in view.',
    repsText: '1 Set | 10 Reps',
    targetReps: 10,
    difficulty: ExerciseDifficulty.moderate,
    estimatedMinutes: 10,
    targetAngle: 155.0, // Extended elbow
    restAngle: 80.0, // Bent elbow near chest
  ),

  // ---------------- Timed holds ----------------
  const ExerciseConfig(
    type: ExerciseType.singleLegBalance,
    title: 'Single-Leg Balance',
    category: 'Balance',
    cameraView: CameraView.front,
    setupTip: 'Stand facing the camera, with your whole body in view.',
    repsText: '3 Holds | 10 sec',
    targetReps: 3,
    difficulty: ExerciseDifficulty.hard,
    estimatedMinutes: 8,
    targetAngle: 0.0, // not used for holds
    restAngle: 0.0, // not used for holds
    holdSeconds: 10,
  ),
  const ExerciseConfig(
    type: ExerciseType.wallSit,
    title: 'Wall Sit',
    category: 'Lower Body',
    cameraView: CameraView.side,
    setupTip: 'Stand with your back to a wall, side-on to the camera, whole body in view.',
    repsText: '3 Holds | 20 sec',
    targetReps: 3,
    difficulty: ExerciseDifficulty.hard,
    estimatedMinutes: 10,
    targetAngle: 90.0, // knee angle to hold (+/- 20 degrees)
    restAngle: 0.0, // not used for holds
    holdSeconds: 20,
  ),

  // ---------------- Second batch ----------------
  // Measured in lib/services/exercise_geometry.dart. Angles are starting
  // points from general physiotherapy guidance; confirm them with the
  // clinic and tune on a phone. The camera view each one needs is noted.
  const ExerciseConfig(
    type: ExerciseType.miniSquat,
    title: 'Mini Squat',
    category: 'Lower Body',
    cameraView: CameraView.either,
    setupTip: 'Stand facing the camera (best) or side-on, with your whole body in view.',
    repsText: '1 Set | 10 Reps',
    targetReps: 10,
    difficulty: ExerciseDifficulty.moderate,
    estimatedMinutes: 10,
    // Front or side view. Knee angle: ~45 deg of bend, not a full squat.
    targetAngle: 135.0,
    restAngle: 170.0, // standing
  ),
  const ExerciseConfig(
    type: ExerciseType.hipAbduction,
    title: 'Standing Hip Abduction',
    category: 'Core & Hips',
    cameraView: CameraView.front,
    setupTip: 'Stand facing the camera, holding a chair, with your whole body in view.',
    repsText: '1 Set | 10 Reps',
    targetReps: 10,
    difficulty: ExerciseDifficulty.moderate,
    estimatedMinutes: 10,
    // Front view. Degrees the leg is out to the side from the body line.
    targetAngle: 30.0,
    restAngle: 8.0, // feet together
  ),
  const ExerciseConfig(
    type: ExerciseType.hamstringCurl,
    title: 'Standing Hamstring Curl',
    category: 'Lower Body',
    cameraView: CameraView.side,
    setupTip: 'Stand side-on to the camera, holding a chair, with your whole body in view.',
    repsText: '1 Set | 10 Reps',
    targetReps: 10,
    difficulty: ExerciseDifficulty.easy,
    estimatedMinutes: 10,
    // Side view. Knee angle of the working leg: heel toward the buttock.
    targetAngle: 90.0,
    restAngle: 165.0, // standing, leg straight
  ),
  const ExerciseConfig(
    type: ExerciseType.marching,
    title: 'Marching in Place',
    category: 'Lower Body',
    cameraView: CameraView.side,
    setupTip: 'Stand side-on to the camera, with your whole body in view.',
    repsText: '1 Set | 10 Reps',
    targetReps: 10,
    difficulty: ExerciseDifficulty.easy,
    estimatedMinutes: 8,
    // Side view. Hip angle (shoulder-hip-knee) of the lifted leg; each
    // knee lift is one rep, alternating legs.
    targetAngle: 110.0,
    restAngle: 170.0, // standing
  ),
  const ExerciseConfig(
    type: ExerciseType.overheadRaise,
    title: 'Overhead Arm Raise',
    category: 'Arm Rehabilitation',
    cameraView: CameraView.side,
    setupTip: 'Stand side-on to the camera, with your upper body and arm in view.',
    repsText: '1 Set | 10 Reps',
    targetReps: 10,
    difficulty: ExerciseDifficulty.easy,
    estimatedMinutes: 10,
    // Side view. Arm against the body (hip-shoulder-wrist), up beside the
    // ear. Forward Raise stops at shoulder height; this one goes overhead.
    targetAngle: 150.0,
    restAngle: 30.0, // arm by the side
  ),
];
