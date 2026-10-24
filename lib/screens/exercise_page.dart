// lib/screens/exercise_page.dart
import 'package:flutter/material.dart';
// `show`: intl also exports a TextDirection that clashes with Flutter's.
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../core/app_palette.dart';
import '../models/exercise_model.dart';
import '../services/app_provider.dart';
import '../services/prescription_service.dart';
import '../services/progress_stats.dart';
import '../widgets/today_checklist_sheet.dart';
import '../widgets/unread_badge.dart';
import '../core/responsive.dart';
import 'notification_page.dart';
import 'pose_detector_screen.dart';

class ExercisePage extends StatefulWidget {
  const ExercisePage({super.key});

  @override
  State<ExercisePage> createState() => _ExercisePageState();
}

class _ExercisePageState extends State<ExercisePage> {
  static const Color primaryTeal = Color(0xFF23A8AA);
  static const Color lightTealBg = Color(0xFFE8F7F7);

  /// Pale teal for the background circles and count chip. The light pastel
  /// glares on a dark page, so dark mode uses a faint teal tint instead.
  Color _tealTint(BuildContext context) => context.isDarkMode
      ? primaryTeal.withValues(alpha: 0.14)
      : lightTealBg;

  late Future<List<ExerciseConfig>> _exercisesFuture;

  @override
  void initState() {
    super.initState();
    _exercisesFuture = _loadAssignedExercises();
  }

  final _prescriptions = PrescriptionService();

  /// Last successfully loaded plan, for the checklist sheet.
  List<ExerciseConfig> _assigned = const [];

  Future<List<ExerciseConfig>> _loadAssignedExercises() async {
    final list = await _prescriptions.loadAssignedExercises();
    if (mounted) setState(() => _assigned = list);
    return list;
  }

  Future<void> _refresh() async {
    setState(() => _exercisesFuture = _loadAssignedExercises());
    await _exercisesFuture;
  }

