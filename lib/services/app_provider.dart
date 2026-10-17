import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/diagnostic_logger.dart';
import '../models/exercise.dart' as exercise_models;
import '../models/exercise_model.dart' as exercise_model_lib;
import '../models/pose_data.dart';
import '../models/session.dart';
import '../services/auth_service.dart';
import '../services/compliance_tracker.dart';
import '../services/pose_estimation_service.dart';
import '../services/session_storage.dart';

/// Main AppProvider - maintains backward compatibility with existing screens.
///
/// Manages session state, exercise catalog, and an optional pose-tracking
/// camera pipeline for legacy screens. Diagnostic events are logged via
/// [DiagnosticLogger] for AI troubleshooting.
class AppProvider extends ChangeNotifier {
  final DiagnosticLogger _logger = DiagnosticLogger.I;
  final SessionStorage _storage = SessionStorage();
  final PoseEstimationService _poseService;
  final _uuid = const Uuid();

  List<CameraDescription> _cameras = [];
  List<exercise_models.Exercise> _availableExercises = [];
  List<exercise_model_lib.ExerciseConfig> _availableExerciseConfigs = [];
  CameraController? _cameraController;
  PoseData? _currentPose;
  ComplianceTracker? _tracker;
  ExerciseSession? _activeSession;
  List<ExerciseSession> _sessionHistory = [];
  bool _isSessionActive = false;
  bool _isCameraInitialized = false;
  String? _feedbackMessage;
  String? _cameraError;

  /// Creates an [AppProvider] with optional injected services for testing.
  ///
  /// If [poseService] is not provided, a new [PoseEstimationService] is created.
  AppProvider({PoseEstimationService? poseService})
      : _poseService = poseService ?? PoseEstimationService();

  // Getters for backward compatibility
  List<CameraDescription> get cameras => _cameras;
  List<exercise_models.Exercise> get availableExercises => _availableExercises;
  List<exercise_model_lib.ExerciseConfig> get availableExerciseConfigsList =>
      _availableExerciseConfigs;
  CameraController? get cameraController => _cameraController;
  PoseData? get currentPose => _currentPose;
  ComplianceTracker? get tracker => _tracker;
  ExerciseSession? get activeSession => _activeSession;
  List<ExerciseSession> get sessionHistory => _sessionHistory;
  bool get isSessionActive => _isSessionActive;
  bool get isCameraInitialized => _isCameraInitialized;
  String? get feedbackMessage => _feedbackMessage;
  String? get cameraError => _cameraError;

  Future<void> init() async {
    _logger.info('AppProvider', 'Initializing');
    _cameras = await availableCameras();
    _logger.info('AppProvider', 'Available cameras: ${_cameras.length}');
    await loadHistory();
    loadExercises();
    _logger.info('AppProvider', 'Initialized');
  }

  Future<void> loadHistory() async {
    _sessionHistory = await _storage.loadSessions();
    _logger.info('AppProvider', 'Loaded ${_sessionHistory.length} sessions from storage');
    notifyListeners();
  }

  void loadExercises() {
    _availableExercises = exercise_models.defaultExercises;
    _availableExerciseConfigs = exercise_model_lib.availableExercises;
    _logger.info('AppProvider', 'Loaded exercises',
        {
          'legacyCount': _availableExercises.length,
          'configCount': _availableExerciseConfigs.length,
        });
    notifyListeners();
  }

  Future<void> startSession(exercise_models.Exercise exercise) async {
    _logger.info('AppProvider', 'Starting session for exercise: ${exercise.name}');
    _tracker = ComplianceTracker(exercise: exercise);
    _activeSession = ExerciseSession(
      id: _uuid.v4(),
      exerciseId: exercise.id,
      exerciseName: exercise.name,
      startTime: DateTime.now(),
      targetReps: exercise.targetReps,
      targetSets: exercise.targetSets,
    );
    _isSessionActive = true;
    _feedbackMessage = null;
    await _initCamera();
    notifyListeners();
  }

