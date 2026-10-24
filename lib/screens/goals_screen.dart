import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
// `show`: the full intl library also exports a TextDirection that clashes
// with Flutter's.
import 'package:intl/intl.dart' show DateFormat;

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../models/therapy_goal.dart';
import '../services/goal_service.dart';
import '../core/responsive.dart';
import '../widgets/info_content_unavailable.dart';
import '../widgets/ios_page.dart';

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
    return IosPage(
      title: 'My Goals',
      previousPageTitle: 'Profile',
      slivers: [
        StreamBuilder<List<TherapyGoal>>(
          stream: _goals,
          builder: (context, snap) {
            if (snap.hasError) {
              return _message(
                icon: CupertinoIcons.wifi_slash,
                title: 'Could not load your goals',
                body: 'Check your internet connection and open this page again.',
              );
            }
            if (!snap.hasData) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator.adaptive()),
              );
            }
            final goals = snap.data!;
            if (goals.isEmpty) {
              return _message(
                icon: CupertinoIcons.flag,
                title: 'No goals yet',
                body: 'Your therapist will add goals for your recovery. '
                    'They will show up here.',
              );
            }
            return _goalList(goals);
          },
        ),
      ],
    );
  }

  /// The summary line, one card per goal and a footnote, in the readable
  /// column (a sliver: this sits directly in the page's scroll view).
  Widget _goalList(List<TherapyGoal> goals) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final active = goals.where((g) => g.status == GoalStatus.active).length;
    final achieved = goals.where((g) => g.status == GoalStatus.achieved).length;
    return SliverPadding(
      padding: readablePadding(context, const EdgeInsets.fromLTRB(16, 12, 16, 32)),
      sliver: SliverList.list(
        children: [
          // Like an iOS section header: small grey text just above the cards.
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '$active in progress · $achieved achieved',
              style: textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ),
          for (final goal in goals) ...[
            _GoalCard(goal: goal),
            const SizedBox(height: 12),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Goals are set by your therapist. Message them if you want to '
              'change one.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  /// An empty or error state, centred in the space under the title.
  Widget _message({required IconData icon, required String title, required String body}) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: InfoContentUnavailable(icon: icon, title: title, body: body),
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
    final textTheme = Theme.of(context).textTheme;
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
        // iOS card: flat surface on the grouped background, no shadow.
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  goal.status == GoalStatus.achieved
                      ? CupertinoIcons.rosette
                      : CupertinoIcons.flag_fill,
                  color: accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    goal.title,
                    style: textTheme.titleMedium?.copyWith(
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
                style: textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
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
                      minHeight: 6,
                      backgroundColor: palette.surfaceMuted,
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${goal.progress}%',
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
            if (_dateLine() case final line?) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(CupertinoIcons.calendar, size: 15, color: palette.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    line,
                    style: textTheme.bodySmall?.copyWith(color: palette.textMuted),
                  ),
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
