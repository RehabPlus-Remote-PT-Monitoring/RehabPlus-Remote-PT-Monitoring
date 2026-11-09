// lib/widgets/exercise_standing_guide.dart
//
// Faint "stand here" person outline, centred on the camera preview until
// the camera finds the patient's body (see showStandingGuide in
// lib/services/exercise_feedback.dart). Drawn with a CustomPainter, no image
// assets. The outline is the same for front and side camera views; only
// the caption changes (standingGuideCaption).

import 'package:flutter/material.dart';

class ExerciseStandingGuide extends StatelessWidget {
  const ExerciseStandingGuide({super.key, this.caption});

  /// Shown under the outline; null during the countdown, which already
  /// shows its own "Get into position" text in the middle of the screen.
  final String? caption;

  /// Width / height of the drawn figure.
  static const double _aspect = 0.42;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Leave room for the banners above and the bottom card below.
          final maxFigureHeight = constraints.maxHeight * 0.62;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxFigureHeight),
                    child: const AspectRatio(
                      aspectRatio: _aspect,
                      child: RepaintBoundary(
                        child: CustomPaint(painter: _StandingGuidePainter()),
                      ),
                    ),
                  ),
                ),
                if (caption != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
                    child: Text(
                      caption!,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        shadows: [Shadow(blurRadius: 8)],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A simple standing figure: head, shoulders, torso, arms by the sides and
/// legs, all as soft rounded strokes. Static, so it never repaints.
class _StandingGuidePainter extends CustomPainter {
  const _StandingGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.035).clamp(2.0, 5.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    Offset at(double fx, double fy) => Offset(w * fx, h * fy);

    // Head.
    final headCentre = at(0.5, 0.085);
    final headRadius = h * 0.065;
    canvas.drawCircle(headCentre, headRadius, fill);
    canvas.drawCircle(headCentre, headRadius, stroke);

    // Torso: shoulders down to the hips.
    final torso = Path()
      ..moveTo(w * 0.22, h * 0.2)
      ..lineTo(w * 0.78, h * 0.2)
      ..lineTo(w * 0.68, h * 0.53)
      ..lineTo(w * 0.32, h * 0.53)
      ..close();
    canvas.drawPath(torso, fill);
    canvas.drawPath(torso, stroke);

    // Neck.
    canvas.drawLine(at(0.5, 0.15), at(0.5, 0.2), stroke);

    // Arms hanging by the sides.
    final arms = Path()
      ..moveTo(w * 0.22, h * 0.2)
      ..quadraticBezierTo(w * 0.08, h * 0.33, w * 0.1, h * 0.52)
      ..moveTo(w * 0.78, h * 0.2)
      ..quadraticBezierTo(w * 0.92, h * 0.33, w * 0.9, h * 0.52);
    canvas.drawPath(arms, stroke);

    // Legs, feet slightly apart.
    canvas.drawLine(at(0.38, 0.53), at(0.34, 0.97), stroke);
    canvas.drawLine(at(0.62, 0.53), at(0.66, 0.97), stroke);

    // Floor line to show where the feet go.
    final floor = Paint()
      ..color = Colors.tealAccent.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(at(0.15, 0.99), at(0.85, 0.99), floor);
  }

  @override
  bool shouldRepaint(_StandingGuidePainter oldDelegate) => false;
}
