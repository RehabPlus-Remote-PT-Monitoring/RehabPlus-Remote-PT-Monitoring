// lib/services/replay_recorder.dart
//
// Movement replay: collects the pose points the exercise screen already
// tracks and packs them into the byte layout the dashboard replays as a
// stick figure. No images, video or audio are ever involved: only the 33
// landmark positions (normalised 0-1), their confidence, the measured angle
// and the time.
//
// Format (docs/superpowers/specs/2026-11-15-movement-replay-design.md and
// API_CONTRACT.md "replay/"), one 171-byte record per kept frame,
// little-endian:
//   uint32  t       ms since the session started
//   uint16  angle   tenths of a degree, 0xFFFF = not measured this frame
//   33 x (uint16 x * 10000, uint16 y * 10000, uint8 confidence * 255)
//           in ML Kit's PoseLandmarkType order; a missing landmark is
//           x = y = 0xFFFF, confidence 0
// Frames are grouped 300 to a chunk (Firestore docs c000..c019).
//
// Pure Dart on purpose (no Flutter UI, no Firebase, no ML Kit), so the byte
// layout and every limit the security rules enforce are unit-tested in
// test/replay_recorder_test.dart with a test-side decoder.

import 'dart:typed_data';

import '../core/diagnostic_logger.dart';

/// One landmark of one frame, already normalised to the upright image:
/// [x] and [y] are 0-1 of its width and height, [confidence] 0-1 (ML Kit's
/// likelihood). Values outside those ranges are clamped when encoded.
class ReplayPoint {
  const ReplayPoint(this.x, this.y, this.confidence);

  final double x;
  final double y;
  final double confidence;
}

/// One chunk document (`replay/c000` ...): [frames] records starting at frame
/// number [firstFrame], packed in [data] ([frames] x 171 bytes).
class ReplayChunk {
  const ReplayChunk({
    required this.index,
    required this.firstFrame,
    required this.frames,
    required this.data,
  });

  final int index;
  final int firstFrame;
  final int frames;
  final Uint8List data;

  /// Firestore document id: c000, c001, ... (matches the rules' pattern).
  String get docId => 'c${index.toString().padLeft(3, '0')}';
}

/// Everything one session's replay writes: the `replay/meta` fields (without
/// `createdAt`, which the storage layer adds as a server timestamp) and the
/// chunk documents.
class ReplayPayload {
  const ReplayPayload({required this.meta, required this.chunks});

  final Map<String, Object?> meta;
  final List<ReplayChunk> chunks;

  /// Total packed bytes, for the log.
  int get byteCount => chunks.fold(0, (sum, c) => sum + c.data.length);
}

/// Event kinds the dashboard draws on the timeline (rules/contract values).
abstract final class ReplayEventKind {
  static const String counted = 'counted';
  static const String rejected = 'rejected';
  static const String hold = 'hold';

  static const Set<String> all = {counted, rejected, hold};
}

/// Collects frames and rep events during one session, then [encode]s them.
///
/// Cheap per frame on purpose (it runs inside the camera frame loop): a frame
/// closer than `1000 / fpsCap` ms to the last kept one is dropped after one
/// integer comparison, and a kept frame is packed straight into its 171-byte
/// record, so [encode] only has to copy bytes.
///
/// Log events (tag 'ReplayRecorder'): "Replay cap reached" {frames, tMs,
/// maxDurationMs} once; "Replay events dropped" {limit, reason} once;
/// "Replay frame dropped: time went backwards" once.
class ReplayRecorder {
  ReplayRecorder({
    int fpsCap = 10,
    this.maxDurationMs = 600000,
    DiagnosticLogger? logger,
  }) : fps = fpsCap.clamp(1, maxFps),
       _logger = logger ?? DiagnosticLogger.I;

  // ---- Format constants (shared with the rules and the dashboard) ----

  static const int formatVersion = 1;
  static const int landmarkCount = 33;
  static const int bytesPerLandmark = 5;
  static const int headerBytes = 6; // uint32 t + uint16 angle
  static const int frameBytes = headerBytes + landmarkCount * bytesPerLandmark;
  static const int framesPerChunk = 300;
  static const int maxChunks = 20;
  static const int maxFrames = framesPerChunk * maxChunks; // 6000
  static const int maxFps = 10;
  static const int maxEvents = 200;
  static const int maxNoteLength = 120;
  static const int maxAngleLabelLength = 60;

