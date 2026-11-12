// Regression tests for bugs fixed in the camera/pose pipeline review.

import 'dart:ui' as ui;

import 'package:camera/camera.dart' show CameraLensDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:rehabplus/services/cast_service.dart';
import 'package:rehabplus/services/form_checker.dart';
import 'package:rehabplus/widgets/pose_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PosePainter callouts', () {
    final pose = Pose(
      landmarks: {
        for (final type in PoseLandmarkType.values)
          type: PoseLandmark(type: type, x: 40, y: 30, z: 0, likelihood: 0.9),
      },
    );
    const issue = FormIssue(
      code: FormIssueCode.kneeBent,
      message: 'Keep your knee straight.',
      landmarks: {PoseLandmarkType.leftKnee},
      anchor: PoseLandmarkType.leftKnee,
    );

    void paintAt(Size canvasSize) {
      final painter = PosePainter(
        [pose],
        const Size(80, 60),
        InputImageRotation.rotation0deg,
        false, // wrong form, so callouts are drawn
        CameraLensDirection.front,
        flaggedLandmarks: const {PoseLandmarkType.leftKnee},
        issues: const [issue],
      );
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), canvasSize);
      recorder.endRecording().dispose();
    }

    test('do not throw on a canvas smaller than the bubble', () {
      // Before the fix clamp(8, size - bubble - 8) had its upper limit
      // below its lower limit here and threw an ArgumentError.
      expect(() => paintAt(const Size(60, 40)), returnsNormally);
    });

    test('still paint on a normal phone-sized canvas', () {
      expect(() => paintAt(const Size(400, 800)), returnsNormally);
    });
  });

  group('CastService never throws', () {
    const channel = MethodChannel(CastService.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('openCastSettings: a non-String answer returns false', () async {
      // invokeMethod<String> would throw a TypeError, which is not an
      // Exception and used to escape to the button's onPressed.
      messenger.setMockMethodCallHandler(channel, (_) async => 42);
      expect(await CastService(isAndroid: true).openCastSettings(), isFalse);
    });

    test('isCasting: a non-bool answer returns false', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => 'yes');
      expect(await CastService(isAndroid: true).isCasting(), isFalse);
    });
  });
}