  // How close the patient is to the prescribed sessions per week for this
  // exercise, based on sessions saved in the last 7 days (rolling).
  // [lastWeek] comes from ProgressStats.countByExerciseSince, computed once
  // per list build, so N cards cost one pass over the history, not N.
  double _weeklyProgress(Map<String, int> lastWeek, ExerciseConfig config) {
    final count = lastWeek[config.type.name] ?? 0;
    final weeklyGoal = config.prescription?.frequencyPerWeek ?? 3;
    return weeklyGoal > 0 ? (count / weeklyGoal).clamp(0.0, 1.0) : 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      // Light: white page like before. Dark: the darker page colour so the
      // cards (palette.surface) still stand out, as shadows barely show.
      backgroundColor:
          context.isDarkMode ? palette.background : palette.surface,
      // No bottomNavigationBar here: DashboardScreen already has one.
      body: Stack(
        children: [
          // Background decorative teal circles
          Positioned(
            top: -100,
            left: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: _tealTint(context),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            right: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                color: _tealTint(context),
                shape: BoxShape.circle,
              ),
            ),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                // Top Bar Header
                ReadableWidth(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Rehab',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: primaryTeal,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            UnreadNotifications(
                              builder: (context, unread) => _buildTopCircleButton(
                                Icons.notifications_rounded,
                                tooltip: 'Notifications',
                                hasBadge: unread > 0,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const NotificationPage(),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Consumer<AppProvider>(
                              builder: (context, provider, _) =>
                                  _buildTopCircleButton(
                                    Icons.assignment_turned_in_rounded,
                                    tooltip: "Today's plan",
                                    // Dot while something due today is not done.
                                    hasBadge:
                                        TodayChecklistSheet.remainingToday(
                                          _assigned,
                                          provider.sessionHistory,
                                          DateTime.now(),
                                        ) >
                                        0,
                                    onTap: () => TodayChecklistSheet.show(
                                      context,
                                      _assigned,
                                    ),
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Date & Subtitle
                ReadableWidth(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat(
                            'EEEE, d MMMM',
                          ).format(DateTime.now()).toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: palette.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Select an\nExercise',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            height: 1.15,
                            color: palette.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Exercise list, driven by the patient's assigned plan.
                Expanded(
                  child: FutureBuilder<List<ExerciseConfig>>(
                    future: _exercisesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: primaryTeal),
                        );
                      }

                      if (snapshot.hasError) {
                        return _buildMessage(
                          icon: Icons.wifi_off_rounded,
                          text: "Couldn't load your plan. Check your connection and try again.",
                          onRetry: _refresh,
                        );
                      }

                      final exercises = snapshot.data ?? const [];
                      // Rest of the catalog, minus anything already in
                      // the plan so no exercise appears twice.
                      final assignedTypes = exercises.map((e) => e.type).toSet();
                      final others = availableExercises
                          .where((c) => !assignedTypes.contains(c.type))
                          .toList();

                      return RefreshIndicator(
                        color: primaryTeal,
                        onRefresh: _refresh,
                        child: Consumer<AppProvider>(
                          builder: (context, provider, _) {
                            final lastWeek =
                                ProgressStats.countByExerciseSince(
                                  provider.sessionHistory,
                                  DateTime.now().subtract(
                                    const Duration(days: 7),
                                  ),
                                );
                            return ListView(
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            padding: readablePadding(
                              context,
                              const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                            ),
                            children: [
                              _buildSectionHeader('Your Plan', exercises.length),
                              if (exercises.isEmpty)
                                _buildEmptyPlanNote()
                              else
                                for (var i = 0; i < exercises.length; i++)
                                  AnimatedExerciseCard(
                                    // Keys keep each card's animation state
                                    // with its exercise when a refresh
                                    // reorders the plan.
                                    key: ValueKey(
                                      'plan-${exercises[i].prescription?.id ?? 'i$i'}',
                                    ),
                                    index: i,
                                    config: exercises[i],
                                    progress: _weeklyProgress(lastWeek, exercises[i]),
                                  ),
                              if (others.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _buildSectionHeader('All Exercises', others.length),
                                for (var i = 0; i < others.length; i++)
                                  AnimatedExerciseCard(
                                    key: ValueKey('catalog-${others[i].type.name}'),
                                    index: exercises.length + i,
                                    config: others[i],
                                  ),
                              ],
                            ],
                          );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.palette.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _tealTint(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: primaryTeal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPlanNote() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _tealTint(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_note_rounded, color: primaryTeal),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No therapy plan assigned yet. Check back once your therapist sets one up.',
              style: TextStyle(
                fontSize: 13,
                color: context.palette.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String text,
    required VoidCallback onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: _tealTint(context), shape: BoxShape.circle),
              child: Icon(icon, size: 36, color: primaryTeal),
            ),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: context.palette.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: const Text('Refresh', style: TextStyle(color: primaryTeal, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopCircleButton(
    IconData icon, {
    required String tooltip,
    required bool hasBadge,
    required VoidCallback onTap,
  }) {
    return Stack(
      children: [
        Tooltip(
          message: tooltip,
          child: Material(
            color: primaryTeal.withValues(alpha: 0.85),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 38,
                height: 38,
                child: Icon(icon, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),
        if (hasBadge)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class AnimatedExerciseCard extends StatefulWidget {
  final int index;
  final ExerciseConfig config;

  /// 0.0–1.0 progress toward the prescription's weekly goal. Null for
  /// catalog exercises that aren't in the patient's plan (no bar shown).
  final double? progress;

  const AnimatedExerciseCard({
    super.key,
    required this.index,
    required this.config,
    this.progress,
  });

  @override
  State<AnimatedExerciseCard> createState() => _AnimatedExerciseCardState();
}

class _AnimatedExerciseCardState extends State<AnimatedExerciseCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  double _scale = 1.0;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    // Capped so cards far down the list don't wait seconds to appear.
    Future.delayed(Duration(milliseconds: widget.index.clamp(0, 5) * 120), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Icon + accent color per exercise category. Hold exercises always get
  // the timer icon regardless of category, since "how long" matters more
  // than "which body part" at a glance.
  ({Color accent, IconData icon}) get _visuals {
    if (widget.config.isHold) {
      return (accent: const Color(0xFFE91E63), icon: Icons.timer_rounded);
    }
    switch (widget.config.category) {
      case 'MCL Recovery':
        return (accent: const Color(0xFF00ACC1), icon: Icons.swap_vert_rounded);
      case 'Lower Body':
        return (accent: const Color(0xFFFF7043), icon: Icons.directions_walk_rounded);
      case 'Core & Hips':
        return (accent: const Color(0xFF7E57C2), icon: Icons.self_improvement_rounded);
      case 'Arm Rehabilitation':
        return (accent: const Color(0xFF42A5F5), icon: Icons.fitness_center_rounded);
      default:
        return (accent: const Color(0xFF23A8AA), icon: Icons.accessibility_new_rounded);
    }
  }

  // Pastel chip backgrounds in light mode; in dark mode a translucent tint
  // of the label colour, since the pastels glare on a dark card.
  ({Color bg, Color fg}) get _difficultyColors {
    final colors = _lightDifficultyColors;
    if (!context.isDarkMode) return colors;
    return (bg: colors.fg.withValues(alpha: 0.18), fg: colors.fg);
  }

  ({Color bg, Color fg}) get _lightDifficultyColors {
    switch (widget.config.difficulty) {
      case ExerciseDifficulty.easy:
        return (bg: const Color(0xFFE2F3D3), fg: const Color(0xFF558B2F));
      case ExerciseDifficulty.moderate:
        return (bg: const Color(0xFFFFF3D6), fg: const Color(0xFFF9A825));
      case ExerciseDifficulty.hard:
        return (bg: const Color(0xFFFFE0E0), fg: const Color(0xFFD32F2F));
    }
  }

  void _startExercise() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PoseDetectorScreen(selectedExercise: widget.config),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final visuals = _visuals;
    final diff = _difficultyColors;
    final palette = context.palette;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _scale = 0.97),
          onTapUp: (_) => setState(() => _scale = 1.0),
          onTapCancel: () => setState(() => _scale = 1.0),
          onTap: _startExercise,
          child: AnimatedScale(
            scale: _scale,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: visuals.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(visuals.icon, color: visuals.accent, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              config.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: palette.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.schedule_rounded, size: 13, color: palette.textMuted),
                                const SizedBox(width: 4),
                                Text(
                                  '${config.estimatedMinutes} min',
                                  style: TextStyle(fontSize: 12, color: palette.textMuted),
                                ),
                                const SizedBox(width: 12),
                                Icon(Icons.repeat_rounded, size: 13, color: palette.textMuted),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    config.repsText,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: palette.textMuted),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Where to stand: the angles are only measurable
                            // from the right camera view.
                            Row(
                              children: [
                                Icon(Icons.videocam_outlined, size: 13, color: palette.textMuted),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    config.cameraView.label,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: palette.textMuted),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: diff.bg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              config.difficulty.label,
                              style: TextStyle(color: diff.fg, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: _startExercise,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(color: visuals.accent, shape: BoxShape.circle),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (widget.progress != null) ...[
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: widget.progress,
                        minHeight: 6,
                        backgroundColor: visuals.accent.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation(visuals.accent),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
