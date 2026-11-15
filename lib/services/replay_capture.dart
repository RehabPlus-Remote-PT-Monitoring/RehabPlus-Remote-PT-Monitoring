// lib/services/replay_capture.dart
//
// The thin bridge between PoseDetectorScreen and [ReplayRecorder]: turns
// ML Kit's landmark map into normalised [ReplayPoint]s, puts every time on
// the session's clock, and makes sure a bug in the replay can never break
// tracking (every call is guarded; the first failure is logged).
//
// Kept out of the screen file so the screen only needs a few one-line hooks
// (that file is merged into the iPhone branch, so its diff stays small).

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    show PoseLandmark, PoseLandmarkType;

import '../core/diagnostic_logger.dart';
import 'replay_recorder.dart';

/// Records one session's movement replay.
///
/// Clock: every time passed in is a reading of the screen's monotonic frame
/// clock (a Stopwatch, immune to wall-clock changes). [originMs] is that
/// clock's reading when the session started (next to the session's
/// `startTime`), so `t = clockMs - originMs` is "ms since the session
/// started" for frames and events alike.
///
/// Log events (tag 'Replay'): "Replay recording started" {fps, maxS};
/// "Replay frame failed" / "Replay event failed" (first failure only, with
/// the error); "Replay ready" {frames, chunks, bytes, events, truncated,
/// durationMs, mirrored}; "Replay empty: nothing to save";
/// "Replay encode failed".
class ReplayCapture {
  ReplayCapture({
    required this.originMs,
    ReplayRecorder? recorder,
    DiagnosticLogger? logger,
  }) : _recorder = recorder ?? ReplayRecorder(),
       _logger = logger ?? DiagnosticLogger.I {
    _logger.info('Replay', 'Replay recording started', {
      'fps': _recorder.fps,
      'maxS': _recorder.maxDurationMs ~/ 1000,
    });
  }

  /// Frame-clock reading (ms) at the moment the session started.
  final int originMs;

  final ReplayRecorder _recorder;
  final DiagnosticLogger _logger;

  /// ML Kit's 33 landmark types in the order the byte layout uses.
  static const List<PoseLandmarkType> _order = PoseLandmarkType.values;

  // Upright image size of the most recent kept frame (what the painter was
  // given), for the meta doc's aspect ratio.
  double _width = 0;
  double _height = 0;

  // How many kept frames were drawn mirrored / not. The patient can flip the
  // skeleton mid-session; the replay is drawn the way most of it was seen.
  int _mirroredFrames = 0;
  int _plainFrames = 0;

  bool _frameErrorLogged = false;
  bool _eventErrorLogged = false;

  /// Adds one processed camera frame.
  ///
  /// [clockMs]: when the camera captured it (frame clock). [landmarks]: the
  /// first pose's landmarks, or null when no person was found.
  /// [uprightWidth] x [uprightHeight]: the rotated (upright) image size the
  /// painter maps landmarks with; x and y are divided by it, so 0-1 here is
  /// exactly the image area the skeleton was drawn over (before mirroring).
  /// [angle]: the angle measured in THIS frame, or null; 0.0 is the screen's
  /// "could not measure" sentinel and is stored as no angle. [mirrored]:
  /// whether the painter flipped the skeleton for this frame.
  ///
  /// Never throws.
  void onFrame({
    required int clockMs,
    required Map<PoseLandmarkType, PoseLandmark>? landmarks,
    required double uprightWidth,
    required double uprightHeight,
    required double? angle,
    required bool mirrored,
  }) {
    try {
      final t = clockMs - originMs;
      // Cheap exit for the frames the 10 fps down-sample drops anyway.
      if (!_recorder.wantsFrame(t)) return;
      if (uprightWidth <= 0 || uprightHeight <= 0) return;

      final points = landmarks == null || landmarks.isEmpty
          ? const <ReplayPoint?>[]
          : _normalise(landmarks, uprightWidth, uprightHeight);
      final kept = _recorder.addFrame(
        t,
        points,
        angle == null || angle == 0.0 ? null : angle,
      );
      if (!kept) return;
      _width = uprightWidth;
      _height = uprightHeight;
      if (mirrored) {
        _mirroredFrames++;
      } else {
        _plainFrames++;
      }
    } catch (e, st) {
      if (_frameErrorLogged) return;
      _frameErrorLogged = true;
      _logger.error(
        'Replay',
        'Replay frame failed',
        {'clockMs': clockMs},
        e,
        st,
      );
    }
  }

  /// Records a rep/hold verdict decided on the frame captured at [clockMs].
  /// [note] is the message the patient saw (empty for counted reps).
  /// Never throws.
  void onEvent(int clockMs, String kind, String note) {
    try {
      _recorder.addEvent(clockMs - originMs, kind, note);
    } catch (e, st) {
      if (_eventErrorLogged) return;
      _eventErrorLogged = true;
      _logger.error('Replay', 'Replay event failed', {'kind': kind}, e, st);
    }
  }

  /// The packed replay, or null when nothing was recorded or packing failed
  /// (the session is then saved without one). Safe to call more than once.
  ReplayPayload? finish({String? angleLabel}) {
    try {
      final payload = _recorder.encode(
        aspect: _height > 0 ? _width / _height : 1.0,
        mirrored: _mirroredFrames > _plainFrames,
        angleLabel: angleLabel,
      );
      if (payload == null) {
        _logger.info('Replay', 'Replay empty: nothing to save');
        return null;
      }
      _logger.info('Replay', 'Replay ready', {
        'frames': payload.meta['frameCount'],
        'chunks': payload.chunks.length,
        'bytes': payload.byteCount,
        'events': _recorder.eventCount,
        'truncated': _recorder.truncated,
        'durationMs': payload.meta['durationMs'],
        'mirrored': payload.meta['mirrored'],
      });
      return payload;
    } catch (e, st) {
      _logger.error('Replay', 'Replay encode failed', null, e, st);
      return null;
    }
  }

  static List<ReplayPoint?> _normalise(
    Map<PoseLandmarkType, PoseLandmark> landmarks,
    double width,
    double height,
  ) {
    return List<ReplayPoint?>.generate(_order.length, (i) {
      final lm = landmarks[_order[i]];
      if (lm == null) return null;
      return ReplayPoint(lm.x / width, lm.y / height, lm.likelihood);
    }, growable: false);
  }
}