  /// Marks "no value" in a uint16 field (missing landmark, no angle).
  static const int none16 = 0xFFFF;

  /// Largest angle that fits below [none16] in tenths of a degree.
  static const double maxAngle = 6553.4;

  /// The rules accept an aspect ratio of 0.2 to 5.
  static const double minAspect = 0.2;
  static const double maxAspect = 5;

  /// Recorded frame rate (1-10), stored in the meta doc.
  final int fps;

  /// Frames later than this (ms since the session started) are not kept.
  final int maxDurationMs;

  final DiagnosticLogger _logger;

  final List<Uint8List> _frames = [];
  final List<Map<String, Object>> _events = [];
  int _lastKeptMs = -1;
  bool _truncated = false;
  bool _loggedBackwards = false;
  bool _loggedEventsDropped = false;

  /// Minimum gap between kept frames (100 ms at 10 fps).
  int get minFrameGapMs => 1000 ~/ fps;

  int get frameCount => _frames.length;
  int get eventCount => _events.length;

  /// The session ran past the cap, so only its beginning was kept.
  bool get truncated => _truncated;

  /// Whether a frame at [tMs] would be kept. Lets the caller skip turning
  /// ML Kit's landmarks into [ReplayPoint]s for the frames that are dropped
  /// anyway (most of them on a phone tracking faster than 10 fps).
  bool wantsFrame(int tMs) =>
      !_truncated && (_lastKeptMs < 0 || tMs - _lastKeptMs >= minFrameGapMs);

  /// Adds one analysed camera frame taken [tMs] after the session started.
  ///
  /// [points] holds 33 entries in PoseLandmarkType order (null = that
  /// landmark wasn't returned), or is empty when no person was found.
  /// [angle] is the exercise's measured angle in degrees, or null when it
  /// couldn't be measured this frame.
  ///
  /// Returns true when the frame was kept (false: too soon after the last
  /// kept one, past the cap, or out of order).
  bool addFrame(int tMs, List<ReplayPoint?> points, double? angle) {
    if (_truncated) return false;
    if (tMs < 0 || (_lastKeptMs >= 0 && tMs < _lastKeptMs)) {
      if (!_loggedBackwards) {
        _loggedBackwards = true;
        _logger.warn(
          'ReplayRecorder',
          'Replay frame dropped: time went backwards',
          {'tMs': tMs, 'lastKeptMs': _lastKeptMs},
        );
      }
      return false;
    }
    if (_lastKeptMs >= 0 && tMs - _lastKeptMs < minFrameGapMs) return false;
    if (tMs > maxDurationMs || _frames.length >= maxFrames) {
      _truncated = true;
      _logger.info('ReplayRecorder', 'Replay cap reached', {
        'frames': _frames.length,
        'tMs': tMs,
        'maxDurationMs': maxDurationMs,
      });
      return false;
    }

    _frames.add(_packFrame(tMs, points, angle));
    _lastKeptMs = tMs;
    return true;
  }

  /// Records a rep/hold verdict at [tMs] (same clock as [addFrame]).
  ///
  /// [kind] is one of [ReplayEventKind.all]; [note] is what the patient was
  /// told (clipped to 120 characters). At most 200 events are kept; events
  /// after the duration cap are dropped because they would sit beyond the
  /// end of the recorded timeline. Unknown kinds are dropped too, since the
  /// dashboard couldn't draw them.
  void addEvent(int tMs, String kind, String note) {
    String? dropReason;
    if (!ReplayEventKind.all.contains(kind)) {
      dropReason = 'unknownKind';
    } else if (_events.length >= maxEvents) {
      dropReason = 'tooMany';
    } else if (tMs > maxDurationMs) {
      dropReason = 'afterCap';
    }
    if (dropReason != null) {
      if (!_loggedEventsDropped) {
        _loggedEventsDropped = true;
        _logger.warn('ReplayRecorder', 'Replay events dropped', {
          'limit': maxEvents,
          'reason': dropReason,
        });
      }
      return;
    }
    _events.add({
      't': tMs < 0 ? 0 : tMs,
      'kind': kind,
      'note': clipText(note, maxNoteLength),
    });
  }

