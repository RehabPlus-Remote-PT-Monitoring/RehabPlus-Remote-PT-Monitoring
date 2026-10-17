import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/exercise_model.dart';
import '../models/session.dart';
import '../screens/pose_detector_screen.dart';
import '../services/app_provider.dart';
import '../services/progress_stats.dart';

const Color _primaryTeal = Color(0xFF23A8AA);

/// Bottom sheet: today's prescribed exercises with a tick for each one done,
/// plus weekly progress. Exercises not scheduled today are listed below.
class TodayChecklistSheet extends StatelessWidget {
  final List<ExerciseConfig> exercises;

  const TodayChecklistSheet({super.key, required this.exercises});

  static Future<void> show(BuildContext context, List<ExerciseConfig> exercises) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => TodayChecklistSheet(exercises: exercises),
    );
  }

  /// How many exercises due today are not done yet (for the button badge).
  static int remainingToday(
    List<ExerciseConfig> exercises,
    List<ExerciseSession> sessions,
    DateTime now,
  ) => exercises
      .where((e) => e.prescription?.isDueOn(now) ?? true)
      .where((e) => !ProgressStats.doneOn(sessions, e.type.name, now))
      .length;

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<AppProvider>().sessionHistory;
    final now = DateTime.now();
    final today = exercises
        .where((e) => e.prescription?.isDueOn(now) ?? true)
        .toList();
    final other = exercises.where((e) => !today.contains(e)).toList();
    final done = today
        .where((e) => ProgressStats.doneOn(sessions, e.type.name, now))
        .length;

    Widget row(ExerciseConfig e, {required bool dueToday}) {
      final isDone = ProgressStats.doneOn(sessions, e.type.name, now);
      final week = ProgressStats.completedThisWeek(sessions, e.type.name, now);
      final goal = e.prescription?.frequencyPerWeek;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          color: isDone
              ? _primaryTeal
              : dueToday
              ? Colors.black38
              : Colors.black12,
          size: 28,
        ),
        title: Text(
          e.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: dueToday ? Colors.black87 : Colors.black45,
            decoration: isDone ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          '${e.repsText}  ·  $week${goal != null ? '/$goal' : ''} this week',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: isDone
            ? null
            : TextButton(
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
      );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              DateFormat('EEEE, d MMMM').format(now).toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Today's Plan",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (exercises.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No exercises assigned yet. Your therapist will set up your plan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
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
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                ...today.map((e) => row(e, dueToday: true)),
              ] else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Nothing scheduled today. Rest up!',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              if (other.isNotEmpty) ...[
                const Divider(height: 32),
                const Text(
                  'Not scheduled today',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                ...other.map((e) => row(e, dueToday: false)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
