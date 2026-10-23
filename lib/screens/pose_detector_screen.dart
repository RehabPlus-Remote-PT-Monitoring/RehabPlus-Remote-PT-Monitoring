// lib/screens/pose_detector_screen.dart
//
// The live exercise screen: camera preview, ML Kit pose detection, form
// checking, rep / hold counting, feedback (sound, vibration, voice) and the
// end-of-session pain check-in.
//
// Frame pipeline (one processed frame at a time)
// -----------------------------------------------
//   camera plugin  --CameraImage-->  _onCameraFrame
//     - drops the frame if the screen is gone, the session is over, the
//       frame belongs to an old camera (switch / pause), ML Kit is still
//       busy with the previous frame (back-pressure) or the ~15 fps cap
//       hasn't elapsed yet. Every drop is counted by reason.
//   _processFrame
//     - wraps the NV21 bytes for ML Kit WITHOUT copying them (Android
//       delivers NV21 as one plane), awaits ML Kit, then runs the form
//       checker and the rep logic, then does ONE setState.
//     - any exception is caught and counted; the stream keeps running.
//
// Why ML Kit is not moved to a Dart isolate ("multithreading")
//   - ML Kit already runs the model on its own native threads; the UI isolate
//     only awaits a platform-channel reply, so it is never blocked by
//     inference.
//   - Platform plugins (ML Kit, camera, audio, TTS) only work on the root
//     isolate, so a worker isolate couldn't call ML Kit anyway.
//   - Moving each frame to an isolate would add a copy of every frame
//     (~115 KB at 15 fps) for nothing. The pure-Dart work that IS left
//     (angles, form checks on 33 landmarks) takes well under a millisecond.
//
// Diagnostics (see lib/core/diagnostic_logger.dart; grep RPLOG in logcat)
//   PoseCamera   camera init/failure/switch, first frame format, lifecycle
//   PosePipeline 5-second throughput windows, frame errors, ML Kit stalls,
//                detector shutdown and the end-of-session summary
//   PoseForm     form status changes (ok / wrong form / not in frame)
//   RepCycle     rep counted / rejected (with reason), holds, countdown
//   PoseAudio / PoseTts / PoseHaptics   feedback channel problems
//   PoseSession  session saved / save failed
//   Per-frame events are verbose only (--dart-define=RP_LOG_LEVEL=verbose).
//
// Tuning knobs are all in the "TUNING" block below.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
// WriteBuffer: only used for multi-plane camera formats (not Android NV21).
import 'package:flutter/foundation.dart' show WriteBuffer;

import 'package:camera/camera.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../models/exercise_model.dart';
import '../models/session.dart';
import '../services/app_provider.dart';
import '../services/app_settings.dart';
import '../services/exercise_geometry.dart';
import '../services/form_checker.dart';
import '../widgets/pose_painter.dart';

class PoseDetectorScreen extends StatefulWidget {
  final ExerciseConfig selectedExercise;
  const PoseDetectorScreen({super.key, required this.selectedExercise});

  @override
  State<PoseDetectorScreen> createState() => _PoseDetectorScreenState();
}