  Future<void> _initCamera() async {
    if (_cameras.isEmpty) {
      _logger.warn('AppProvider', 'No cameras available');
      return;
    }

    final front = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );
    _logger.info('AppProvider', 'Initializing camera: ${front.name} (${front.lensDirection})');

    _cameraController = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      _isCameraInitialized = true;
      _cameraController!.startImageStream(_onFrame);
      _cameraError = null;
      _logger.info('AppProvider', 'Camera initialized and streaming');
    } catch (e, stackTrace) {
      _cameraError = e.toString();
      _isCameraInitialized = false;
      _logger.error('AppProvider', 'Camera initialization failed',
          {'error': e.toString(), 'stackTrace': stackTrace.toString()});
    }
    notifyListeners();
  }

  void _onFrame(CameraImage image) {
    if (!_isSessionActive || _tracker == null || _cameraController == null) {
      return;
    }

    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    // Use a Future with proper error handling to avoid unhandled exceptions
    _poseService
        .processFrame(image, camera)
        .then((pose) {
          if (pose == null) return;
          _currentPose = pose;
          final repCompleted = _tracker!.processFrame(pose);
          if (repCompleted) {
            final score = _tracker!.currentRepScore;
            _activeSession!.repComplianceScores = List.from(_tracker!.repScores);
            _activeSession!.completedReps = _tracker!.completedReps;
            _activeSession!.completedSets = _tracker!.completedSets;
            _feedbackMessage = score > 0.8
                ? '✅ Great form!'
                : score > 0.5
                    ? '⚠️ Watch your form'
                    : '❌ Adjust position';
            _logger.info('AppProvider', 'Rep completed',
                {'score': score, 'reps': _tracker!.completedReps});
          }
          notifyListeners();
        })
        .catchError((error, stackTrace) {
          _logger.error('AppProvider', 'Frame processing error',
              {'error': error.toString(), 'stackTrace': stackTrace.toString()});
          // Don't rethrow - just log and continue processing next frames
        });
  }

  Future<ExerciseSession?> endSession() async {
    if (_activeSession == null) {
      _logger.warn('AppProvider', 'endSession called with no active session');
      return null;
    }

    _logger.info('AppProvider', 'Ending session: ${_activeSession!.exerciseName}');
    _activeSession!.endTime = DateTime.now();
    _activeSession!.completedReps = _tracker?.completedReps ?? 0;
    _activeSession!.completedSets = _tracker?.completedSets ?? 0;
    _activeSession!.repComplianceScores = List.from(_tracker?.repScores ?? []);

    final session = _activeSession!;
    await _disposeCamera();

    _isSessionActive = false;
    _activeSession = null;
    _tracker = null;
    _currentPose = null;
    _feedbackMessage = null;
    _isCameraInitialized = false;
    notifyListeners();

    _logger.info('AppProvider', 'Session ended', {
      'id': session.id,
      'completedReps': session.completedReps,
      'completedSets': session.completedSets,
      'duration': session.endTime!.difference(session.startTime).inSeconds,
    });

    return session;
  }

  Future<void> recordCompletedSession(ExerciseSession session) async {
    _logger.info('AppProvider', 'Recording completed session: ${session.exerciseName}');
    await _storage.saveSession(session);
    await loadHistory();
  }

  Future<void> signOut() async {
    await AuthService.I.signOut();
    _sessionHistory = [];
    notifyListeners();
  }

  Future<void> _disposeCamera() async {
    if (_cameraController == null) return;
    try {
      await _cameraController!.stopImageStream();
    } catch (e) {
      _logger.warn('AppProvider', 'Error stopping image stream: $e');
    }
    try {
      await _cameraController!.dispose();
    } catch (e) {
      _logger.warn('AppProvider', 'Error disposing camera controller: $e');
    }
    _cameraController = null;
    _isCameraInitialized = false;
  }

  @override
  void dispose() {
    _logger.info('AppProvider', 'Disposing');
    _disposeCamera();
    _poseService.dispose();
    super.dispose();
  }
}

/// Extension for easy access in widgets
extension AppProviderExtensions on BuildContext {
  AppProvider get appProvider => read<AppProvider>();
}