  /// Packs everything recorded so far, or returns null when no frame was
  /// kept (the rules need at least one chunk, and an empty replay would show
  /// nothing anyway).
  ///
  /// [aspect] is the upright image width / height (clamped to the rules'
  /// 0.2-5; 1 when unusable). [mirrored] is whether the patient saw the
  /// skeleton mirrored. [angleLabel] says what the angle measures.
  ReplayPayload? encode({
    required double aspect,
    required bool mirrored,
    String? angleLabel,
  }) {
    if (_frames.isEmpty) return null;

    final chunks = <ReplayChunk>[];
    for (var first = 0; first < _frames.length; first += framesPerChunk) {
      final end = (first + framesPerChunk).clamp(0, _frames.length);
      final data = Uint8List((end - first) * frameBytes);
      for (var i = first; i < end; i++) {
        data.setRange(
          (i - first) * frameBytes,
          (i - first + 1) * frameBytes,
          _frames[i],
        );
      }
      chunks.add(
        ReplayChunk(
          index: chunks.length,
          firstFrame: first,
          frames: end - first,
          data: data,
        ),
      );
    }

    final lastT = ByteData.sublistView(
      _frames.last,
    ).getUint32(0, Endian.little);
    final meta = <String, Object?>{
      'version': formatVersion,
      'fps': fps,
      'frameCount': _frames.length,
      'chunkCount': chunks.length,
      'durationMs': lastT,
      'truncated': _truncated,
      'aspect': _safeAspect(aspect),
      'mirrored': mirrored,
      if (angleLabel != null && angleLabel.trim().isNotEmpty)
        'angleLabel': clipText(angleLabel.trim(), maxAngleLabelLength),
      'events': [for (final e in _events) Map<String, Object>.of(e)],
    };
    return ReplayPayload(meta: meta, chunks: chunks);
  }

  // ---- Packing helpers ----

  static Uint8List _packFrame(
    int tMs,
    List<ReplayPoint?> points,
    double? angle,
  ) {
    final bytes = Uint8List(frameBytes);
    final view = ByteData.sublistView(bytes);
    view.setUint32(0, tMs, Endian.little);
    view.setUint16(4, encodeAngle(angle), Endian.little);
    for (var i = 0; i < landmarkCount; i++) {
      final offset = headerBytes + i * bytesPerLandmark;
      final p = i < points.length ? points[i] : null;
      if (p == null || !p.x.isFinite || !p.y.isFinite) {
        view.setUint16(offset, none16, Endian.little);
        view.setUint16(offset + 2, none16, Endian.little);
        view.setUint8(offset + 4, 0);
        continue;
      }
      view.setUint16(offset, _unit16(p.x), Endian.little);
      view.setUint16(offset + 2, _unit16(p.y), Endian.little);
      view.setUint8(offset + 4, _unit8(p.confidence));
    }
    return bytes;
  }

  /// Degrees -> tenths of a degree, or [none16] when null, not finite, or
  /// outside 0..[maxAngle] (no real joint angle is ever out there).
  static int encodeAngle(double? angle) {
    if (angle == null || !angle.isFinite || angle < 0 || angle > maxAngle) {
      return none16;
    }
    return (angle * 10).round();
  }

  /// 0-1 -> 0-10000 (clamped).
  static int _unit16(double v) => (v.clamp(0.0, 1.0) * 10000).round();

  /// 0-1 -> 0-255 (clamped; NaN counts as 0).
  static int _unit8(double v) =>
      v.isFinite ? (v.clamp(0.0, 1.0) * 255).round() : 0;

  static double _safeAspect(double aspect) {
    if (!aspect.isFinite || aspect <= 0) return 1.0;
    return aspect.clamp(minAspect, maxAspect).toDouble();
  }

  /// [text] cut to at most [max] UTF-16 units, never splitting a surrogate
  /// pair (an emoji cut in half would be invalid text). Firestore rules count
  /// characters, which is never more than UTF-16 units, so this always fits.
  static String clipText(String text, int max) {
    if (text.length <= max) return text;
    var end = max;
    final last = text.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--; // high surrogate
    return text.substring(0, end);
  }
}
