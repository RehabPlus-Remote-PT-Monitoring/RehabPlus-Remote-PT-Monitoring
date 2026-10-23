import 'package:flutter/material.dart';
// `show`: the full intl library also exports a TextDirection that clashes
// with Flutter's.
import 'package:intl/intl.dart' show DateFormat;

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../models/therapy_goal.dart';
import '../services/goal_service.dart';

/// Profile > My Goals: the rehab goals the therapist set on the clinic
/// dashboard, with their progress. Read-only; the patient is told to ask
/// their therapist to change them.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key, this.goals});

  /// For tests: a ready-made stream instead of [GoalService.watch].
  final Stream<List<TherapyGoal>>? goals;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  static const String _tag = 'Goals';

  late final Stream<List<TherapyGoal>> _goals;

  @override
  void initState() {
    super.initState();
    DiagnosticLogger.I.info(_tag, 'Screen opened');
    _goals = widget.goals ?? GoalService().watch();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: StreamBuilder<List<TherapyGoal>>(
              stream: _goals,
              builder: (context, snap) {
                if (snap.hasError) {
                  return _message(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could not load your goals',
                    body: 'Check your internet connection and open this page again.',
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final goals = snap.data!;
                if (goals.isEmpty) {
                  return _message(
                    icon: Icons.flag_outlined,
                    title: 'No goals yet',
                    body: 'Your therapist will add goals for your recovery. '
                        'They will show up here.',
                  );
                }
                return _goalList(goals);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _goalList(List<TherapyGoal> goals) {
    final active = goals.where((g) => g.status == GoalStatus.active).length;
    final achieved = goals.where((g) => g.status == GoalStatus.achieved).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        Text(
          '$active in progress · $achieved achieved',
          style: TextStyle(fontSize: 13, color: context.palette.textMuted),
        ),
        const SizedBox(height: 12),
        for (final goal in goals) ...[
          _GoalCard(goal: goal),
          const SizedBox(height: 12),
        ],
        Text(
          'Goals are set by your therapist. Message them if you want to '
          'change one.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: context.palette.textMuted),
        ),
      ],
    );
  }

  Widget _message({required IconData icon, required String title, required String body}) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppPalette.teal.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AppPalette.teal),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: AppPalette.headerGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 24),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.flag_outlined, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'My Goals',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal});

  final TherapyGoal goal;

  static const Color _achievedGreen = Color(0xFF2E7D32);
  static const Color _overdueOrange = Color(0xFFD84315);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final overdue = goal.isOverdue(DateTime.now());
    final stopped = goal.status == GoalStatus.discontinued;
    final accent = switch (goal.status) {
      GoalStatus.achieved => _achievedGreen,
      GoalStatus.discontinued => palette.textMuted,
      GoalStatus.active => overdue ? _overdueOrange : AppPalette.teal,
    };

    return Opacity(
      opacity: stopped ? 0.7 : 1,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: palette.shadow.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  goal.status == GoalStatus.achieved
                      ? Icons.emoji_events_rounded
                      : Icons.flag_rounded,
                  color: accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    goal.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(label: overdue ? 'Past target' : goal.status.label, color: accent),
              ],
            ),
            if (goal.details.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                goal.details.trim(),
                style: TextStyle(fontSize: 13, color: palette.textSecondary, height: 1.35),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: goal.progress / 100,
                      minHeight: 8,
                      backgroundColor: palette.surfaceMuted,
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${goal.progress}%',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.textPrimary),
                ),
              ],
            ),
            if (_dateLine() case final line?) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.event_outlined, size: 15, color: palette.textMuted),
                  const SizedBox(width: 6),
                  Text(line, style: TextStyle(fontSize: 12, color: palette.textMuted)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "Achieved 3 Oct 2026", "Target: 30 Nov 2026", or null.
  String? _dateLine() {
    final format = DateFormat('d MMM y');
    if (goal.status == GoalStatus.achieved && goal.achievedAt != null) {
      return 'Achieved ${format.format(goal.achievedAt!)}';
    }
    if (goal.targetDate != null) {
      return 'Target: ${format.format(goal.targetDate!)}';
    }
    return null;
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
