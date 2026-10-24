import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
// `show`: intl also exports a TextDirection that clashes with Flutter's.
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../core/app_palette.dart';
import '../core/responsive.dart';
import '../models/exercise_model.dart';
import '../models/session.dart';
import '../screens/pose_detector_screen.dart';
import '../services/app_provider.dart';
import '../services/progress_stats.dart';
import 'ios_list.dart';

const Color _primaryTeal = Color(0xFF23A8AA);

/// Bottom sheet: today's prescribed exercises with a tick for each one done,
/// plus weekly progress. Exercises not scheduled today are listed below.
class TodayChecklistSheet extends StatelessWidget {
  final List<ExerciseConfig> exercises;

  const TodayChecklistSheet({super.key, required this.exercises});

  static Future<void> show(BuildContext context, List<ExerciseConfig> exercises) {
    // iOS sheet: grouped grey background with the rows in a white group,
    // the theme's drag handle, and phone width centred on tablets.
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.background,
      constraints: const BoxConstraints(maxWidth: kReadableMaxWidth),
      builder: (_) => TodayChecklistSheet(exercises: exercises),
    );
  }

  /// How many exercises due today are not done yet (for the button badge).
  /// One pass over [sessions] however many exercises there are.
  static int remainingToday(
    List<ExerciseConfig> exercises,
    List<ExerciseSession> sessions,
    DateTime now,
  ) {
    if (exercises.isEmpty) return 0;
    final activity = ProgressStats.activity(sessions, now);
    return exercises
        .where((e) => e.prescription?.isDueOn(now) ?? true)
        .where((e) => !activity.isDoneToday(e.type.name))
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<AppProvider>().sessionHistory;
    final now = DateTime.now();
    // "Done today" and "this week" for every exercise in a single pass,
    // instead of re-scanning the history two or three times per row.
    final activity = ProgressStats.activity(sessions, now);
    final today = exercises
        .where((e) => e.prescription?.isDueOn(now) ?? true)
        .toList();
    final todaySet = today.toSet();
    final other = exercises.where((e) => !todaySet.contains(e)).toList();
    final done = today.where((e) => activity.isDoneToday(e.type.name)).length;
    final palette = context.palette;

    /// One exercise: tick circle, name (struck through when done), reps
    /// and this week's count, and a Start button until it's done.
    Widget row(ExerciseConfig e, {required bool dueToday}) {
      final isDone = activity.isDoneToday(e.type.name);
      final week = activity.weekCount(e.type.name);
      final goal = e.prescription?.frequencyPerWeek;
      return Container(
        color: palette.surface,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(
              isDone
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              color: isDone
                  ? _primaryTeal
                  : dueToday
                  ? palette.textMuted
                  : palette.textFaint,
              size: 26,
              semanticLabel: isDone ? 'Done' : 'Not done',
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    style: TextStyle(
                      fontSize: 17,
                      color: dueToday ? palette.textPrimary : palette.textMuted,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${e.repsText}  ·  $week${goal != null ? '/$goal' : ''} this week',
                    style: TextStyle(fontSize: 13, color: palette.textMuted),
                  ),
                ],
              ),
            ),
            if (!isDone)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PoseDetectorScreen(selectedExercise: e),
                    ),
                  );
                },
                child: const Text('Start'),
              ),
          ],
        ),
      );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          // The drag handle comes from the theme (showDragHandle).
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            Text(
              DateFormat('EEEE, d MMMM').format(now).toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Today's Plan",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            if (exercises.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No exercises assigned yet. Your therapist will set up your plan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.textSecondary),
                ),
              )
            else ...[
              if (today.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: done / today.length,
                    minHeight: 8,
                    color: _primaryTeal,
                    backgroundColor: _primaryTeal.withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  done == today.length
                      ? 'All done for today. Nice work!'
                      : '$done of ${today.length} done today',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
                IosSection(
                  hasLeading: true,
                  children: [for (final e in today) row(e, dueToday: true)],
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Nothing scheduled today. Rest up!',
                    style: TextStyle(color: palette.textSecondary),
                  ),
                ),
              if (other.isNotEmpty)
                IosSection(
                  header: 'Not scheduled today',
                  children: [for (final e in other) row(e, dueToday: false)],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
