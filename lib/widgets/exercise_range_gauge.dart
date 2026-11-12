// lib/widgets/exercise_range_gauge.dart
//
// Small "how far through the movement" gauge for the exercise screen's
// bottom card, replacing the bare angle number for rep exercises. Patients
// don't know what "112 deg" means; a bar from Rest to Target with a moving
// marker shows how far they still have to go. The mapping is the pure
// RangeGaugeScale in lib/services/exercise_feedback.dart.

import 'package:flutter/material.dart';

import '../services/exercise_feedback.dart';

class ExerciseRangeGauge extends StatelessWidget {
  const ExerciseRangeGauge({
    super.key,
    required this.angle,
    required this.restAngle,
    required this.targetAngle,
    required this.isCorrect,
  });

  /// Current joint angle, or null before the first measurement (then no
  /// marker is drawn instead of a misleading one at either end).
  final double? angle;

  /// The screen's rest angle (it overrides the config for some exercises,
  /// e.g. the curl rests at 170 deg) and the exercise's target angle.
  final double restAngle;
  final double targetAngle;

  /// False while the form is wrong: the marker turns red like the skeleton.
  final bool isCorrect;

  /// Lets tests find the marker and check where it is.
  static const Key markerKey = ValueKey('exerciseRangeGaugeMarker');

  static const double _trackHeight = 8;
  static const double _markerSize = 16;
  static const BorderRadius _trackRadius = BorderRadius.all(
    Radius.circular(4),
  );

  // This widget is rebuilt on every processed camera frame, so everything
  // that doesn't depend on the angle is built once here rather than per
  // build.
  static const BoxDecoration _trackDecoration = BoxDecoration(
    color: Colors.white24,
    borderRadius: _trackRadius,
  );
  static final BoxDecoration _zoneDecoration = BoxDecoration(
    color: Colors.tealAccent.withValues(alpha: 0.55),
    borderRadius: _trackRadius,
  );
  static final Border _markerBorder = Border.all(
    color: Colors.black54,
    width: 2,
  );
  static final BoxDecoration _markerWrong = _marker(Colors.redAccent);
  static final BoxDecoration _markerInTarget = _marker(Colors.greenAccent);
  static final BoxDecoration _markerMoving = _marker(Colors.white);

  static BoxDecoration _marker(Color color) => BoxDecoration(
    color: color,
    shape: BoxShape.circle,
    border: _markerBorder,
  );

  @override
  Widget build(BuildContext context) {
    final scale = RangeGaugeScale(
      restAngle: restAngle,
      targetAngle: targetAngle,
    );
    final current = angle;
    final position = current == null ? null : scale.position(current);
    final inTarget = current != null && scale.isInTarget(current);
    final markerDecoration = !isCorrect
        ? _markerWrong
        : inTarget
        ? _markerInTarget
        : _markerMoving;

    return Semantics(
      label: position == null
          ? 'Range: waiting for a reading'
          : 'Range: ${(position / scale.targetStart * 100).clamp(0, 100).round()} '
                'percent of the way to the target',
      excludeSemantics: true,
      // The marker moves on every processed frame; keep its repaint from
      // spreading to the rest of the card.
      child: RepaintBoundary(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Flexible(
                  child: Text(
                    'RANGE',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                if (current != null) ...[
                  const SizedBox(width: 6),
                  // The number stays, small, for therapists reviewing a
                  // screen recording.
                  Text(
                    '${current.round()}°',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: _markerSize,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final zoneLeft = width * scale.targetStart;
                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: _trackHeight,
                        decoration: _trackDecoration,
                      ),
                      Positioned(
                        left: zoneLeft,
                        right: 0,
                        child: Container(
                          height: _trackHeight,
                          decoration: _zoneDecoration,
                        ),
                      ),
                      if (position != null)
                        Positioned(
                          left: position * width - _markerSize / 2,
                          child: Container(
                            key: markerKey,
                            width: _markerSize,
                            height: _markerSize,
                            decoration: markerDecoration,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Rest',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
                Flexible(
                  child: Text(
                    'Target',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.tealAccent, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
