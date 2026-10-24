// Tests for lib/services/camera_rotation.dart: the frame rotation handed to
// ML Kit must follow how the device is held, or poses come out sideways in
// landscape (tablets).

import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    show InputImageRotation, InputImageRotationValue;
import 'package:rehabplus/services/camera_rotation.dart';

void main() {
  group('deviceRotationDegrees', () {
    test('maps each orientation to its clockwise turn from portrait', () {
      expect(deviceRotationDegrees(DeviceOrientation.portraitUp), 0);
      expect(deviceRotationDegrees(DeviceOrientation.landscapeLeft), 90);
      expect(deviceRotationDegrees(DeviceOrientation.portraitDown), 180);
      expect(deviceRotationDegrees(DeviceOrientation.landscapeRight), 270);
    });
  });

  group('mlKitRotation', () {
    test('portrait uses the sensor angle unchanged (old behaviour)', () {
      for (final front in [true, false]) {
        for (final sensor in [0, 90, 180, 270]) {
          expect(
            mlKitRotation(
              sensorOrientation: sensor,
              isFrontCamera: front,
              device: DeviceOrientation.portraitUp,
            ).rawValue,
            sensor,
            reason: 'front=$front sensor=$sensor',
          );
        }
      }
    });

    test('front camera adds the device turn (typical sensor 270)', () {
      InputImageRotation at(DeviceOrientation d) =>
          mlKitRotation(sensorOrientation: 270, isFrontCamera: true, device: d);
      expect(
        at(DeviceOrientation.landscapeLeft),
        InputImageRotation.rotation0deg,
      );
      expect(
        at(DeviceOrientation.portraitDown),
        InputImageRotation.rotation90deg,
      );
      expect(
        at(DeviceOrientation.landscapeRight),
        InputImageRotation.rotation180deg,
      );
    });

    test('back camera subtracts the device turn (typical sensor 90)', () {
      InputImageRotation at(DeviceOrientation d) =>
          mlKitRotation(sensorOrientation: 90, isFrontCamera: false, device: d);
      expect(
        at(DeviceOrientation.landscapeLeft),
        InputImageRotation.rotation0deg,
      );
      expect(
        at(DeviceOrientation.portraitDown),
        InputImageRotation.rotation270deg,
      );
      expect(
        at(DeviceOrientation.landscapeRight),
        InputImageRotation.rotation180deg,
      );
    });

    test('landscape-native tablet sensor (0) still gets a valid rotation', () {
      expect(
        mlKitRotation(
          sensorOrientation: 0,
          isFrontCamera: false,
          device: DeviceOrientation.landscapeLeft,
        ),
        InputImageRotation.rotation270deg,
      );
    });
  });
}
