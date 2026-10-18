// lib/widgets/pose_painter.dart
//
// Canonical pose skeleton painter with form feedback callouts.
// Used by PoseDetectorScreen. Supports both cover (crop) and fit (letterbox)
// preview modes, and configurable horizontal mirroring for front camera.
//
// Performance notes (this paints up to ~15 times a second):
//   - Paint objects never change, so they are created once (static) instead
//     of on every paint() call.
//   - Callout text is laid out once per distinct message and cached; text
//     layout is the most expensive thing this painter does.
//   - shouldRepaint compares the inputs, so rebuilds that don't change the
//     overlay (countdown ticks, settings) don't repaint it.
import 'dart:math';

import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../services/form_checker.dart';

class PosePainter extends CustomPainter {
  final List<Pose> poses;

  /// Size of the analysis frame in PIXELS, already rotated to display
  /// orientation (portrait phone => swapped W/H).
  final Size absoluteImageSize;
  final InputImageRotation rotation;
  final bool isExerciseCorrect;
  final CameraLensDirection cameraLensDirection;

  /// Flip landmarks horizontally (true for the front camera).
  final bool mirrorX;

  /// Same choice as the preview: false = whole frame visible, true = crop.
  final bool cover;

  /// Joints the form checker wants highlighted.
  final Set<PoseLandmarkType> flaggedLandmarks;

  /// Faults to explain with a callout bubble next to the offending joint.
  final List<FormIssue> issues;

  PosePainter(
    this.poses,
    this.absoluteImageSize,
    this.rotation,
    this.isExerciseCorrect,
    this.cameraLensDirection, {
    this.mirrorX = false,
    this.cover = false,
    this.flaggedLandmarks = const {},
    this.issues = const [],
  });

  static const Set<PoseLandmarkType> _faceLandmarks = {
    PoseLandmarkType.nose,
    PoseLandmarkType.leftEyeInner,
    PoseLandmarkType.leftEye,
    PoseLandmarkType.leftEyeOuter,
    PoseLandmarkType.rightEyeInner,
    PoseLandmarkType.rightEye,
    PoseLandmarkType.rightEyeOuter,
    PoseLandmarkType.leftEar,
    PoseLandmarkType.rightEar,
    PoseLandmarkType.leftMouth,
    PoseLandmarkType.rightMouth,
  };

  static const List<List<PoseLandmarkType>> _bones = [
    // Arms
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    // Legs
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
    // Torso
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
  ];

  // ---- Paints (immutable after creation, shared by every frame) ----

  static final Paint _okDotPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = Colors.greenAccent;
  static final Paint _wrongDotPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = Colors.yellowAccent;

  static final Paint _okLinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.0
    ..strokeCap = StrokeCap.round
    ..color = Colors.greenAccent;
  static final Paint _wrongLinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.0
    ..strokeCap = StrokeCap.round
    ..color = Colors.redAccent;

  static final Paint _hotLinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6.5
    ..strokeCap = StrokeCap.round
    ..color = Colors.red;

  static final Paint _glowPaint = Paint()
    ..color = Colors.redAccent.withValues(alpha: 0.35);
  static final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..color = Colors.white;
  static final Paint _corePaint = Paint()..color = Colors.redAccent;

  static const Color _calloutRed = Color(0xFFD50000);
  static final Paint _calloutFill = Paint()
    ..color = Colors.white.withValues(alpha: 0.95);
  static final Paint _calloutBorder = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..color = _calloutRed;
  static final Paint _calloutLeader = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..color = _calloutRed;

  // ---- Callout text cache ----

  static const double _calloutMaxTextWidth = 150.0;

  /// Laid-out callout text by message. Messages come from a small fixed set
  /// (plus "Rep not counted. ..." variants), so this stays tiny; the cap is
  /// only a safety net.
  static final Map<String, TextPainter> _calloutText = {};
  static const int _calloutCacheLimit = 32;

