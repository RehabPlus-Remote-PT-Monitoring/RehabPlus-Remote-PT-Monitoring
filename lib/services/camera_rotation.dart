// lib/services/camera_rotation.dart
//
// Which way up a camera frame is, for ML Kit pose detection.
//
// Why this exists
// ---------------
// The camera sensor is glued into the device at a fixed angle
// (`CameraDescription.sensorOrientation`, usually 90 or 270 on phones). Its
// frames arrive in that sensor's own orientation, so ML Kit has to be told
// how far to rotate each frame to make the person upright. The app used to
// pass the sensor angle alone, which is only right while the device is held
// in portrait. Turned sideways (how tablets are usually propped up), ML Kit
// received a frame lying on its side: the skeleton was misplaced and reps
// stopped counting.
//
// The fix is Google's documented formula for Android: add (front camera) or
// subtract (back camera) how far the device is turned from portrait.
// https://developers.google.com/ml-kit/vision/pose-detection/android
//
// Pure function, unit-tested in test/camera_rotation_test.dart.

import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    show InputImageRotation, InputImageRotationValue;

/// How many degrees the device is turned clockwise from portrait.
int deviceRotationDegrees(DeviceOrientation orientation) =>
    switch (orientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };

/// The rotation to hand ML Kit for a frame from a camera mounted at
/// [sensorOrientation] degrees, while the device is held at [device].
///
/// The front camera's image is mirrored, so the device turn is added to the
/// sensor angle; for the back camera it is subtracted.
InputImageRotation mlKitRotation({
  required int sensorOrientation,
  required bool isFrontCamera,
  required DeviceOrientation device,
}) {
  final turn = deviceRotationDegrees(device);
  final degrees = isFrontCamera
      ? (sensorOrientation + turn) % 360
      : (sensorOrientation - turn + 360) % 360;
  return InputImageRotationValue.fromRawValue(degrees) ??
      InputImageRotation.rotation0deg;
}