class _PoseDetectorScreenState extends State<PoseDetectorScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];
  late PoseDetector _poseDetector;
  bool _isProcessing = false;
  bool _initializingCamera = false;
  String? _cameraError;

  // ---------------------------------------------------------------------
  // Pipeline / concurrency bookkeeping
  // ---------------------------------------------------------------------

  static final DiagnosticLogger _log = DiagnosticLogger.I;

  /// Bumped whenever a camera is created or torn down. Each frame callback
  /// remembers the generation it was registered with, so frames (and
  /// in-flight ML Kit results) from an old camera are ignored after a camera
  /// switch or an app pause instead of advancing the new rep cycle.
  int _cameraGeneration = 0;

  /// Set when the app resumes while a camera init is still running (e.g.
  /// the permission prompt made the app "inactive"). The running init is
  /// superseded, so it schedules a fresh one when it finishes.
  bool _reinitCameraWhenDone = false;

  /// True between AppLifecycleState.inactive/paused and resumed.
  bool _appInBackground = false;

  /// True while a camera switch is tearing down / rebuilding (double-tap
  /// guard: the init flag alone leaves a gap during the dispose).
  bool _switchingCamera = false;

  /// True once dispose() started shutting ML Kit down: no new
  /// processImage call may start after this.
  bool _detectorClosing = false;

  /// Completes when the frame currently inside ML Kit has finished, so
  /// PoseDetector.close() never races an in-flight processImage.
  Completer<void>? _inFlightFrame;

  /// Monotonic clock for the frame throttle and latency (immune to wall
  /// clock changes, no DateTime allocation per frame).
  final Stopwatch _frameClock = Stopwatch()..start();
  int _processingStartedMs = 0;
  bool _stallReported = false;

  /// Counters for the periodic "Pipeline window" log and session summary.
  final PosePipelineStats _stats = PosePipelineStats();

  /// Only the first few frame errors are logged with a stack trace; the
  /// rest are counted in the pipeline window (avoids 15 logs per second).
  static const int _maxLoggedFrameErrors = 3;
  int _loggedFrameErrors = 0;

  bool _firstFrameLogged = false;
  int _cameraSwitches = 0;
  int _lifecyclePauses = 0;
  String _resolutionLabel = 'unknown';
  bool _summaryLogged = false;
  bool _endDialogOpen = false;

  /// Last form state that was logged, to log changes only (not per frame).
  FormStatus _loggedFormStatus = FormStatus.ok;
  int _loggedFormMask = 0;

  /// Rejected reps by rule and by issue code, for the session summary.
  final Map<String, int> _rejectRules = {};
  final Map<String, int> _rejectCodes = {};

  // ---------------------------------------------------------------------
  // TUNING
  // ---------------------------------------------------------------------

  /// Pose analysis cap (ms between processed frames). ~15 fps.
  static const int _minFrameIntervalMs = 66;

  /// false = whole frame visible (letterboxed). true = fill and crop.
  static const bool _coverPreview = false;

  /// Same numbers as FormThresholds.standard, except the elbow-swing limit
  /// is relaxed (was 45) so the arms don't have to be glued to your sides.
  static const FormThresholds _thresholds = FormThresholds(
    minLikelihood: 0.5,
    stationaryRange: 0.40,
    torsoSwayRange: 0.25,
    maxWorkingSpeed: 3.5,
    maxTrunkLeanDeg: 30,
    maxUpperArmSwingDeg: 55,
    minStraightArmDeg: 140,
    window: Duration(milliseconds: 800),
    confirm: Duration(milliseconds: 200),
    hold: Duration(milliseconds: 700),
    attemptProgress: 0.4,
  );

  /// Rest zone: a rep is "back at rest" once the joint has returned through
  /// this fraction of the range.
  static const double _restZone = 0.3;

  /// The rep is judged (counted/rejected, sound plays) as soon as the joint
  /// has come back this far toward rest after reaching the target
  /// (1.0 = at target, 0.0 = at rest). Higher = earlier feedback.
  static const double _commitProgress = 0.6;

  /// "Down" positions. The curl's elbow is ~170 deg when the arm hangs
  /// straight; the raises measure the arm against the body (hip-shoulder-wrist).
  static const double _curlRestAngle = 170.0;
  static const double _raiseRestAngle = 30.0;

  /// Anti-flail rules for rep-based exercises.
  static const int _minRepMs = 700; // leave-rest -> back toward rest
  static const int _faultFrameLimit = 3; // faulty frames allowed in one rep
  static const double _reArmProgress =
      0.7; // must drop below this to re-hit target

  /// Knee Extension: the other (resting) leg counts as "bent" below this
  /// knee angle. Only checked when that leg can really be seen.
  static const double _otherLegBentMaxDeg = 120.0;

  /// Extra per-exercise limits.
  static const double _raiseMaxDeg = 125.0; // arm above this = too high
  static const double _sitToStandMaxLeanDeg = 60.0;
  static const double _wallSitFaultDeg = 30.0; // off-target by this = red
  static const double _wallSitTolerance = 20.0; // counts as "in position"

  // ---------------------------------------------------------------------
  // Audio / haptics
  // ---------------------------------------------------------------------

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _audioReady = false;
  bool _hasVibrator = false;

  /// Loads the sound once so a rep never waits on disk/decoding.
  Future<void> _initAudio() async {
    try {
      await _audioPlayer.setAudioContext(
        AudioContextConfig(
          focus: AudioContextConfigFocus.mixWithOthers,
        ).build(),
      );
      await _audioPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setSource(AssetSource('successSound.mp3'));
      _audioReady = true;
      _log.info('PoseAudio', 'Success sound ready');
    } catch (e, st) {
      // Expected if the screen closed while loading (player disposed).
      if (mounted) {
        _log.warn('PoseAudio', 'Audio init failed', null, e, st);
      }
    }
  }

  void _playSuccessSound() {
    if (!_audioReady) return;
    // Fire and forget: never block the frame pipeline on audio.
    unawaited(
      _audioPlayer
          .stop()
          .then((_) => _audioPlayer.resume())
          .catchError(
            (Object e, StackTrace st) =>
                _log.warn('PoseAudio', 'Success sound failed', null, e, st),
          ),
    );
  }

  /// Vibrates without letting a plugin error escape as an unhandled
  /// asynchronous exception.
  void _vibrate({int duration = 100, List<int>? pattern}) {
    final Future<void> call = pattern == null
        ? Vibration.vibrate(duration: duration)
        : Vibration.vibrate(pattern: pattern);
    unawaited(
      call.catchError(
        (Object e, StackTrace st) =>
            _log.warn('PoseHaptics', 'Vibration failed', null, e, st),
      ),
    );
  }

  void _triggerFeedback() {
    if (_settings.repSound) _playSuccessSound();
    if (_settings.repVibration && _hasVibrator) {
      _vibrate(duration: 100);
    }
    if (_settings.voiceCues) _speak('$_repCounter', force: true);
  }

  /// Double buzz for wrong form / rejected rep (throttled so it can't spam).
  DateTime _lastBuzz = DateTime.fromMillisecondsSinceEpoch(0);
  void _triggerWrongFeedback() {
    final now = DateTime.now();
    if (now.difference(_lastBuzz).inMilliseconds < 1500) return;
    _lastBuzz = now;
    if (_settings.repVibration && _hasVibrator) {
      _vibrate(pattern: [0, 120, 80, 120]);
    }
  }

  // ---------------------------------------------------------------------
  // Spoken cues (Settings > Spoken cues)
  // ---------------------------------------------------------------------

  final AppSettings _settings = AppSettings.I;
  FlutterTts? _tts;
  String? _lastSpoken;
  DateTime _lastSpokenAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _initVoice() async {
    if (!_settings.voiceCues) return;
    final tts = FlutterTts();
    try {
      await tts.setLanguage('en-US');
      await tts.setSpeechRate(0.5);
      if (!mounted) {
        // Screen closed while the engine was starting: don't keep it.
        unawaited(_stopTts(tts));
        return;
      }
      _tts = tts;
      _log.info('PoseTts', 'Voice cues ready');
    } catch (e, st) {
      _log.warn('PoseTts', 'TTS init failed', null, e, st);
    }
  }

  Future<void> _stopTts(FlutterTts tts) async {
    try {
      await tts.stop();
    } catch (e, st) {
      _log.warn('PoseTts', 'TTS stop failed', null, e, st);
    }
  }

  /// Says [text]. Form tips are throttled (a new tip at most every 3 s, the
  /// same tip again after 8 s); [force] is for rep counts and the countdown.
  void _speak(String text, {bool force = false}) {
    final tts = _tts;
    if (tts == null) return;
    final now = DateTime.now();
    final since = now.difference(_lastSpokenAt).inMilliseconds;
    if (!force) {
      if (since < 3000) return;
      if (text == _lastSpoken && since < 8000) return;
    }
    _lastSpoken = text;
    _lastSpokenAt = now;
    unawaited(
      tts.stop().then((_) => tts.speak(text)).catchError((
        Object e,
        StackTrace st,
      ) {
        _log.warn('PoseTts', 'Speak failed', null, e, st);
        return null;
      }),
    );
  }

  // ---------------------------------------------------------------------
  // Start countdown (Settings > Countdown before counting)
  // ---------------------------------------------------------------------

  int _countdownLeft = 0;
  bool _countdownStarted = false;
  Timer? _countdownTimer;

  bool get _countingDown => _countdownLeft > 0;

  /// The small "where to stand" chip shows after the countdown until the
  /// patient's first attempt (counted or rejected), then gets out of the way.
  bool get _showSetupTip =>
      !_countingDown && _repCounter == 0 && _rejectedReps == 0;

  /// Runs once, when the camera first shows: reps aren't counted until it
  /// reaches zero, giving the patient time to get into position.
  void _startCountdown() {
    if (_countdownStarted) return;
    _countdownStarted = true;
    final seconds = _settings.countdownSeconds;
    if (seconds <= 0) return;
    setState(() => _countdownLeft = seconds);
    _log.info('RepCycle', 'Countdown started', {'seconds': seconds});
    _speak('$seconds', force: true);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _countdownLeft--);
      if (_countdownLeft > 0) {
        _speak('$_countdownLeft', force: true);
      } else {
        t.cancel();
        _resetTracking(); // start the first rep from a clean slate
        _log.info('RepCycle', 'Countdown finished', {'seconds': seconds});
        _speak('Go', force: true);
      }
    });
  }

  // ---------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------

  int _repCounter = 0;
  String _stage = "down";
  double _currentAngle = 0.0;

  // ---- Form checking ----
  late final FormChecker _checker;
  FormResult _form = FormResult.ok;
  bool _wasWrong = false;

  // One-off events ("rep not counted", "leg too low") that should stay on
  // screen for a moment after the frame that caused them.
  FormIssue? _flash;
  DateTime? _flashUntil;

  // Debounce for the extra per-exercise faults defined in this file.
  final Map<FormIssueCode, int> _xFirst = {};
  final Map<FormIssueCode, int> _xLast = {};
  final Map<FormIssueCode, FormIssue> _xIssue = {};

  // ---- Rep cycle (a rep = leave rest, reach target, come back) ----
  bool _cycleActive = false;
  bool _awaitRest = false; // rep already judged; wait until fully at rest
  DateTime? _cycleStart;
  FormIssue? _cycleViolation; // first debounced form fault seen during the rep
  FormIssue? _cycleFaultIssue; // first raw (instant) fault seen during the rep
  int _cycleFaultFrames = 0; // frames with a raw fault during the rep
  int _targetHits = 0; // times the target was reached during the rep
  bool _atTarget = false;
  double _maxProgress = 0.0; // furthest toward target this rep (0..1+)
  double? _baseline; // the patient's own resting angle
  int _rejectedReps = 0;
  final List<double> _repScores = []; // 1.0 = clean rep, 0.0 = rejected rep

  // ---- Session completion state ----
  bool _isSessionComplete = false;
  late final DateTime _sessionStart;

  // ---- Hold-timer state (single-leg balance, wall sit, ...) ----
  DateTime? _holdStart;
  DateTime? _lostSince;
  bool _holdCounted = false;
  double _holdElapsed = 0.0;
  static const Duration _holdGrace = Duration(milliseconds: 700);

  // Visual Overlay states
  List<Pose> _detectedPoses = [];
  Size? _imageSize;
  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  late CameraLensDirection _lensDirection = AppSettings.I.useBackCamera
      ? CameraLensDirection.back
      : CameraLensDirection.front;

  /// Front camera preview is a selfie mirror while ML Kit data is not, so the
  /// skeleton is flipped. The app-bar button is an on-device override.
  bool _mirrorSkeleton = true;

  /// Live faults plus any recent one-off event.
  FormResult get _effectiveForm {
    final flash = _flash;
    final until = _flashUntil;
    if (flash == null || until == null || DateTime.now().isAfter(until)) {
      return _form;
    }
    return _form.plus(flash);
  }

  void _flashIssue(FormIssue issue) {
    _flash = issue;
    _flashUntil = DateTime.now().add(const Duration(milliseconds: 1800));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionStart = DateTime.now();
    _checker = FormChecker(widget.selectedExercise, thresholds: _thresholds);
    _log.info('PosePipeline', 'Exercise screen opened', {
      'exercise': widget.selectedExercise.type.name,
      'targetReps': widget.selectedExercise.targetReps,
      'holdSeconds': widget.selectedExercise.holdSeconds,
      'prescribed': widget.selectedExercise.prescription != null,
      'cameraView': widget.selectedExercise.cameraView.name,
      'countdownS': _settings.countdownSeconds,
      'voiceCues': _settings.voiceCues,
      'repSound': _settings.repSound,
      'repVibration': _settings.repVibration,
      'showSkeleton': _settings.showSkeleton,
      'minFrameIntervalMs': _minFrameIntervalMs,
    });
    unawaited(
      Vibration.hasVibrator()
          .then((v) => _hasVibrator = v)
          .catchError((Object e, StackTrace st) {
            _log.warn('PoseHaptics', 'Vibrator check failed', null, e, st);
            return false;
          }),
    );
    unawaited(_initAudio());
    unawaited(_initVoice());
    _initPoseDetector();
    unawaited(_initCamera());
  }

  void _initPoseDetector() {
    // "base" is the lightweight model: same 33 landmarks as "accurate" at a
    // fraction of the cost.
    final options = PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    );
    _poseDetector = PoseDetector(options: options);
    _log.info('PosePipeline', 'Pose detector created', {
      'mode': 'stream',
      'model': 'base',
    });
  }

  /// True when the camera init that started with [generation] has been
  /// overtaken by a dispose (app paused, camera switch, screen closed).
  bool _isSuperseded(int generation) =>
      !mounted || generation != _cameraGeneration;

  Future<void> _initCamera() async {
    if (_initializingCamera || _isSessionComplete) return;
    _initializingCamera = true;
    _reinitCameraWhenDone = false;
    if (mounted) setState(() => _cameraError = null);

    final generation = ++_cameraGeneration;
    final stopwatch = Stopwatch()..start();
    CameraController? controller;

    try {
      _availableCameras = await availableCameras();
      if (_isSuperseded(generation)) {
        _log.info('PoseCamera', 'Camera init superseded', {
          'stage': 'list',
          'gen': generation,
        });
        return;
      }
      if (_availableCameras.isEmpty) {
        throw CameraException('NoCamera', 'No camera found on this device.');
      }

      final camera = _availableCameras.firstWhere(
        (c) => c.lensDirection == _lensDirection,
        orElse: () => _availableCameras.first,
      );
      _lensDirection = camera.lensDirection;
      // Front camera previews are mirrored; Settings can flip that default.
      _mirrorSkeleton =
          (_lensDirection == CameraLensDirection.front) !=
          _settings.flipSkeleton;

      controller = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      _cameraController = controller;

      await controller.initialize();
      if (_isSuperseded(generation)) {
        // Paused / switched / closed while initialising. Whoever bumped the
        // generation already cleared _cameraController; make sure this
        // controller is released too (dispose is idempotent).
        _log.info('PoseCamera', 'Camera init superseded', {
          'stage': 'initialize',
          'gen': generation,
        });
        await _releaseController(controller);
        return;
      }

      _firstFrameLogged = false;
      await controller.startImageStream(
        (image) => _onCameraFrame(image, camera, generation),
      );
      if (_isSuperseded(generation)) {
        await _releaseController(controller);
        return;
      }

      final preview = controller.value.previewSize;
      _resolutionLabel = preview == null
          ? 'unknown'
          : '${preview.width.round()}x${preview.height.round()}';
      _log.info('PoseCamera', 'Camera started', {
        'lens': camera.lensDirection.name,
        'sensorOrientation': camera.sensorOrientation,
        'preset': 'low',
        'requestedFormat': 'nv21',
        'preview': _resolutionLabel,
        'cameras': _availableCameras.length,
        'gen': generation,
        'ms': stopwatch.elapsedMilliseconds,
      });

      setState(() {});
      _startCountdown();
    } on CameraException catch (e, st) {
      if (_isSuperseded(generation)) {
        // Expected: the controller was disposed under initialize().
        _log.info('PoseCamera', 'Camera init superseded', {
          'stage': 'error',
          'code': e.code,
          'gen': generation,
        });
        if (controller != null) await _releaseController(controller);
        return;
      }
      _log.error(
        'PoseCamera',
        'Camera init failed',
        {
          'code': e.code,
          'lens': _lensDirection.name,
          'ms': stopwatch.elapsedMilliseconds,
        },
        e,
        st,
      );
      await _disposeCamera();
      if (mounted) {
        setState(() {
          _cameraError = switch (e.code) {
            'CameraAccessDenied' ||
            'CameraAccessDeniedWithoutPrompt' ||
            'CameraAccessRestricted' =>
              'Camera permission is required to track your exercise. '
                  'Please allow camera access in your phone settings.',
            'NoCamera' => 'No camera was found on this device.',
            _ => 'Could not start the camera (${e.code}).',
          };
        });
      }
    } catch (e, st) {
      if (_isSuperseded(generation)) {
        _log.info('PoseCamera', 'Camera init superseded', {
          'stage': 'error',
          'gen': generation,
        });
        if (controller != null) await _releaseController(controller);
        return;
      }
      _log.error(
        'PoseCamera',
        'Camera init failed',
        {'code': 'unexpected', 'lens': _lensDirection.name},
        e,
        st,
      );
      await _disposeCamera();
      if (mounted) {
        setState(() => _cameraError = 'Could not start the camera.');
      }
    } finally {
      _initializingCamera = false;
      // The app came back to the foreground while this (now superseded)
      // init was still running: start a fresh one.
      if (_reinitCameraWhenDone) {
        _reinitCameraWhenDone = false;
        if (mounted &&
            !_appInBackground &&
            !_isSessionComplete &&
            _cameraController == null) {
          _log.info('PoseCamera', 'Restarting camera after superseded init');
          unawaited(_initCamera());
        }
      }
    }
  }

  /// Stops the stream and releases the current camera. Safe to call more
  /// than once and concurrently: the first caller takes the controller.
  Future<void> _disposeCamera() async {
    // Invalidate frames / in-flight results from this camera right away.
    _cameraGeneration++;
    final controller = _cameraController;
    _cameraController = null;
    if (controller == null) return;
    await _releaseController(controller);
  }

  Future<void> _releaseController(CameraController controller) async {
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (e, st) {
      _log.warn('PoseCamera', 'Stopping the image stream failed', null, e, st);
    }
    try {
      await controller.dispose();
    } catch (e, st) {
      _log.warn('PoseCamera', 'Camera dispose failed', null, e, st);
    }
  }

  void _resetTracking() {
    _checker.reset();
    _xFirst.clear();
    _xLast.clear();
    _xIssue.clear();
    _cancelCycle();
  }

  Future<void> _switchCamera() async {
    if (_availableCameras.length < 2 ||
        _initializingCamera ||
        _switchingCamera ||
        _isSessionComplete) {
      return;
    }
    _switchingCamera = true;
    try {
      final from = _lensDirection;
      _lensDirection = _lensDirection == CameraLensDirection.front
          ? CameraLensDirection.back
          : CameraLensDirection.front;
      _cameraSwitches++;
      _log.info('PoseCamera', 'Camera switch requested', {
        'from': from.name,
        'to': _lensDirection.name,
        'switches': _cameraSwitches,
      });

      await _disposeCamera();

      _resetTracking();
      if (mounted) setState(() => _detectedPoses = []);
      await _initCamera();
    } finally {
      _switchingCamera = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log.info('PoseCamera', 'App lifecycle changed', {
      'state': state.name,
      'cameraActive': _cameraController != null,
      'initializing': _initializingCamera,
      'sessionComplete': _isSessionComplete,
    });
    if (_isSessionComplete) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (!_appInBackground) _lifecyclePauses++;
      _appInBackground = true;
      // A resume that arrives later must start a NEW init, not rely on one
      // that this pause is about to supersede.
      _reinitCameraWhenDone = false;
      _resetTracking();
      unawaited(
        _disposeCamera().then((_) {
          if (mounted) setState(() => _detectedPoses = []);
        }),
      );
    } else if (state == AppLifecycleState.resumed) {
      _appInBackground = false;
      if (_cameraController != null) return;
      if (_initializingCamera) {
        // The running init was superseded by the pause; it restarts the
        // camera when it unwinds (see _initCamera's finally block).
        _reinitCameraWhenDone = true;
      } else {
        unawaited(_initCamera());
      }
    }
  }

  int _lastFrameMs = -_minFrameIntervalMs;

  /// Camera stream callback. Decides cheaply whether to analyse this frame.
  /// Must never throw: an exception here would surface in the camera
  /// plugin's stream.
  void _onCameraFrame(CameraImage image, CameraDescription camera, int gen) {
    _stats.onReceived();
    final nowMs = _frameClock.elapsedMilliseconds;
    if (_stats.isWindowDue(nowMs)) _logPipelineWindow(nowMs);

    if (!mounted ||
        _isSessionComplete ||
        _detectorClosing ||
        gen != _cameraGeneration) {
      _stats.onSkippedInactive();
      return;
    }

    // Back-pressure: skip frames while ML Kit is still busy.
    if (_isProcessing) {
      _stats.onSkippedBusy();
      final busyMs = nowMs - _processingStartedMs;
      if (busyMs > 2000 && !_stallReported) {
        _stallReported = true;
        _log.warn('PosePipeline', 'ML Kit call is taking unusually long', {
          'busyMs': busyMs,
        });
      }
      return;
    }

    if (nowMs - _lastFrameMs < _minFrameIntervalMs) {
      _stats.onSkippedThrottle();
      return;
    }
    _lastFrameMs = nowMs;

    if (!_firstFrameLogged) {
      _firstFrameLogged = true;
      _log.info('PoseCamera', 'First frame received', {
        'width': image.width,
        'height': image.height,
        'formatRaw': image.format.raw,
        'formatGroup': image.format.group.name,
        'planes': image.planes.length,
        'bytesPerRow': image.planes.isEmpty ? 0 : image.planes[0].bytesPerRow,
        'gen': gen,
      });
    }

    unawaited(_processFrame(image, camera, gen));
  }

  void _logPipelineWindow(int nowMs) {
    final window = _stats.takeWindow(nowMs);
    if (window == null) return;
    window['lens'] = _lensDirection.name;
    window['reps'] = _repCounter;
    window['rejected'] = _rejectedReps;
    window['countingDown'] = _countingDown;
    _log.info('PosePipeline', 'Pipeline window', window);
  }

  Future<void> _processFrame(
    CameraImage image,
    CameraDescription camera,
    int gen,
  ) async {
    _isProcessing = true;
    _stallReported = false;
    _processingStartedMs = _frameClock.elapsedMilliseconds;
    final inFlight = Completer<void>();
    _inFlightFrame = inFlight;

    try {
      final inputImage = _inputImageFromCameraImage(image, camera);
      if (inputImage == null) {
        _stats.onConversionFailed();
        return;
      }

      final mlStartUs = _frameClock.elapsedMicroseconds;
      final List<Pose> poses = await _poseDetector.processImage(inputImage);
      final latencyUs = _frameClock.elapsedMicroseconds - mlStartUs;
      _stats.onProcessed(latencyUs: latencyUs, poseFound: poses.isNotEmpty);

      // The world may have changed while ML Kit was busy: screen closed,
      // session finished, or the camera was switched / paused (stale frame).
      if (!mounted || _isSessionComplete || gen != _cameraGeneration) {
        _stats.onResultDiscarded();
        return;
      }

      // Judge the form first so the overlay and the rep logic agree.
      final FormResult form;
      if (_countingDown) {
        form = FormResult.ok;
      } else if (poses.isEmpty) {
        form = _filterForm(_checker.evaluateNoPose());
      } else {
        final lm = poses.first.landmarks;
        form = _filterForm(_mergeExtraFaults(_checker.evaluate(lm), lm));
      }
      _stats.onForm(form.status);
      _logFormChange(form);

      if (form.isWrong && !_wasWrong) _triggerWrongFeedback();
      _wasWrong = form.isWrong;

      // Run all logic BEFORE the single setState below.
      if (_countingDown) {
        // Getting into position: nothing is counted yet.
      } else if (poses.isNotEmpty) {
        _analyzeMotion(poses.first.landmarks, form);
      } else {
        _cancelCycle();
        if (widget.selectedExercise.isHold) _updateHold(false);
      }

      final rotation =
          inputImage.metadata?.rotation ?? InputImageRotation.rotation0deg;
      final swap =
          rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg;
      final w = image.width.toDouble();
      final h = image.height.toDouble();

      if (_log.isVerbose) {
        _log.verbose('PosePipeline', 'Frame processed', {
          'mlMs': latencyUs ~/ 1000,
          'poses': poses.length,
          'form': form.status.name,
          'angle': _currentAngle.round(),
          'stage': _stage,
        });
      }

      if (!mounted) return;
      setState(() {
        _detectedPoses = poses;
        _imageSize = swap ? Size(h, w) : Size(w, h);
        _rotation = rotation;
        _form = form;
      });
      if (_settings.voiceCues) {
        final tip = _effectiveForm.primary?.message;
        if (tip != null && tip.isNotEmpty) _speak(tip);
      }
    } catch (e, st) {
      // One bad frame must never stop the stream: count it, log the first
      // few in full, and carry on with the next frame.
      _stats.onError();
      if (_loggedFrameErrors < _maxLoggedFrameErrors) {
        _loggedFrameErrors++;
        _log.error(
          'PosePipeline',
          'Frame processing failed',
          {
            'errorsSoFar': _stats.totalErrors,
            'logged': _loggedFrameErrors,
            'width': image.width,
            'height': image.height,
          },
          e,
          st,
        );
      }
    } finally {
      _isProcessing = false;
      inFlight.complete();
      if (identical(_inFlightFrame, inFlight)) _inFlightFrame = null;
    }
  }

  /// Logs the screen's FINAL form verdict when it changes (status or the set
  /// of issue codes). Cheap per frame: one int mask comparison.
  void _logFormChange(FormResult form) {
    var mask = 0;
    for (final issue in form.issues) {
      mask |= 1 << issue.code.index;
    }
    if (form.status == _loggedFormStatus && mask == _loggedFormMask) return;
    _loggedFormStatus = form.status;
    _loggedFormMask = mask;
    _log.info('PoseForm', 'Form status changed', {
      'status': form.status.name,
      'issues': [for (final i in form.issues) i.code.name],
      'reps': _repCounter,
    });
  }

  /// Arm exercises: legs are usually cropped or half out of frame, and their
  /// guessed landmarks jitter, which kept "legs moving" red permanently.
  FormResult _filterForm(FormResult f) {
    if (!f.isWrong) return f;
    final armExercise = switch (widget.selectedExercise.type) {
      ExerciseType.forwardRaise ||
      ExerciseType.sideRaise ||
      ExerciseType.forwardPush ||
      ExerciseType.overheadRaise ||
      ExerciseType.bicepCurl => true,
      _ => false,
    };
    if (!armExercise) return f;
    final kept = f.issues
        .where((i) => i.code != FormIssueCode.legsMoving)
        .toList();
    return kept.isEmpty
        ? FormResult.ok
        : FormResult(FormStatus.wrongForm, kept);
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  bool _vis(PoseLandmark? p) =>
      p != null && p.likelihood >= _thresholds.minLikelihood;

  /// Angle at landmark [b] between [a] and [c], or null if any is missing.
  double? _jointAngle(
    Map<PoseLandmarkType, PoseLandmark> lm,
    PoseLandmarkType a,
    PoseLandmarkType b,
    PoseLandmarkType c,
  ) {
    final p1 = lm[a];
    final p2 = lm[b];
    final p3 = lm[c];
    if (p1 == null || p2 == null || p3 == null) return null;
    return _calculateAngle(p1, p2, p3);
  }

  /// Like [_jointAngle] but also requires every landmark to be confidently
  /// visible (used by the fault checks so guessed points don't cause red).
  double? _visAngle(
    Map<PoseLandmarkType, PoseLandmark> lm,
    PoseLandmarkType a,
    PoseLandmarkType b,
    PoseLandmarkType c,
  ) {
    final p1 = lm[a];
    final p2 = lm[b];
    final p3 = lm[c];
    if (!_vis(p1) || !_vis(p2) || !_vis(p3)) return null;
    return _calculateAngle(p1!, p2!, p3!);
  }

  double _average(List<double> values) =>
      values.reduce((a, b) => a + b) / values.length;

  double _distance(PoseLandmark a, PoseLandmark b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
  }

  /// Shoulder-mid to hip-mid distance in pixels, or null if not visible.
  double? _torsoPx(Map<PoseLandmarkType, PoseLandmark> lm) {
    final s = [
      lm[PoseLandmarkType.leftShoulder],
      lm[PoseLandmarkType.rightShoulder],
    ].where(_vis).cast<PoseLandmark>().toList();
    final h = [
      lm[PoseLandmarkType.leftHip],
      lm[PoseLandmarkType.rightHip],
    ].where(_vis).cast<PoseLandmark>().toList();
    if (s.isEmpty || h.isEmpty) return null;
    final sx = s.map((p) => p.x).reduce((a, b) => a + b) / s.length;
    final sy = s.map((p) => p.y).reduce((a, b) => a + b) / s.length;
    final hx = h.map((p) => p.x).reduce((a, b) => a + b) / h.length;
    final hy = h.map((p) => p.y).reduce((a, b) => a + b) / h.length;
    return sqrt((sx - hx) * (sx - hx) + (sy - hy) * (sy - hy));
  }

  /// The angle the "down" position is judged against (see TUNING).
  double get _restAngle {
    switch (widget.selectedExercise.type) {
      case ExerciseType.bicepCurl:
        return _curlRestAngle;
      case ExerciseType.forwardRaise:
      case ExerciseType.sideRaise:
        return _raiseRestAngle;
      default:
        return widget.selectedExercise.restAngle;
    }
  }

  // ---------------------------------------------------------------------
  // Extra per-exercise faults (live in this file; reuse existing issue codes)
  //
  // _rawFaults  : instantaneous, used for rep validation (catches flailing)
  // _mergeExtraFaults : debounced, used for the red skeleton / banner
  // ---------------------------------------------------------------------

  List<FormIssue> _rawFaults(Map<PoseLandmarkType, PoseLandmark> lm) {
    final out = <FormIssue>[];
    final exercise = widget.selectedExercise;

    switch (exercise.type) {
      case ExerciseType.bicepCurl:
        {
          // Upper arm must stay beside the trunk; only the elbow bends.
          final swung = <PoseLandmarkType>{};
          const sides = [
            (
              PoseLandmarkType.leftHip,
              PoseLandmarkType.leftShoulder,
              PoseLandmarkType.leftElbow,
            ),
            (
              PoseLandmarkType.rightHip,
              PoseLandmarkType.rightShoulder,
              PoseLandmarkType.rightElbow,
            ),
          ];
          for (final s in sides) {
            final a = _visAngle(lm, s.$1, s.$2, s.$3);
            if (a != null && a > _thresholds.maxUpperArmSwingDeg) {
              swung.add(s.$3);
            }
          }
          if (swung.isNotEmpty) {
            out.add(
              FormIssue(
                code: FormIssueCode.elbowDrift,
                message: 'Keep your elbows by your sides. Only bend the elbow.',
                landmarks: swung,
                anchor: swung.first,
              ),
            );
          }
        }
        break;

      case ExerciseType.forwardRaise:
      case ExerciseType.sideRaise:
        {
          // Raise to shoulder height, not above it.
          final high = <PoseLandmarkType>{};
          const sides = [
            (
              PoseLandmarkType.leftHip,
              PoseLandmarkType.leftShoulder,
              PoseLandmarkType.leftWrist,
            ),
            (
              PoseLandmarkType.rightHip,
              PoseLandmarkType.rightShoulder,
              PoseLandmarkType.rightWrist,
            ),
          ];
          for (final s in sides) {
            final a = _visAngle(lm, s.$1, s.$2, s.$3);
            if (a != null && a > _raiseMaxDeg) high.add(s.$3);
          }
          if (high.isNotEmpty) {
            out.add(
              FormIssue(
                code: FormIssueCode.shortRange,
                message: 'Too high. Stop at shoulder height.',
                landmarks: high,
                anchor: high.first,
              ),
            );
          }
        }
        break;

      case ExerciseType.forwardPush:
        {
          // Extended hands should be at chest height, not drifting up/down.
          final torso = _torsoPx(lm);
          if (torso != null) {
            final off = <PoseLandmarkType>{};
            const sides = [
              (
                PoseLandmarkType.leftShoulder,
                PoseLandmarkType.leftElbow,
                PoseLandmarkType.leftWrist,
              ),
              (
                PoseLandmarkType.rightShoulder,
                PoseLandmarkType.rightElbow,
                PoseLandmarkType.rightWrist,
              ),
            ];
            for (final s in sides) {
              final elbowAngle = _visAngle(lm, s.$1, s.$2, s.$3);
              final sh = lm[s.$1];
              final wr = lm[s.$3];
              if (elbowAngle == null || !_vis(sh) || !_vis(wr)) continue;
              if (elbowAngle > 130 && (wr!.y - sh!.y).abs() > 0.6 * torso) {
                off.add(s.$3);
              }
            }
            if (off.isNotEmpty) {
              out.add(
                FormIssue(
                  code: FormIssueCode.shortRange,
                  message: 'Push straight ahead at chest height.',
                  landmarks: off,
                  anchor: off.first,
                ),
              );
            }
          }
        }
        break;

      case ExerciseType.sitToStand:
        {
          // Some forward lean is normal; too much means collapsing forward.
          final ls = lm[PoseLandmarkType.leftShoulder];
          final rs = lm[PoseLandmarkType.rightShoulder];
          final lh = lm[PoseLandmarkType.leftHip];
          final rh = lm[PoseLandmarkType.rightHip];
          final shoulders = [ls, rs].where(_vis).cast<PoseLandmark>().toList();
          final hips = [lh, rh].where(_vis).cast<PoseLandmark>().toList();
          if (shoulders.isNotEmpty && hips.isNotEmpty) {
            final sx =
                shoulders.map((p) => p.x).reduce((a, b) => a + b) /
                shoulders.length;
            final sy =
                shoulders.map((p) => p.y).reduce((a, b) => a + b) /
                shoulders.length;
            final hx =
                hips.map((p) => p.x).reduce((a, b) => a + b) / hips.length;
            final hy =
                hips.map((p) => p.y).reduce((a, b) => a + b) / hips.length;
            final lean = atan2((sx - hx).abs(), hy - sy) * 180 / pi;
            if (lean > _sitToStandMaxLeanDeg) {
              out.add(
                FormIssue(
                  code: FormIssueCode.trunkLean,
                  message: "Don't lean too far forward. Keep your chest up.",
                  landmarks: {
                    PoseLandmarkType.leftShoulder,
                    PoseLandmarkType.rightShoulder,
                    PoseLandmarkType.leftHip,
                    PoseLandmarkType.rightHip,
                  },
                  anchor: _vis(ls)
                      ? PoseLandmarkType.leftShoulder
                      : PoseLandmarkType.rightShoulder,
                ),
              );
            }
          }
        }
        break;

      case ExerciseType.singleLegBalance:
        {
          final lAnkle = lm[PoseLandmarkType.leftAnkle];
          final rAnkle = lm[PoseLandmarkType.rightAnkle];
          if (_vis(lAnkle) && _vis(rAnkle)) {
            // Image y grows downward: the standing foot has the larger y.
            final leftStands = lAnkle!.y > rAnkle!.y;
            final hip = leftStands
                ? PoseLandmarkType.leftHip
                : PoseLandmarkType.rightHip;
            final knee = leftStands
                ? PoseLandmarkType.leftKnee
                : PoseLandmarkType.rightKnee;
            final ankle = leftStands
                ? PoseLandmarkType.leftAnkle
                : PoseLandmarkType.rightAnkle;
            final a = _visAngle(lm, hip, knee, ankle);
            if (a != null && a < 150) {
              out.add(
                FormIssue(
                  code: FormIssueCode.kneeBent,
                  message: 'Keep your standing leg straight.',
                  landmarks: {knee, ankle},
                  anchor: knee,
                ),
              );
            }
          }
        }
        break;

      case ExerciseType.wallSit:
        {
          final angles = <double?>[
            _visAngle(
              lm,
              PoseLandmarkType.leftHip,
              PoseLandmarkType.leftKnee,
              PoseLandmarkType.leftAnkle,
            ),
            _visAngle(
              lm,
              PoseLandmarkType.rightHip,
              PoseLandmarkType.rightKnee,
              PoseLandmarkType.rightAnkle,
            ),
          ].whereType<double>().toList();
          if (angles.isNotEmpty) {
            final knee = _average(angles);
            final diff = knee - exercise.targetAngle;
            if (diff.abs() > _wallSitFaultDeg) {
              out.add(
                FormIssue(
                  code: FormIssueCode.shortRange,
                  message: diff > 0
                      ? 'Slide lower until your knees are at 90°.'
                      : 'Too low. Rise until your knees are at 90°.',
                  landmarks: {
                    PoseLandmarkType.leftKnee,
                    PoseLandmarkType.rightKnee,
                  },
                  anchor: PoseLandmarkType.leftKnee,
                ),
              );
            }
          }
        }
        break;

      case ExerciseType.miniSquat:
      case ExerciseType.hipAbduction:
      case ExerciseType.hamstringCurl:
      case ExerciseType.marching:
      case ExerciseType.overheadRaise:
        out.addAll(
          ExerciseGeometry.extraFaults(
            exercise.type,
            lm,
            minLikelihood: _thresholds.minLikelihood,
          ),
        );
        break;

      default:
        break;
    }
    return out;
  }

  /// Debounces [_rawFaults] (confirm 150 ms, hold 700 ms) and merges the
  /// result into the checker's own result.
  FormResult _mergeExtraFaults(
    FormResult base,
    Map<PoseLandmarkType, PoseLandmark> lm,
  ) {
    if (base.isNotInFrame) return base;

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final i in _rawFaults(lm)) {
      final last = _xLast[i.code];
      if (last == null || now - last > 300) _xFirst[i.code] = now;
      _xLast[i.code] = now;
      _xIssue[i.code] = i;
    }

    final baseCodes = base.issues.map((i) => i.code).toSet();
    final extra = <FormIssue>[];
    for (final code in _xLast.keys.toList()) {
      final last = _xLast[code]!;
      if (now - last > 700) {
        _xLast.remove(code);
        _xFirst.remove(code);
        _xIssue.remove(code);
        continue;
      }
      if (last - _xFirst[code]! >= 150 && !baseCodes.contains(code)) {
        extra.add(_xIssue[code]!);
      }
    }
    if (extra.isEmpty) return base;

    final all = [...base.issues, ...extra]
      ..sort((a, b) => a.code.index.compareTo(b.code.index));
    return FormResult(FormStatus.wrongForm, all);
  }

  // ---------------------------------------------------------------------
  // Rep-based exercises
  // ---------------------------------------------------------------------

  void _analyzeMotion(
    Map<PoseLandmarkType, PoseLandmark> landmarks,
    FormResult form,
  ) {
    final exercise = widget.selectedExercise;

    // Patient isn't properly framed: nothing counts until they are.
    if (form.isNotInFrame) {
      _cancelCycle();
      if (exercise.isHold) _updateHold(false);
      return;
    }

    // Timed holds use their own logic.
    if (exercise.isHold) {
      _analyzeHold(landmarks, form);
      return;
    }

    final shoulder =
        landmarks[PoseLandmarkType.leftShoulder] ??
        landmarks[PoseLandmarkType.rightShoulder];
    final hip =
        landmarks[PoseLandmarkType.leftHip] ??
        landmarks[PoseLandmarkType.rightHip];
    final knee =
        landmarks[PoseLandmarkType.leftKnee] ??
        landmarks[PoseLandmarkType.rightKnee];
    final ankle =
        landmarks[PoseLandmarkType.leftAnkle] ??
        landmarks[PoseLandmarkType.rightAnkle];

    double calculatedAngle = 0.0;
    bool isValidRep = false;
    bool isRestPosition = false;

    switch (exercise.type) {
      case ExerciseType.kneeExtension:
        {
          // Which leg is working, and whether the other leg can really be
          // seen, is decided in ExerciseGeometry.kneeExtensionLegs (see the
          // comment there: a hidden far leg used to block every rep).
          final legs = ExerciseGeometry.kneeExtensionLegs(
            landmarks,
            minLikelihood: _thresholds.minLikelihood,
          );
          if (legs != null) {
            calculatedAngle = legs.working;
            final reachedTarget = legs.working >= exercise.targetAngle;
            final otherLegBent =
                legs.resting == null || legs.resting! < _otherLegBentMaxDeg;
            isValidRep = reachedTarget && otherLegBent;
            isRestPosition = legs.working < exercise.restAngle;
            _logOtherLegBlock(
              blocked: reachedTarget && !otherLegBent,
              working: legs.working,
              resting: legs.resting,
            );
          }
        }
        break;

      case ExerciseType.straightLegRaise:
        if (shoulder != null && hip != null && knee != null && ankle != null) {
          final kneeAngle = _calculateAngle(hip, knee, ankle);
          final hipAngle = _calculateAngle(shoulder, hip, knee);
          calculatedAngle = hipAngle;

          if (kneeAngle >= 150.0) {
            isValidRep = hipAngle <= exercise.targetAngle;
            isRestPosition = hipAngle >= exercise.restAngle;
          }
        }
        break;

      case ExerciseType.kneeFlexion:
      case ExerciseType.heelSlide:
        if (hip != null && knee != null && ankle != null) {
          calculatedAngle = _calculateAngle(hip, knee, ankle);
          isValidRep = calculatedAngle <= exercise.targetAngle;
          isRestPosition = calculatedAngle >= exercise.restAngle;
        }
        break;

      case ExerciseType.forwardRaise:
      case ExerciseType.sideRaise:
        {
          final raised = <double?>[
            _jointAngle(
              landmarks,
              PoseLandmarkType.leftHip,
              PoseLandmarkType.leftShoulder,
              PoseLandmarkType.leftWrist,
            ),
            _jointAngle(
              landmarks,
              PoseLandmarkType.rightHip,
              PoseLandmarkType.rightShoulder,
              PoseLandmarkType.rightWrist,
            ),
          ].whereType<double>().toList();
          if (raised.isNotEmpty) {
            calculatedAngle = raised.reduce(max);
            isValidRep = calculatedAngle >= exercise.targetAngle;
            isRestPosition = calculatedAngle <= _restAngle;
          }
        }
        break;

      case ExerciseType.forwardPush:
        {
          final extended = <double?>[
            _jointAngle(
              landmarks,
              PoseLandmarkType.leftShoulder,
              PoseLandmarkType.leftElbow,
              PoseLandmarkType.leftWrist,
            ),
            _jointAngle(
              landmarks,
              PoseLandmarkType.rightShoulder,
              PoseLandmarkType.rightElbow,
              PoseLandmarkType.rightWrist,
            ),
          ].whereType<double>().toList();
          if (extended.isNotEmpty) {
            calculatedAngle = extended.reduce(max);
            isValidRep = calculatedAngle >= exercise.targetAngle;
            isRestPosition = calculatedAngle <= exercise.restAngle;
          }
        }
        break;

      case ExerciseType.bicepCurl:
        {
          final left = _jointAngle(
            landmarks,
            PoseLandmarkType.leftShoulder,
            PoseLandmarkType.leftElbow,
            PoseLandmarkType.leftWrist,
          );
          final right = _jointAngle(
            landmarks,
            PoseLandmarkType.rightShoulder,
            PoseLandmarkType.rightElbow,
            PoseLandmarkType.rightWrist,
          );

          double? best;
          PoseLandmark? bestElbow;
          PoseLandmark? bestWrist;
          for (final entry in [
            (left, PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist),
            (right, PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist),
          ]) {
            final angle = entry.$1;
            if (angle == null) continue;
            if (best == null || angle < best) {
              best = angle;
              bestElbow = landmarks[entry.$2];
              bestWrist = landmarks[entry.$3];
            }
          }

          if (best != null && bestElbow != null && bestWrist != null) {
            calculatedAngle = best;

            final shoulderY =
                landmarks[PoseLandmarkType.leftShoulder]?.y ??
                landmarks[PoseLandmarkType.rightShoulder]?.y;
            // Landmark coordinates are PIXELS, so tolerances scale with body.
            final torsoPx = (shoulder != null && hip != null)
                ? _distance(shoulder, hip)
                : 100.0;
            final elbowPinned =
                shoulderY == null || bestElbow.y > shoulderY - 0.15 * torsoPx;
            final wristNearShoulder =
                shoulderY != null && bestWrist.y <= shoulderY + 0.35 * torsoPx;

            isValidRep =
                calculatedAngle <= exercise.targetAngle &&
                elbowPinned &&
                wristNearShoulder;
            isRestPosition = calculatedAngle >= _restAngle;
          }
        }
        break;

      case ExerciseType.sitToStand:
        {
          final angles = <double?>[
            _jointAngle(
              landmarks,
              PoseLandmarkType.leftHip,
              PoseLandmarkType.leftKnee,
              PoseLandmarkType.leftAnkle,
            ),
            _jointAngle(
              landmarks,
              PoseLandmarkType.rightHip,
              PoseLandmarkType.rightKnee,
              PoseLandmarkType.rightAnkle,
            ),
          ].whereType<double>().toList();

          if (angles.isNotEmpty) {
            calculatedAngle = _average(angles);
            isValidRep = calculatedAngle >= exercise.targetAngle;
            isRestPosition = calculatedAngle <= exercise.restAngle;
          }
        }
        break;

      case ExerciseType.gluteBridge:
        {
          final angles = <double?>[
            _jointAngle(
              landmarks,
              PoseLandmarkType.leftShoulder,
              PoseLandmarkType.leftHip,
              PoseLandmarkType.leftKnee,
            ),
            _jointAngle(
              landmarks,
              PoseLandmarkType.rightShoulder,
              PoseLandmarkType.rightHip,
              PoseLandmarkType.rightKnee,
            ),
          ].whereType<double>().toList();

          if (angles.isNotEmpty) {
            calculatedAngle = _average(angles);
            isValidRep = calculatedAngle >= exercise.targetAngle;
            isRestPosition = calculatedAngle <= exercise.restAngle;
          }
        }
        break;

      case ExerciseType.singleLegBalance:
      case ExerciseType.wallSit:
        break; // handled by _analyzeHold above

      // Second batch: geometry lives in exercise_geometry.dart (unit-tested).
      case ExerciseType.miniSquat:
      case ExerciseType.hipAbduction:
      case ExerciseType.hamstringCurl:
      case ExerciseType.marching:
      case ExerciseType.overheadRaise:
        final reading = ExerciseGeometry.readRep(exercise, landmarks);
        if (reading != null) {
          calculatedAngle = reading.angle;
          isValidRep = reading.atTarget;
        }
    }

    // Forgiving rest zone: count the rep once the joint is back through the
    // first part of the range, rather than at the exact rest angle.
    if (calculatedAngle != 0.0) {
      final restA = _restAngle;
      final span = exercise.targetAngle - restA;
      final returnAngle = restA + span * _restZone;
      isRestPosition = span >= 0
          ? calculatedAngle <= returnAngle
          : calculatedAngle >= returnAngle;
    }

    // 0.0 means "couldn't measure" (a needed landmark was missing).
    if (calculatedAngle == 0.0) return;

    // No setState here: _processFrame does a single setState per frame.
    _currentAngle = calculatedAngle;
    _advanceRepCycle(
      angle: calculatedAngle,
      isValidRep: isValidRep,
      isRest: isRestPosition,
      form: form,
      instantFaults: _rawFaults(landmarks),
    );

    _checkCompletion();
  }

  // ---------------------------------------------------------------------
  // Strict rep accounting
  //
  // A rep counts only if the patient (1) leaves rest, (2) reaches the target
  // once, (3) comes back toward rest, AND (4) took long enough, AND (5) no
  // fault was raised along the way (debounced OR instantaneous for more than
  // a couple of frames). Anything else is rejected and scored 0.0.
  //
  // The rep is judged as soon as the joint is _commitProgress of the way
  // back, so the sound/vibration don't wait for a full return to rest.
  // ---------------------------------------------------------------------

  void _advanceRepCycle({
    required double angle,
    required bool isValidRep,
    required bool isRest,
    required FormResult form,
    required List<FormIssue> instantFaults,
  }) {
    // Rep already judged: wait for a full return before the next one starts.
    if (_awaitRest) {
      if (isRest) {
        _awaitRest = false;
        _cancelCycle();
        _learnBaseline(angle);
      }
      return;
    }

    if (isRest) {
      if (_cycleActive) _finishCycle();
      _cancelCycle();
      _learnBaseline(angle);
      return;
    }

    if (!_cycleActive) {
      _cycleActive = true;
      _cycleStart = DateTime.now();
      _cycleViolation = null;
      _cycleFaultIssue = null;
      _cycleFaultFrames = 0;
      _targetHits = 0;
      _atTarget = false;
      _maxProgress = 0.0;
    }

    if (form.isWrong) _cycleViolation ??= form.primary;
    if (instantFaults.isNotEmpty) {
      _cycleFaultFrames++;
      _cycleFaultIssue ??= instantFaults.first;
    }

    final p = _progress(angle);
    _maxProgress = max(_maxProgress, p);

    // Count how many separate times the target was reached (hysteresis so
    // jitter around the target isn't counted as a new hit).
    if (isValidRep) {
      if (!_atTarget) {
        _atTarget = true;
        _targetHits++;
      }
      if (_stage == "down") _stage = "up";
    } else if (p < _reArmProgress) {
      _atTarget = false;
    }

    // Judge the rep on the way back, without waiting for full rest.
    if (_stage == "up" && p <= _commitProgress) {
      _finishCycle();
      _awaitRest = true;
    }
  }

  /// Knee Extension: logs when the target angle is reached but the rep is
  /// held back because the other leg is also straight, and when that
  /// clears. Logged on change only, so it can't flood the log.
  bool _otherLegBlocked = false;
  void _logOtherLegBlock({
    required bool blocked,
    required double working,
    required double? resting,
  }) {
    if (blocked == _otherLegBlocked) return;
    _otherLegBlocked = blocked;
    _log.info(
      'RepCycle',
      blocked ? 'Rep blocked: other leg straight' : 'Other-leg block cleared',
      {
        'working': working.round(),
        'resting': resting?.round(),
        'limit': _otherLegBentMaxDeg,
      },
    );
  }

  void _learnBaseline(double angle) {
    _baseline = _baseline == null ? angle : _baseline! * 0.8 + angle * 0.2;
  }

  void _finishCycle() {
    final exercise = widget.selectedExercise;
    final ms = DateTime.now()
        .difference(_cycleStart ?? DateTime.now())
        .inMilliseconds;

    if (_stage == "up") {
      final bad =
          _cycleViolation ??
          (_cycleFaultFrames >= _faultFrameLimit ? _cycleFaultIssue : null);

      if (bad != null) {
        _rejectRep(
          bad.withMessage('Rep not counted. ${bad.message}'),
          rule: 'formFault',
          ms: ms,
        );
      } else if (_targetHits > 1) {
        _rejectRep(
          const FormIssue(
            code: FormIssueCode.tooFast,
            message:
                'Rep not counted. Use one smooth movement, not back and forth.',
            landmarks: <PoseLandmarkType>{},
          ),
          rule: 'backAndForth',
          ms: ms,
        );
      } else if (ms < _minRepMs) {
        _rejectRep(
          const FormIssue(
            code: FormIssueCode.tooFast,
            message: 'Rep not counted. Too fast. Slow down and control it.',
            landmarks: <PoseLandmarkType>{},
          ),
          rule: 'tooQuick',
          ms: ms,
        );
      } else {
        _repCounter++;
        _repScores.add(1.0);
        _log.info('RepCycle', 'Rep counted', {
          'rep': _repCounter,
          'target': exercise.targetReps,
          'ms': ms,
          'targetHits': _targetHits,
          'faultFrames': _cycleFaultFrames,
          'maxProgress': _round2(_maxProgress),
          'angle': _currentAngle.round(),
          'baseline': _baseline?.round(),
        });
        _triggerFeedback();
      }
    } else if (_maxProgress >= _thresholds.attemptProgress && ms >= 500) {
      // They started the movement but never got to the target angle.
      final fb = _rangeFeedback(exercise.type);
      _rejectRep(
        FormIssue(
          code: FormIssueCode.shortRange,
          message: 'Rep not counted. ${fb.message}',
          landmarks: fb.landmarks,
        ),
        rule: 'partialRange',
        ms: ms,
      );
    }
  }

  /// [rule] says WHICH anti-flail rule fired (formFault, backAndForth,
  /// tooQuick, partialRange); the issue code says what was wrong.
  void _rejectRep(FormIssue issue, {required String rule, required int ms}) {
    _rejectedReps++;
    _repScores.add(0.0);
    _rejectRules[rule] = (_rejectRules[rule] ?? 0) + 1;
    _rejectCodes[issue.code.name] = (_rejectCodes[issue.code.name] ?? 0) + 1;
    _log.info('RepCycle', 'Rep rejected', {
      'rule': rule,
      'code': issue.code.name,
      'ms': ms,
      'minRepMs': _minRepMs,
      'targetHits': _targetHits,
      'faultFrames': _cycleFaultFrames,
      'faultFrameLimit': _faultFrameLimit,
      'maxProgress': _round2(_maxProgress),
      'rejected': _rejectedReps,
      'reps': _repCounter,
    });
    _flashIssue(issue);
    _triggerWrongFeedback();
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  void _cancelCycle() {
    _cycleActive = false;
    _awaitRest = false;
    _cycleStart = null;
    _cycleViolation = null;
    _cycleFaultIssue = null;
    _cycleFaultFrames = 0;
    _targetHits = 0;
    _atTarget = false;
    _maxProgress = 0.0;
    _stage = "down";
  }

  /// 0 = at the patient's resting angle, 1 = at the target angle.
  double _progress(double angle) {
    final e = widget.selectedExercise;
    final base = _baseline ?? _restAngle;
    final span = e.targetAngle - base;
    if (span.abs() < 10) return 0.0; // degenerate range, don't guess
    return (angle - base) / span;
  }

  ({String message, Set<PoseLandmarkType> landmarks}) _rangeFeedback(
    ExerciseType type,
  ) {
    const ankles = {PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle};
    const wrists = {PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist};
    const hips = {PoseLandmarkType.leftHip, PoseLandmarkType.rightHip};

    switch (type) {
      case ExerciseType.kneeExtension:
        return (
          message: 'Leg is too low. Raise it higher to straighten your knee.',
          landmarks: ankles,
        );
      case ExerciseType.straightLegRaise:
        return (message: 'Leg is too low. Lift it higher.', landmarks: ankles);
      case ExerciseType.kneeFlexion:
      case ExerciseType.heelSlide:
        return (message: 'Bend your knee further.', landmarks: ankles);
      case ExerciseType.forwardRaise:
      case ExerciseType.sideRaise:
        return (
          message: 'Arm is too low. Raise it to shoulder height.',
          landmarks: wrists,
        );
      case ExerciseType.forwardPush:
        return (message: 'Push all the way out.', landmarks: wrists);
      case ExerciseType.bicepCurl:
        return (message: 'Curl all the way up.', landmarks: wrists);
      case ExerciseType.sitToStand:
        return (message: 'Stand up fully.', landmarks: hips);
      case ExerciseType.gluteBridge:
        return (message: 'Lift your hips higher.', landmarks: hips);
      case ExerciseType.singleLegBalance:
      case ExerciseType.wallSit:
        return (message: 'Hold the full position.', landmarks: ankles);
      case ExerciseType.miniSquat:
      case ExerciseType.hipAbduction:
      case ExerciseType.hamstringCurl:
      case ExerciseType.marching:
      case ExerciseType.overheadRaise:
        return ExerciseGeometry.rangeFeedback(type);
    }
  }

  // ---------------------------------------------------------------------
  // Timed holds
  // ---------------------------------------------------------------------

  void _analyzeHold(
    Map<PoseLandmarkType, PoseLandmark> landmarks,
    FormResult form,
  ) {
    final exercise = widget.selectedExercise;
    bool inPosition = false;

    switch (exercise.type) {
      case ExerciseType.singleLegBalance:
        {
          final lHip = landmarks[PoseLandmarkType.leftHip];
          final lKnee = landmarks[PoseLandmarkType.leftKnee];
          final lAnkle = landmarks[PoseLandmarkType.leftAnkle];
          final rHip = landmarks[PoseLandmarkType.rightHip];
          final rKnee = landmarks[PoseLandmarkType.rightKnee];
          final rAnkle = landmarks[PoseLandmarkType.rightAnkle];

          if (lHip != null &&
              lKnee != null &&
              lAnkle != null &&
              rHip != null &&
              rKnee != null &&
              rAnkle != null) {
            final leftIsStanding = lAnkle.y > rAnkle.y;
            final standHip = leftIsStanding ? lHip : rHip;
            final standKnee = leftIsStanding ? lKnee : rKnee;
            final standAnkle = leftIsStanding ? lAnkle : rAnkle;

            final standingKneeAngle = _calculateAngle(
              standHip,
              standKnee,
              standAnkle,
            );
            final legLength = _distance(standHip, standAnkle);
            final footLift = (lAnkle.y - rAnkle.y).abs();

            _currentAngle = standingKneeAngle;
            inPosition =
                standingKneeAngle >= 150.0 && footLift >= 0.15 * legLength;
          }
        }
        break;

      case ExerciseType.wallSit:
        {
          final angles = <double?>[
            _jointAngle(
              landmarks,
              PoseLandmarkType.leftHip,
              PoseLandmarkType.leftKnee,
              PoseLandmarkType.leftAnkle,
            ),
            _jointAngle(
              landmarks,
              PoseLandmarkType.rightHip,
              PoseLandmarkType.rightKnee,
              PoseLandmarkType.rightAnkle,
            ),
          ].whereType<double>().toList();

          if (angles.isNotEmpty) {
            final kneeAngle = _average(angles);
            _currentAngle = kneeAngle;
            inPosition =
                (kneeAngle - exercise.targetAngle).abs() <= _wallSitTolerance;
          }
        }
        break;

      default:
        break;
    }

    // The clock only runs while the position is right AND form is clean.
    _updateHold(inPosition && !form.isWrong);
  }

  /// Call once per processed frame. State is plain fields; the frame's single
  /// setState in _processFrame repaints them.
  void _updateHold(bool inPosition) {
    final now = DateTime.now();
    final needed = widget.selectedExercise.holdSeconds;

    if (inPosition) {
      _lostSince = null;
      if (_holdStart == null) {
        _log.info('RepCycle', 'Hold started', {
          'hold': _repCounter + 1,
          'neededS': needed,
          'angle': _currentAngle.round(),
        });
      }
      _holdStart ??= now;
      final elapsed = now.difference(_holdStart!).inMilliseconds / 1000.0;
      _holdElapsed = elapsed > needed ? needed.toDouble() : elapsed;

      if (elapsed >= needed && !_holdCounted) {
        _holdCounted = true;
        _repScores.add(1.0);
        _repCounter++;
        _log.info('RepCycle', 'Hold counted', {
          'hold': _repCounter,
          'target': widget.selectedExercise.targetReps,
          'heldS': _round2(elapsed),
        });
        _triggerFeedback();
        _checkCompletion();
      }
    } else {
      _lostSince ??= now;
      if (now.difference(_lostSince!) > _holdGrace) {
        if (_holdStart != null || _holdElapsed != 0.0) {
          _log.info('RepCycle', 'Hold lost', {
            'heldS': _round2(_holdElapsed),
            'neededS': needed,
            'alreadyCounted': _holdCounted,
            'graceMs': _holdGrace.inMilliseconds,
          });
          _holdStart = null;
          _holdCounted = false; // release, then hold again for the next one
          _holdElapsed = 0.0;
        }
      }
    }
  }

  // ---------------------------------------------------------------------
  // Session completion
  // ---------------------------------------------------------------------

  void _checkCompletion() {
    if (_isSessionComplete) return;
    if (_repCounter < widget.selectedExercise.targetReps) return;

    setState(() => _isSessionComplete = true);
    _logSessionSummary('completed');
    unawaited(_disposeCamera());
    // Saved from the completion dialog so the pain check-in is included.
    _showCompletionBanner();
  }

  /// Back pressed mid-session. Nothing attempted yet → just leave; otherwise
  /// confirm, then save the partial session (with pain check-in) so the
  /// therapist still sees it.
  Future<void> _confirmEndEarly() async {
    // A second back press while the dialog is up must not stack another.
    if (_endDialogOpen || _isSessionComplete) return;
    if (_repCounter == 0 && _rejectedReps == 0) {
      setState(() => _isSessionComplete = true);
      _logSessionSummary('leftBeforeFirstRep');
      Navigator.of(context).pop();
      return;
    }
    _endDialogOpen = true;
    final bool? end;
    try {
      end = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: dialogContext.palette.surface,
          title: const Text('End session early?'),
          content: Text(
            'You have done $_repCounter of ${widget.selectedExercise.targetReps}. '
            'Your progress will be saved for your therapist.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep going'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('End session'),
            ),
          ],
        ),
      );
    } finally {
      _endDialogOpen = false;
    }
    if (end != true || !mounted || _isSessionComplete) return;
    setState(() => _isSessionComplete = true);
    _logSessionSummary('endedEarly');
    unawaited(_disposeCamera());
    _showCompletionBanner(endedEarly: true);
  }

  /// One info event per session with everything needed to judge how the
  /// session went technically. Safe to call more than once (logs once).
  void _logSessionSummary(String outcome) {
    if (_summaryLogged) return;
    _summaryLogged = true;
    final exercise = widget.selectedExercise;
    _log.info('PosePipeline', 'Session summary', {
      'outcome': outcome,
      'exercise': exercise.type.name,
      'isHold': exercise.isHold,
      'reps': _repCounter,
      'targetReps': exercise.targetReps,
      'rejected': _rejectedReps,
      'rejectRules': Map<String, int>.of(_rejectRules),
      'rejectCodes': Map<String, int>.of(_rejectCodes),
      'durationS': DateTime.now().difference(_sessionStart).inSeconds,
      'lens': _lensDirection.name,
      'resolution': _resolutionLabel,
      'cameraSwitches': _cameraSwitches,
      'lifecyclePauses': _lifecyclePauses,
      ..._stats.sessionTotals(_frameClock.elapsedMilliseconds),
    });
  }

  Future<void> _saveSession({
    required int painLevel,
    String? painNote,
    bool endedEarly = false,
  }) async {
    final exercise = widget.selectedExercise;
    final prescription = exercise.prescription;
    final session = ExerciseSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      exerciseId: exercise.type.name,
      exerciseName: exercise.title,
      startTime: _sessionStart,
      endTime: DateTime.now(),
      completedReps: _repCounter,
      completedSets: endedEarly ? 0 : 1,
      targetReps: exercise.targetReps,
      targetSets: 1,
      repComplianceScores: List<double>.from(_repScores),
      notes: _rejectedReps > 0
          ? '$_rejectedReps rep(s) rejected for poor form or range'
          : null,
      prescriptionId: prescription?.id,
      rejectedReps: _rejectedReps,
      painLevel: painLevel,
      painNote: painNote,
      outsideSchedule:
          prescription != null && !prescription.isWithinSchedule(_sessionStart),
      endedEarly: endedEarly,
    );

    if (!mounted) return;
    await _log.timed(
      'PoseSession',
      'Save session',
      () => context.read<AppProvider>().recordCompletedSession(session),
      data: {
        'exercise': exercise.type.name,
        'reps': _repCounter,
        'rejected': _rejectedReps,
        'endedEarly': endedEarly,
        'painLevel': painLevel,
        'hasPainNote': painNote != null,
        'outsideSchedule': session.outsideSchedule,
      },
    );
  }

  void _showCompletionBanner({bool endedEarly = false}) {
    final exercise = widget.selectedExercise;
    if (!mounted) return;

    var pain = 0;
    var saving = false;
    final noteController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: dialogContext.palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                endedEarly
                    ? Icons.flag_circle_rounded
                    : Icons.check_circle_rounded,
                color: endedEarly ? Colors.orange : Colors.teal,
                size: 64,
              ),
              const SizedBox(height: 12),
              Text(
                endedEarly ? 'Session Ended' : 'Session Complete!',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                endedEarly
                    ? 'You did $_repCounter of ${exercise.targetReps} '
                          '${exercise.isHold ? 'holds' : 'reps'} of ${exercise.title}.'
                    : exercise.isHold
                    ? 'You finished ${exercise.targetReps} holds of ${exercise.title}.'
                    : 'You finished ${exercise.targetReps} reps of ${exercise.title}.',
                textAlign: TextAlign.center,
                style: TextStyle(color: dialogContext.palette.textSecondary),
              ),
              if (_rejectedReps > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '$_rejectedReps attempt(s) were not counted because of form.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
              const Divider(height: 28),
              Text(
                'How much pain do you feel now? ($pain/10)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Slider(
                value: pain.toDouble(),
                min: 0,
                max: 10,
                divisions: 10,
                label: '$pain',
                activeColor: pain >= 7
                    ? Colors.redAccent
                    : pain >= 4
                    ? Colors.orange
                    : Colors.teal,
                onChanged: saving
                    ? null
                    : (v) => setDialogState(() => pain = v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'No pain',
                    style: TextStyle(
                      fontSize: 11,
                      color: dialogContext.palette.textMuted,
                    ),
                  ),
                  Text(
                    'Worst pain',
                    style: TextStyle(
                      fontSize: 11,
                      color: dialogContext.palette.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                enabled: !saving,
                maxLines: 2,
                maxLength: 300,
                decoration: const InputDecoration(
                  hintText: 'Anything to tell your therapist? (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () async {
                      // Two taps can land before the rebuild disables the
                      // button: only the first one may save and navigate.
                      if (saving) return;
                      setDialogState(() => saving = true);
                      final note = noteController.text.trim();
                      try {
                        await _saveSession(
                          painLevel: pain,
                          painNote: note.isEmpty ? null : note,
                          endedEarly: endedEarly,
                        );
                      } catch (e, st) {
                        // _log.timed already logged the failure with its
                        // timing; this records that the user was told.
                        _log.error(
                          'PoseSession',
                          'Session not saved; user notified',
                          {'endedEarly': endedEarly},
                          e,
                          st,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not save this session. Please sign in again.',
                              ),
                            ),
                          );
                        }
                      }
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                      if (!mounted) return;
                      // If the target was reached while "End session
                      // early?" was open, that dialog is still underneath
                      // (showDialog uses the root navigator). Close it first,
                      // or the pop below would close it instead of this
                      // screen and strand the patient on a dead camera.
                      if (_endDialogOpen) {
                        Navigator.of(context, rootNavigator: true).pop();
                      }
                      Navigator.of(context).pop();
                    },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    ).whenComplete(noteController.dispose);
  }

  double _calculateAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    double radians =
        atan2(p3.y - p2.y, p3.x - p2.x) - atan2(p1.y - p2.y, p1.x - p2.x);
    double angle = (radians * 180.0 / pi).abs();
    if (angle > 180.0) angle = 360.0 - angle;
    return angle;
  }

  InputImage? _inputImageFromCameraImage(
    CameraImage image,
    CameraDescription camera,
  ) {
    if (image.planes.isEmpty) return null;

    final sensorOrientation = camera.sensorOrientation;
    final rotation =
        InputImageRotationValue.fromRawValue(sensorOrientation) ??
        InputImageRotation.rotation0deg;
    final format =
        InputImageFormatValue.fromRawValue(image.format.raw) ??
        InputImageFormat.nv21;

    // Android + ImageFormatGroup.nv21 delivers ONE plane holding the whole
    // NV21 frame (camera_android_camerax converts it natively), so its bytes
    // can go to ML Kit as they are. Copying them into a WriteBuffer, as the
    // generic multi-plane path below does, would allocate and copy ~115 KB
    // per analysed frame for nothing.
    final Uint8List bytes;
    if (image.planes.length == 1) {
      bytes = image.planes.first.bytes;
    } else {
      final allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      bytes = allBytes.done().buffer.asUint8List();
    }

    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _logSessionSummary('closed');
    unawaited(
      _audioPlayer.dispose().catchError(
        (Object e, StackTrace st) =>
            _log.warn('PoseAudio', 'Audio dispose failed', null, e, st),
      ),
    );
    final tts = _tts;
    _tts = null;
    if (tts != null) unawaited(_stopTts(tts));
    unawaited(_shutdownPipeline());
    super.dispose();
  }

  /// Order matters: stop the camera (no new frames), wait for the frame that
  /// is still inside ML Kit, and only then close the detector. Closing it
  /// while processImage is in flight makes that call fail natively, and on
  /// Android a processImage that arrives after close() silently creates a
  /// new native detector that is never closed (a leak).
  Future<void> _shutdownPipeline() async {
    _detectorClosing = true;
    await _disposeCamera();

    final inFlight = _inFlightFrame;
    if (inFlight != null && !inFlight.isCompleted) {
      await inFlight.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => _log.warn(
          'PosePipeline',
          'Closing detector with a frame still in flight',
          {'waitedMs': 2000},
        ),
      );
    }

    try {
      await _poseDetector.close();
      _log.info('PosePipeline', 'Pose detector closed');
    } catch (e, st) {
      _log.warn('PosePipeline', 'Pose detector close failed', null, e, st);
    }
  }

  // The preview subtree only depends on the controller (and on MediaQuery,
  // which it subscribes to itself). Reusing the SAME widget instance lets
  // Flutter skip rebuilding it on the ~15 setStates per second caused by
  // processed frames; CameraPreview already repaints its own texture.
  Widget? _previewWidget;
  CameraController? _previewController;

  Widget _cachedPreview(CameraController controller) {
    if (_previewWidget == null || !identical(_previewController, controller)) {
      _previewController = controller;
      _previewWidget = RepaintBoundary(
        child: _AspectCoverPreview(controller: controller, cover: _coverPreview),
      );
    }
    return _previewWidget!;
  }

  @override
  Widget build(BuildContext context) {
    final exercise = widget.selectedExercise;

    if (_cameraError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(exercise.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.videocam_off_rounded,
                  size: 56,
                  color: context.palette.textMuted,
                ),
                const SizedBox(height: 16),
                Text(
                  _cameraError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _initCamera,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final form = _effectiveForm;
    final isCorrect = !form.isWrong;

    return PopScope(
      canPop: _isSessionComplete,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmEndEarly();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(exercise.title),
          backgroundColor: isCorrect ? Colors.teal : Colors.red,
          actions: [
            IconButton(
              icon: Icon(
                Icons.flip,
                color: _mirrorSkeleton ? Colors.white : Colors.white54,
              ),
              tooltip: "Flip skeleton (use if it moves opposite to you)",
              onPressed: () =>
                  setState(() => _mirrorSkeleton = !_mirrorSkeleton),
            ),
            IconButton(
              icon: const Icon(Icons.cameraswitch),
              tooltip: "Switch Camera",
              onPressed: _switchCamera,
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            _cachedPreview(controller),

            if (_settings.showSkeleton &&
                _imageSize != null &&
                _detectedPoses.isNotEmpty)
              RepaintBoundary(
                child: CustomPaint(
                  painter: PosePainter(
                    _detectedPoses,
                    _imageSize!,
                    _rotation,
                    isCorrect,
                    _lensDirection,
                    mirrorX: _mirrorSkeleton,
                    cover: _coverPreview,
                    flaggedLandmarks: form.flagged,
                    issues: form.issues,
                  ),
                ),
              ),

            if (_countingDown)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Get into position',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(blurRadius: 8)],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 6,
                      ),
                      child: Text(
                        exercise.setupTip,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          shadows: [Shadow(blurRadius: 8)],
                        ),
                      ),
                    ),
                    Text(
                      '$_countdownLeft',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 96,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(blurRadius: 12)],
                      ),
                    ),
                  ],
                ),
              ),

            // "Keep Centered: ..." / "Wrong Form: ..." message, and until the
            // first rep is attempted, where to stand (after the countdown
            // the big centred version of the tip is gone).
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FormBanner(form: form),
                  if (_showSetupTip) ...[
                    const SizedBox(height: 6),
                    _SetupTip(text: exercise.setupTip),
                  ],
                ],
              ),
            ),

            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (isCorrect ? Colors.black87 : Colors.red.shade900)
                      .withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (exercise.isHold) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (_holdElapsed / exercise.holdSeconds)
                              .clamp(0.0, 1.0)
                              .toDouble(),
                          minHeight: 8,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isCorrect ? Colors.greenAccent : Colors.redAccent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              exercise.isHold ? "HOLDS" : "REPS",
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              "$_repCounter / ${exercise.targetReps}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              exercise.isHold ? "HOLD" : "ANGLE",
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              exercise.isHold
                                  ? "${_holdElapsed.toStringAsFixed(1)} / ${exercise.holdSeconds}s"
                                  : "${_currentAngle.round()}°",
                              style: TextStyle(
                                color: isCorrect
                                    ? Colors.greenAccent
                                    : Colors.redAccent,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (!isCorrect) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Why red: ${form.issues.map((i) => i.code.name).join(', ')}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (_rejectedReps > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Not counted: $_rejectedReps',
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cheap counters for the camera -> ML Kit pipeline.
///
/// Updated on every camera frame, so it only increments ints (no
/// allocation, no logging). Every [windowMs] the screen calls [takeWindow],
/// which builds ONE data map for the "Pipeline window" log and starts a new
/// window. [sessionTotals] feeds the "Session summary" log.
///
/// Times are passed in as monotonic milliseconds (a Stopwatch), which keeps
/// the class pure and easy to unit test.
///
/// How to read a window (for a developer or an AI assistant):
///   received      frames the camera delivered (CameraX: ~30 fps)
///   processed     frames ML Kit analysed; processedFps is the real
///                 analysis rate (capped at ~15 fps by the throttle)
///   skippedBusy   frames dropped because ML Kit was still busy. High
///                 values with avg/maxMlMs > 66 mean the phone is too slow
///                 for the cap
///   skippedThrottle  frames dropped by the fps cap (normal, ~half)
///   skippedInactive  frames after close / session end / camera switch
///   posesFound / posesEmpty  whether ML Kit saw a person at all
///   wrongForm / notInFrame   processed frames per final form verdict
///   errors / discarded / conversionFailed  should all be 0
class PosePipelineStats {
  PosePipelineStats({this.windowMs = 5000});

  /// Length of one reporting window.
  final int windowMs;

  int _windowStartMs = 0;

  // Current window.
  int _received = 0;
  int _processed = 0;
  int _skippedBusy = 0;
  int _skippedThrottle = 0;
  int _skippedInactive = 0;
  int _posesFound = 0;
  int _posesEmpty = 0;
  int _wrongForm = 0;
  int _notInFrame = 0;
  int _errors = 0;
  int _discarded = 0;
  int _conversionFailed = 0;
  int _latencySumUs = 0;
  int _latencyMaxUs = 0;

  // Whole session.
  int _totalReceived = 0;
  int _totalProcessed = 0;
  int _totalSkippedBusy = 0;
  int _totalPosesEmpty = 0;
  int _totalErrors = 0;
  int _totalLatencySumUs = 0;
  int _totalLatencyMaxUs = 0;

  int get totalErrors => _totalErrors;
  int get totalProcessed => _totalProcessed;

  void onReceived() {
    _received++;
    _totalReceived++;
  }

  void onSkippedBusy() {
    _skippedBusy++;
    _totalSkippedBusy++;
  }

  void onSkippedThrottle() => _skippedThrottle++;
  void onSkippedInactive() => _skippedInactive++;
  void onConversionFailed() => _conversionFailed++;
  void onResultDiscarded() => _discarded++;

  void onError() {
    _errors++;
    _totalErrors++;
  }

  /// One ML Kit call finished after [latencyUs] microseconds.
  void onProcessed({required int latencyUs, required bool poseFound}) {
    _processed++;
    _totalProcessed++;
    _latencySumUs += latencyUs;
    _totalLatencySumUs += latencyUs;
    if (latencyUs > _latencyMaxUs) _latencyMaxUs = latencyUs;
    if (latencyUs > _totalLatencyMaxUs) _totalLatencyMaxUs = latencyUs;
    if (poseFound) {
      _posesFound++;
    } else {
      _posesEmpty++;
      _totalPosesEmpty++;
    }
  }

  /// The screen's final form verdict for a processed frame.
  void onForm(FormStatus status) {
    if (status == FormStatus.wrongForm) _wrongForm++;
    if (status == FormStatus.notInFrame) _notInFrame++;
  }

  bool isWindowDue(int nowMs) => nowMs - _windowStartMs >= windowMs;

  /// Returns the finished window's numbers and starts a new window, or null
  /// if nothing happened in it.
  Map<String, Object?>? takeWindow(int nowMs) {
    final elapsedMs = max(1, nowMs - _windowStartMs);
    final data = _received == 0
        ? null
        : <String, Object?>{
            'windowMs': elapsedMs,
            'received': _received,
            'processed': _processed,
            'skippedBusy': _skippedBusy,
            'skippedThrottle': _skippedThrottle,
            'skippedInactive': _skippedInactive,
            'receivedFps': _fps(_received, elapsedMs),
            'processedFps': _fps(_processed, elapsedMs),
            'avgMlMs': _avgMs(_latencySumUs, _processed),
            'maxMlMs': _round1(_latencyMaxUs / 1000),
            'posesFound': _posesFound,
            'posesEmpty': _posesEmpty,
            'wrongForm': _wrongForm,
            'notInFrame': _notInFrame,
            'errors': _errors,
            'discarded': _discarded,
            'conversionFailed': _conversionFailed,
          };

    _windowStartMs = nowMs;
    _received = 0;
    _processed = 0;
    _skippedBusy = 0;
    _skippedThrottle = 0;
    _skippedInactive = 0;
    _posesFound = 0;
    _posesEmpty = 0;
    _wrongForm = 0;
    _notInFrame = 0;
    _errors = 0;
    _discarded = 0;
    _conversionFailed = 0;
    _latencySumUs = 0;
    _latencyMaxUs = 0;
    return data;
  }

  /// Whole-session numbers for the "Session summary" log.
  Map<String, Object?> sessionTotals(int nowMs) => {
    'framesReceived': _totalReceived,
    'framesProcessed': _totalProcessed,
    'framesSkippedBusy': _totalSkippedBusy,
    'framesNoPose': _totalPosesEmpty,
    'frameErrors': _totalErrors,
    'avgProcessedFps': _fps(_totalProcessed, max(1, nowMs)),
    'avgMlMs': _avgMs(_totalLatencySumUs, _totalProcessed),
    'maxMlMs': _round1(_totalLatencyMaxUs / 1000),
  };

  static double _fps(int frames, int ms) => _round1(frames * 1000 / ms);

  static double _avgMs(int sumUs, int count) =>
      count == 0 ? 0 : _round1(sumUs / count / 1000);

  static double _round1(double v) => (v * 10).roundToDouble() / 10;
}

/// Camera preview drawn at the sensor's native aspect ratio.
///  - cover=false: the whole frame is visible (letterboxed).
///  - cover=true : the frame fills the screen and the overflow is cropped.
/// PosePainter uses the identical mapping, so video and skeleton line up.
/// This widget must NOT apply its own horizontal flip.
class _AspectCoverPreview extends StatelessWidget {
  final CameraController controller;
  final bool cover;

  const _AspectCoverPreview({required this.controller, this.cover = false});

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;
    if (size == null || size.width <= 0 || size.height <= 0) {
      return const SizedBox.shrink();
    }

    final longSide = max(size.width, size.height);
    final shortSide = min(size.width, size.height);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final frame = isLandscape
        ? Size(longSide, shortSide)
        : Size(shortSide, longSide);

    return LayoutBuilder(
      builder: (context, constraints) {
        final sx = constraints.maxWidth / frame.width;
        final sy = constraints.maxHeight / frame.height;
        final scale = cover ? max(sx, sy) : min(sx, sy);
        final w = frame.width * scale;
        final h = frame.height * scale;

        return ClipRect(
          child: Center(
            child: SizedBox(
              width: w,
              height: h,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}

/// Top-of-screen message: red bold label + the current fault.
class _FormBanner extends StatelessWidget {
  final FormResult form;
  const _FormBanner({required this.form});

  @override
  Widget build(BuildContext context) {
    if (form.isOk) return const SizedBox.shrink();

    final label = form.isNotInFrame ? 'Keep Centered: ' : 'Wrong Form: ';
    final message = form.primary?.message ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          children: [
            TextSpan(
              text: label,
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            TextSpan(
              text: message,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Where to stand" reminder under the form banner (see [_showSetupTip]).
class _SetupTip extends StatelessWidget {
  final String text;
  const _SetupTip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_outlined, color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
