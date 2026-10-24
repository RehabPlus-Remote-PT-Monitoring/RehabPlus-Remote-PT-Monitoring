// lib/screens/exercise_page.dart
//
// The Exercise tab (second dashboard tab, a root page: no back button).
// iOS large-title page: "Exercises" collapses into the bar as you scroll,
// with the notifications bell and today's checklist as bar buttons. Below
// it, "Your Plan" (the therapist's prescriptions, with weekly progress) and
// "All Exercises" (the rest of the catalog). Tapping a card opens the camera
// exercise. Phones show one column of cards, wide tablets two.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// `show`: intl also exports a TextDirection that clashes with Flutter's.
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../core/app_palette.dart';
import '../models/exercise_model.dart';
import '../services/app_provider.dart';
import '../services/prescription_service.dart';
import '../services/progress_stats.dart';
import '../widgets/exercise_card_body.dart';
import '../widgets/exercise_list_layout.dart';
import '../widgets/pressable.dart';
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
    // Two columns of cards on wide tablets need the wider content column.
    final maxWidth = adaptiveMaxWidth(context);

    return Scaffold(
      backgroundColor: palette.background,
      // No bottomNavigationBar here: DashboardScreen already has one.
      body: FutureBuilder<List<ExerciseConfig>>(
        future: _exercisesFuture,
        builder: (context, snapshot) {
          return CustomScrollView(
            // iOS bounce even when the list is short, so the large title
            // still collapses and pull-to-refresh always works.
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              _buildNavigationBar(context, maxWidth),
              CupertinoSliverRefreshControl(onRefresh: _refresh),
              SliverPadding(
                padding: readablePadding(
                  context,
                  const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  maxWidth,
                ),
                sliver: SliverToBoxAdapter(child: _buildIntro(context)),
              ),
              ..._buildContent(context, snapshot, maxWidth),
            ],
          );
        },
      ),
    );
  }

  /// Large title "Exercises" with the two bar buttons. Built here rather
  /// than with IosPage because a tab's root page must never show a back
  /// button, whatever route the dashboard itself sits on.
  Widget _buildNavigationBar(BuildContext context, double maxWidth) {
    final palette = context.palette;
    final inset = readableInset(context, maxWidth);
    return CupertinoSliverNavigationBar(
      automaticallyImplyLeading: false,
      largeTitle: Padding(
        // Line the title up with the cards on tablets.
        padding: EdgeInsets.only(left: inset),
        child: const Text('Exercises'),
      ),
      middle: const Text('Exercises'),
      alwaysShowMiddle: false,
      trailing: _buildBarButtons(),
      padding: EdgeInsetsDirectional.only(
        start: inset > 0 ? inset : 8,
        end: inset > 0 ? inset + 4 : 8,
      ),
      backgroundColor: palette.background.withValues(alpha: 0.86),
      border: Border(bottom: BorderSide(color: palette.divider, width: 0.5)),
      transitionBetweenRoutes: false,
    );
  }

  /// Bell (with a dot while there are unread notifications) and Today's
  /// plan (with a dot while something due today isn't done yet).
  Widget _buildBarButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        UnreadNotifications(
          builder: (context, unread) => _BarIconButton(
            icon: CupertinoIcons.bell,
            tooltip: unread > 0
                ? 'Notifications, $unread unread'
                : 'Notifications',
            hasBadge: unread > 0,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationPage()),
            ),
          ),
        ),
        Consumer<AppProvider>(
          builder: (context, provider, _) {
            final remaining = TodayChecklistSheet.remainingToday(
              _assigned,
              provider.sessionHistory,
              DateTime.now(),
            );
            return _BarIconButton(
              icon: CupertinoIcons.doc_checkmark,
              tooltip: remaining > 0
                  ? "Today's plan, $remaining left"
                  : "Today's plan",
              hasBadge: remaining > 0,
              onPressed: () => TodayChecklistSheet.show(context, _assigned),
            );
          },
        ),
      ],
    );
  }

  /// Today's date and a one-line prompt, in grey under the large title.
  Widget _buildIntro(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('EEEE, d MMMM').format(DateTime.now()).toUpperCase(),
          style: textTheme.bodySmall?.copyWith(
            color: palette.textMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Select an exercise to start a camera session.',
          style: textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }

  /// The slivers under the intro: a spinner on first load, an error
  /// message, or the two sections of cards.
  List<Widget> _buildContent(
    BuildContext context,
    AsyncSnapshot<List<ExerciseConfig>> snapshot,
    double maxWidth,
  ) {
    // The dashboard's translucent tab bar lies over the bottom of the page;
    // its height arrives as bottom padding, so the last card can scroll
    // clear of it.
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    // While refreshing, FutureBuilder keeps the previous data: keep showing
    // the list (the pull-to-refresh spinner shows progress) instead of
    // blanking the page.
    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: const Center(child: CircularProgressIndicator.adaptive()),
          ),
        ),
      ];
    }

    if (snapshot.hasError) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: _buildMessage(
              icon: CupertinoIcons.wifi_slash,
              text:
                  "Couldn't load your plan. Check your connection and try again.",
              onRetry: _refresh,
            ),
          ),
        ),
      ];
    }

    final exercises = snapshot.data ?? const <ExerciseConfig>[];
    // Rest of the catalog, minus anything already in the plan so no
    // exercise appears twice.
    final assignedTypes = exercises.map((e) => e.type).toSet();
    final others = availableExercises
        .where((c) => !assignedTypes.contains(c.type))
        .toList();
    final twoColumns = isTwoColumn(context);

    return [
      SliverPadding(
        padding: readablePadding(
          context,
          EdgeInsets.fromLTRB(16, 4, 16, 24 + bottomInset),
          maxWidth,
        ),
        sliver: Consumer<AppProvider>(
          builder: (context, provider, _) {
            final lastWeek = ProgressStats.countByExerciseSince(
              provider.sessionHistory,
              DateTime.now().subtract(const Duration(days: 7)),
            );

            final planCards = <Widget>[
              for (var i = 0; i < exercises.length; i++)
                AnimatedExerciseCard(
                  // Keys keep each card's animation state with its
                  // exercise when a refresh reorders the plan.
                  key: ValueKey(
                    'plan-${exercises[i].prescription?.id ?? 'i$i'}',
                  ),
                  index: i,
                  config: exercises[i],
                  progress: _weeklyProgress(lastWeek, exercises[i]),
                ),
            ];
            final catalogCards = <Widget>[
              for (var i = 0; i < others.length; i++)
                AnimatedExerciseCard(
                  key: ValueKey('catalog-${others[i].type.name}'),
                  index: exercises.length + i,
                  config: others[i],
                ),
            ];

            return SliverList.list(
              children: [
                ExerciseSectionHeader(
                  title: 'Your Plan',
                  count: exercises.length,
                ),
                if (exercises.isEmpty)
                  _buildEmptyPlanNote()
                else
                  ...exerciseCardRows(planCards, twoColumns: twoColumns),
                if (others.isNotEmpty) ...[
                  ExerciseSectionHeader(
                    title: 'All Exercises',
                    count: others.length,
                  ),
                  ...exerciseCardRows(catalogCards, twoColumns: twoColumns),
                ],
              ],
            );
          },
        ),
      ),
    ];
  }

  Widget _buildEmptyPlanNote() {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.calendar, color: AppPalette.teal),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No therapy plan assigned yet. Check back once your therapist sets one up.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
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
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: palette.textFaint),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: const Text(
                'Try Again',
                style: TextStyle(
                  color: AppPalette.teal,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A teal icon button for the navigation bar, 44x44 (iOS minimum), with a
/// tooltip (also its screen-reader label) and an optional red dot.
class _BarIconButton extends StatelessWidget {
  const _BarIconButton({
    required this.icon,
    required this.tooltip,
    required this.hasBadge,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool hasBadge;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      color: AppPalette.teal,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: Badge(
        isLabelVisible: hasBadge,
        smallSize: 8,
        child: Icon(icon, size: 24),
      ),
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // With the system's "remove animations" setting on, show the card at
    // once instead of fading and sliding it in.
    if (MediaQuery.disableAnimationsOf(context)) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startExercise() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            PoseDetectorScreen(selectedExercise: widget.config),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        // The whole card is the button. Haptic: starting an exercise is a
        // meaningful moment, not plain navigation.
        child: Pressable(
          haptic: true,
          semanticLabel: 'Start ${widget.config.title}',
          onTap: _startExercise,
          child: ExerciseCardBody(
            config: widget.config,
            progress: widget.progress,
          ),
        ),
      ),
    );
  }
}
