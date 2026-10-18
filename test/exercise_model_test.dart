import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/models/exercise_model.dart';

void main() {
  test('every exercise says where to stand, matching its camera view', () {
    for (final e in availableExercises) {
      final tip = e.setupTip.toLowerCase();
      expect(tip, contains('camera'), reason: '${e.title}: "${e.setupTip}"');
      switch (e.cameraView) {
        case CameraView.front:
          expect(tip, contains('facing'), reason: e.title);
          expect(tip, isNot(contains('side-on')), reason: e.title);
        case CameraView.side:
          expect(tip, contains('side-on'), reason: e.title);
        case CameraView.either:
          expect(tip, allOf(contains('facing'), contains('side-on')));
      }
    }
  });

  test('every exercise type has exactly one catalog entry', () {
    for (final type in ExerciseType.values) {
      expect(
        availableExercises.where((e) => e.type == type),
        hasLength(1),
        reason: '$type',
      );
    }
  });

  test('copyWith keeps the camera set-up', () {
    final e = availableExercises.first.copyWith(targetReps: 3);
    expect(e.cameraView, availableExercises.first.cameraView);
    expect(e.setupTip, availableExercises.first.setupTip);
  });
}