  static TextPainter _calloutPainter(String message) {
    final cached = _calloutText[message];
    if (cached != null) return cached;
    if (_calloutText.length >= _calloutCacheLimit) {
      for (final painter in _calloutText.values) {
        painter.dispose();
      }
      _calloutText.clear();
    }
    final painter = TextPainter(
      text: TextSpan(
        text: message,
        style: const TextStyle(
          color: _calloutRed,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 4,
      ellipsis: '…',
    )..layout(maxWidth: _calloutMaxTextWidth);
    _calloutText[message] = painter;
    return painter;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (poses.isEmpty) return;

    final wrong = !isExerciseCorrect;
    final dotPaint = wrong ? _wrongDotPaint : _okDotPaint;
    final linePaint = wrong ? _wrongLinePaint : _okLinePaint;
    final hotLinePaint = _hotLinePaint;

    final iw = absoluteImageSize.width;
    final ih = absoluteImageSize.height;
    if (iw <= 0 || ih <= 0) return;
    final scale = cover
        ? max(size.width / iw, size.height / ih)
        : min(size.width / iw, size.height / ih);
    final drawW = iw * scale;
    final drawH = ih * scale;
    final offX = (size.width - drawW) / 2.0;
    final offY = (size.height - drawH) / 2.0;

    for (final pose in poses) {
      final Map<PoseLandmarkType, Offset> points = {};

      pose.landmarks.forEach((type, landmark) {
        if (landmark.likelihood > 0.5) {
          var x = offX + landmark.x * scale;
          final y = offY + landmark.y * scale;
          if (mirrorX) x = size.width - x;
          points[type] = Offset(x, y);
        }
      });

      for (final bone in _bones) {
        final p1 = points[bone[0]];
        final p2 = points[bone[1]];
        if (p1 == null || p2 == null) continue;
        final hot =
            wrong &&
            (flaggedLandmarks.contains(bone[0]) ||
                flaggedLandmarks.contains(bone[1]));
        canvas.drawLine(p1, p2, hot ? hotLinePaint : linePaint);
      }

      points.forEach((type, p) {
        if (!_faceLandmarks.contains(type)) {
          canvas.drawCircle(p, 5, dotPaint);
        }
      });

      if (wrong) {
        _drawFlaggedJoints(canvas, points);
        _drawCallouts(canvas, size, points);
      }
    }
  }

  void _drawFlaggedJoints(Canvas canvas, Map<PoseLandmarkType, Offset> points) {
    for (final type in flaggedLandmarks) {
      final p = points[type];
      if (p == null) continue;
      canvas.drawCircle(p, 18, _glowPaint);
      canvas.drawCircle(p, 11, _ringPaint);
      canvas.drawCircle(p, 6, _corePaint);
    }
  }

  Offset? _anchorPoint(FormIssue issue, Map<PoseLandmarkType, Offset> points) {
    final a = issue.anchor;
    if (a != null && points[a] != null) return points[a];
    for (final t in issue.landmarks) {
      final p = points[t];
      if (p != null) return p;
    }
    return null;
  }

  /// White bubble with a red border and red text, joined to the joint.
  void _drawCallouts(
    Canvas canvas,
    Size size,
    Map<PoseLandmarkType, Offset> points,
  ) {
    const pad = 8.0;

    var slot = 0;
    for (final issue in issues) {
      if (issue.code == FormIssueCode.notInFrame) continue;
      if (slot >= 2) break; // keep the screen readable
      final target = _anchorPoint(issue, points);
      if (target == null) continue;

      final tp = _calloutPainter(issue.message);

      final w = tp.width + pad * 2;
      final h = tp.height + pad * 2;

      final onLeftHalf = target.dx < size.width / 2;
      final left = (onLeftHalf ? target.dx + 28 : target.dx - 28 - w)
          .clamp(8.0, size.width - w - 8.0)
          .toDouble();
      final top = (slot == 0 ? target.dy - h - 24 : target.dy + 24)
          .clamp(8.0, size.height - h - 8.0)
          .toDouble();

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, w, h),
        const Radius.circular(8),
      );

      final from = Offset(onLeftHalf ? left : left + w, top + h / 2);
      canvas.drawLine(from, target, _calloutLeader);
      canvas.drawRRect(rect, _calloutFill);
      canvas.drawRRect(rect, _calloutBorder);
      tp.paint(canvas, Offset(left + pad, top + pad));

      slot++;
    }
  }

  /// The screen builds a new painter on every processed frame, with a NEW
  /// poses list from ML Kit, so live frames always repaint. Other rebuilds
  /// (countdown ticks, the flip button) reuse the same list and only repaint
  /// if something that is drawn actually changed.
  @override
  bool shouldRepaint(PosePainter oldDelegate) =>
      !identical(poses, oldDelegate.poses) ||
      absoluteImageSize != oldDelegate.absoluteImageSize ||
      rotation != oldDelegate.rotation ||
      isExerciseCorrect != oldDelegate.isExerciseCorrect ||
      cameraLensDirection != oldDelegate.cameraLensDirection ||
      mirrorX != oldDelegate.mirrorX ||
      cover != oldDelegate.cover ||
      !setEquals(flaggedLandmarks, oldDelegate.flaggedLandmarks) ||
      !listEquals(issues, oldDelegate.issues);
}