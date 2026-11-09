// lib/widgets/exercise_session_summary.dart
//
// End-of-session summary for the completion dialog: accuracy (counted of
// attempted) and one dot per attempt, green = counted, red = not counted.
// A Wrap of dots instead of an fl_chart chart: the information is a simple
// sequence, it costs nothing to lay out, and it wraps on its own when a
// session has many attempts.

import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../services/exercise_feedback.dart';

class ExerciseSessionSummary extends StatelessWidget {
  const ExerciseSessionSummary({
    super.key,
    required this.scores,
    required this.unit,
  });

  /// The screen's per-attempt scores in order (1.0 counted, 0.0 not).
  final List<double> scores;

  /// "reps" or "holds".
  final String unit;

  static const Color countedColor = Color(0xFF43A047);
  static const Color missedColor = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    final accuracy = SessionAccuracy.fromScores(scores);
    final percent = accuracy.percent;
    final palette = context.palette;

    if (percent == null) {
      return Text(
        'No $unit were attempted.',
        textAlign: TextAlign.center,
        style: TextStyle(color: palette.textSecondary, fontSize: 13),
      );
    }

    final percentColor = percent >= 80
        ? countedColor
        : percent >= 50
        ? Colors.orange
        : missedColor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$percent%',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: percentColor,
          ),
        ),
        Text(
          'Accuracy: ${accuracy.counted} of ${accuracy.attempts} $unit counted',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Semantics(
          label:
              'Attempts in order: ${[for (final s in scores) s >= 0.5 ? 'counted' : 'not counted'].join(', ')}',
          excludeSemantics: true,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final s in scores) ExerciseAttemptDot(counted: s >= 0.5),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 2,
          children: [
            _LegendItem(color: countedColor, label: 'Counted'),
            _LegendItem(color: missedColor, label: 'Not counted'),
          ],
        ),
      ],
    );
  }
}

/// One attempt in the summary row: green if it was counted, red if not.
class ExerciseAttemptDot extends StatelessWidget {
  const ExerciseAttemptDot({super.key, required this.counted});

  final bool counted;

  Color get color => counted
      ? ExerciseSessionSummary.countedColor
      : ExerciseSessionSummary.missedColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: context.palette.textMuted),
        ),
      ],
    );
  }
}
