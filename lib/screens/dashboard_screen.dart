import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../services/app_provider.dart';
import '../models/prescription.dart';
import '../services/prescription_service.dart';
import '../services/progress_report_loader.dart';
import '../services/progress_stats.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/dashboard_shell.dart';
import '../widgets/dashboard_tab_bar.dart' show DashboardDestination;
import '../widgets/pressable.dart';
import '../widgets/unread_badge.dart';
import '../core/responsive.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';
import 'notification_page.dart';
import 'demo_screen.dart';
import 'exercise_page.dart';
import 'progress_report_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedTab = 0;
  int _prevSelectedTab = 0;
  /// The open tab: 0 Home, 1 Exercise, 2 Messages, 3 Profile.
  int _tabIndex = 0;

  /// Shared by the page slide and the bottom-nav pill so they move in step.

  static const Color primaryTeal = Color(0xFF23A8AA);
  static const Color darkTeal = Color(0xFF0D6E71);
  static const Color lightTealBg = Color(0xFFE0F5F5);

  static const List<String> _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  /// Full names for screen readers (the circles only show a letter).
  static const List<String> _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday',
  ];

  /// Window sizes for the 7 / 30 / 90 day tabs.
  static const List<int> _tabDays = [7, 30, 90];

  late final AnimationController _headerCtrl;
  late final AnimationController _cardsCtrl;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;
  late final Animation<double> _cardsFade;
  late final Animation<Offset> _cardsSlide;

  // ── PROGRESS NUMBERS ───────────────────────────────────────────────────────
  // The week tracker, stat cards and "How you're doing" card are computed by
  // the loader once per change of the sessions, plan, day or period, not on
  // every rebuild (tab taps, nav animations and clock ticks all rebuild this
  // screen). Long histories are built on a background isolate; see
  // progress_report_loader.dart for the threshold.
  late final ProgressReportLoader _progress = ProgressReportLoader(
    owner: 'dashboard',
    onBackgroundResult: () {
      if (mounted) setState(() {});
    },
  );

  @override
  void initState() {
    super.initState();

    _headerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _cardsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOutCubic));

    _cardsFade = CurvedAnimation(parent: _cardsCtrl, curve: Curves.easeOut);
    _cardsSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _cardsCtrl, curve: Curves.easeOutCubic));

    _headerCtrl.forward();
    Future.delayed(
      const Duration(milliseconds: 250),
      () => _cardsCtrl.forward(),
    );

    WidgetsBinding.instance.addObserver(this);
    _scheduleClockRefresh();
    _loadPlan();
  }

  // ── THE THERAPIST'S PLAN (for "followed X% of your plan") ───────────────────
  List<Prescription> _plan = const [];

  Future<void> _loadPlan() async {
    try {
      final assigned = await PrescriptionService().loadAssignedExercises();
      if (!mounted) return;
      setState(() {
        _plan = [
          for (final e in assigned)
            if (e.prescription != null) e.prescription!,
        ];
      });
    } catch (e, st) {
      // Offline or not signed in: the report falls back to active days.
      DiagnosticLogger.I.warn(
        'Dashboard',
        'Plan load failed; report uses active days',
        {'errorType': e.runtimeType.toString()},
        e,
        st,
      );
    }
  }

  void _openReport() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ProgressReportScreen(
        initialDays: _tabDays[_selectedTab],
        prescriptions: _plan,
      ),
    ),
  );

  // ── KEEP THE DATE AND GREETING CURRENT ─────────────────────────────────────
  // Both are read from the clock when the screen redraws. Redraw at the next
  // change (noon, 6 PM, midnight) and whenever the app comes back to the
  // foreground (timers don't run while it's in the background).
  Timer? _clockTimer;

  void _scheduleClockRefresh() {
    _clockTimer?.cancel();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final next = [
      today.add(const Duration(hours: 12)),
      today.add(const Duration(hours: 18)),
      DateTime(now.year, now.month, now.day + 1),
    ].firstWhere((t) => t.isAfter(now));
    // A second late so the clock is safely past the boundary.
    _clockTimer = Timer(next.difference(now) + const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {});
      _scheduleClockRefresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      _scheduleClockRefresh();
      _loadPlan(); // the therapist may have changed it
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _progress.dispose();
    _headerCtrl.dispose();
    _cardsCtrl.dispose();
    super.dispose();
  }

  /// The Home tab. [pageContext] is inside the dashboard shell: its
  /// MediaQuery width is the page area (beside the tablet sidebar) and its
  /// bottom padding includes the translucent tab bar.
  Widget _buildDashboardBody(BuildContext pageContext) {
    // Read once per build; the loader returns cached results unless the
    // list (or the day, plan or period) actually changed. (DashboardScreen's
    // build watches AppProvider, so this rebuilds when it changes.)
    final sessions = context.read<AppProvider>().sessionHistory;
    final overview = _progress.overviewFor(sessions, prescriptions: _plan);
    final reportView = _progress.reportFor(
      sessions,
      days: _tabDays[_selectedTab],
      prescriptions: _plan,
    );

    // Tablets: content up to 1100 dp in two columns; the header's content
    // lines up with the same column.
    final maxWidth = adaptiveMaxWidth(pageContext);
    final inset = readableInset(pageContext, maxWidth);
    final bottomClearance = MediaQuery.paddingOf(pageContext).bottom;

    const gap = SizedBox(height: 14);
    // Most used first: on a phone the right column follows the left one.
    final left = <Widget>[
      _buildActionChips(),
      const SizedBox(height: 16),
      _buildProgressCard(overview.week),
      gap,
      _buildStatsRow(overview),
      gap,
    ];
    final right = <Widget>[
      _buildSummaryCard(reportView),
      gap,
      _buildTherapistCard(),
      gap,
      _buildQuoteCard(),
      gap,
    ];

    return Column(
      children: [
        SlideTransition(
          position: _headerSlide,
          child: FadeTransition(
            opacity: _headerFade,
            child: _buildHeader(inset),
          ),
        ),
        Expanded(
          child: SlideTransition(
            position: _cardsSlide,
            child: FadeTransition(
              opacity: _cardsFade,
              child: SingleChildScrollView(
                padding: readablePadding(
                  pageContext,
                  EdgeInsets.fromLTRB(16, 18, 16, 16 + bottomClearance),
                  maxWidth,
                ),
                // Measures the page area's MediaQuery (it is built under
                // the shell), so it goes two-up beside the sidebar too.
                child: AdaptiveColumns(left: left, right: right),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// "How you're doing" for the selected period. Small histories always
  /// have a report ready; only a very long one shows a placeholder on first
  /// load, then the previous report (dimmed) while a new one is built.
  Widget _buildSummaryCard(ProgressReportView view) {
    final report = view.report;
    if (report == null) {
      // Failed (already logged with the stack): leave the card out rather
      // than show wrong numbers.
      return view.failed
          ? const SizedBox.shrink()
          : const ProgressSummaryLoading();
    }
    return AnimatedOpacity(
      opacity: view.isStale ? 0.55 : 1,
      duration: const Duration(milliseconds: 200),
      child: ProgressSummaryCard(report: report, onOpenReport: _openReport),
    );
  }

  /// Builds only the page that is showing. (The list of all four pages used
  /// to be built on every rebuild, including the whole Home body with its
  /// statistics while another tab was open.)
  Widget _buildPage(BuildContext pageContext, int index) => switch (index) {
    0 => _buildDashboardBody(pageContext),
    1 => const ExercisePage(),
    2 => const MessagesScreen(),
    _ => const Scaffold(body: ProfileScreen()),
  };

  /// Opens tab [index] (from the tab bar, the sidebar or a shortcut on
  /// Home), logging the change like the other navigation in the app.
  void _selectTab(int index) {
    if (index == _tabIndex) return;
    DiagnosticLogger.I.info('Dashboard', 'Tab changed', {
      'from': _tabIndex,
      'to': index,
    });
    setState(() => _tabIndex = index);
  }

  /// The four top-level destinations, shared by the tab bar and the
  /// sidebar. Messages carries the unread-messages badge.
  List<DashboardDestination> get _destinations => [
    const DashboardDestination(
      label: 'Home',
      icon: CupertinoIcons.square_grid_2x2,
      selectedIcon: CupertinoIcons.square_grid_2x2_fill,
    ),
    const DashboardDestination(
      label: 'Exercise',
      icon: CupertinoIcons.flame,
      selectedIcon: CupertinoIcons.flame_fill,
    ),
    DashboardDestination(
      label: 'Messages',
      icon: CupertinoIcons.chat_bubble_2,
      selectedIcon: CupertinoIcons.chat_bubble_2_fill,
      badge: UnreadMessages(
        builder: (context, unread) => unread > 0
            ? UnreadCountBadge(count: unread)
            : const SizedBox.shrink(),
      ),
    ),
    const DashboardDestination(
      label: 'Profile',
      icon: CupertinoIcons.person_crop_circle,
      selectedIcon: CupertinoIcons.person_crop_circle_fill,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Watched here, once: Home's parts are built inside the shell (a
    // Builder below), where they read the provider without subscribing.
    context.watch<AppProvider>();
    return DashboardShell(
      destinations: _destinations,
      selectedIndex: _tabIndex,
      onSelect: _selectTab,
      sidebarHeader: _sidebarHeader(),
      // Built under the shell, so MediaQuery here is the page area: its
      // width excludes the sidebar and its bottom padding includes the
      // translucent tab bar.
      page: Builder(builder: (pageContext) => _buildPage(pageContext, _tabIndex)),
    );
  }

  /// App name at the top of the tablet sidebar.
  Widget _sidebarHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: primaryTeal,
            borderRadius: BorderRadius.circular(9),
          ),
          child: PhosphorIcon(
            PhosphorIcons.shieldPlus(),
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'RehabPlus',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    );
  }

  // ── HEADER ─────────────────────────────────────────────────────────────────
  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  /// The teal Home header (the app's one gradient). [inset] lines its
  /// content up with the card column below on tablets.
  Widget _buildHeader(double inset) {
    final profile = context.read<AppProvider>().profile;
    final name = profile?.name ?? '';
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [darkTeal, Color(0xFF1A8587), primaryTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20 + inset, 14, 16 + inset, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: PhosphorIcon(
                          PhosphorIcons.shieldPlus(),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Rehab +',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  // The patient's profile picture; tap to open the Profile tab.
                  Pressable(
                    onTap: () => _selectTab(3),
                    semanticLabel: 'Open your profile',
                    pressedScale: 0.92,
                    child: ProfileAvatar(
                      photo: profile?.photo,
                      size: 50,
                      onHeader: true,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                        Text(
                          name.isEmpty ? 'Welcome back' : name,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.calendar,
                          color: Colors.white70,
                          size: 13,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          DateFormat('EEE, d MMM').format(DateTime.now()),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── ACTION CHIPS ─────────────────────────────────────────────────────────────
  Widget _buildActionChips() {
    return Row(
      children: [
        // Alerts = the Notifications page, with a dot only when something
        // is unread. (It used to open the Messages tab and always show a
        // dot.) The header's own bell and "+" were removed: the bell
        // duplicated this tile and "+" duplicated the Exercise tab.
        Expanded(
          child: UnreadNotifications(
            builder: (context, unread) => _chip(
              CupertinoIcons.bell,
              'Alerts',
              const Color(0xFFFF6B35),
              hasBadge: unread > 0,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationPage()),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _chip(
            CupertinoIcons.graph_square,
            'Progress',
            const Color(0xFF4A90D9),
            onTap: _openReport,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _chip(
            CupertinoIcons.play_circle,
            'Demo',
            const Color(0xFFE53935),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DemoScreen()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(
    IconData icon,
    String label,
    Color color, {
    bool hasBadge = false,
    VoidCallback? onTap,
  }) {
    final palette = context.palette;
    // The caller wraps it in Expanded (one third of the row each).
    return Pressable(
        onTap: onTap,
        semanticLabel: hasBadge ? '$label, new' : label,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 22, color: color),
                  ),
                  if (hasBadge)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                          // Ring in the card colour so the dot looks cut out.
                          border: Border.all(color: palette.surface, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
    );
  }

  // ── PROGRESS CARD ────────────────────────────────────────────────────────────
  /// [week] = exercised on each day of this week, Monday first (from
  /// [ProgressOverview.week]).
  Widget _buildProgressCard(List<bool> week) {
    final now = DateTime.now();
    final todayIndex = now.weekday - 1;
    final activeThisWeek = week.where((d) => d).length;
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Weekly Progress',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: primaryTeal,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$activeThisWeek/7 days',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Day tracker
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              // Filled = exercised that day (from saved sessions); today is
              // outlined; days still ahead are faded.
              final checked = week[i];
              final isToday = i == todayIndex;
              final isFuture = i > todayIndex;
              return Semantics(
                label: '${_dayNames[i]}, ${checked ? 'exercised' : isToday ? 'today, not yet' : 'no exercise'}',
                excludeSemantics: true,
                child: Opacity(
                opacity: isFuture ? 0.45 : 1,
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: checked ? primaryTeal : palette.surfaceMuted,
                        shape: BoxShape.circle,
                        border: isToday && !checked
                            ? Border.all(color: primaryTeal, width: 2)
                            : null,
                      ),
                      child: Center(
                        child: checked
                            ? const Icon(
                                CupertinoIcons.checkmark,
                                size: 18,
                                color: Colors.white,
                              )
                            : Text(
                                _days[i],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: palette.textMuted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                ),
              );
            }),
          ),

          const SizedBox(height: 20),

          // Tab selector: one pill slides under the chosen window.
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: palette.surfaceMuted,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeInOutCubic,
                    // -1, 0, 1 = left, middle, right third.
                    alignment: Alignment(_selectedTab - 1.0, 0),
                    child: FractionallySizedBox(
                      widthFactor: 1 / _tabDays.length,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: primaryTeal,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    _buildDayTab('7 Day', 0),
                    _buildDayTab('30 Day', 1),
                    _buildDayTab('90 Day', 2),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayTab(String title, int index) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (index == _selectedTab) return;
          DiagnosticLogger.I.info('Dashboard', 'Range changed', {
            'fromDays': _tabDays[_selectedTab],
            'toDays': _tabDays[index],
          });
          setState(() {
            _prevSelectedTab = _selectedTab;
            _selectedTab = index;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : context.palette.textMuted,
            ),
            child: Text(title, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }

  // ── STATS ROW ────────────────────────────────────────────────────────────────
  /// The stat cards for the chosen window. Switching 7/30/90 days slides the
  /// new numbers in from the side of the tab that was tapped.
  Widget _buildStatsRow(ProgressOverview overview) {
    final forward = _selectedTab >= _prevSelectedTab;
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) {
          final isIncoming = child.key == ValueKey(_selectedTab);
          final dir = forward ? 1.0 : -1.0;
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(isIncoming ? 0.35 * dir : -0.35 * dir, 0),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(_selectedTab),
          child: _buildStatCards(overview.periodFor(_tabDays[_selectedTab])),
        ),
      ),
    );
  }

  Widget _buildStatCards(PeriodComparison period) {
    final cur = period.current;
    final prev = period.previous;
    final days = _tabDays[_selectedTab];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildStatCard(
            'Active Days',
            '${cur.activeDays}',
            _compare(cur.activeDays - prev.activeDays, days, unit: 'day'),
            CupertinoIcons.calendar_badge_plus,
            const Color(0xFFFF6B35),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            'Sessions',
            '${cur.sessions}',
            _compare(cur.sessions - prev.sessions, days, unit: 'session'),
            CupertinoIcons.heart,
            primaryTeal,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            'Time',
            ProgressStats.formatDuration(cur.time),
            _compare(
              cur.time.inMinutes - prev.time.inMinutes,
              days,
              unit: 'min',
              countable: false,
            ),
            CupertinoIcons.timer,
            const Color(0xFF7C4DFF),
          ),
        ),
      ],
    );
  }

  /// Plain words comparing with the previous window of the same length,
  /// e.g. "2 fewer than the 7 days before". This replaced red/green arrow
  /// pills: a patient having a slower week should read a fact, not a
  /// warning, and the meaning must not depend on colour.
  String _compare(
    int delta,
    int days, {
    required String unit,
    bool countable = true,
  }) {
    final before = 'than the $days days before';
    if (delta == 0) return 'Same as the $days days before';
    final n = delta.abs();
    final noun = countable && n != 1 ? '${unit}s' : unit;
    if (delta > 0) return '$n $noun more $before';
    return countable ? '$n $noun fewer $before' : '$n $noun less $before';
  }

  Widget _buildStatCard(
    String label,
    String value,
    String comparison,
    IconData icon,
    Color color,
  ) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              comparison,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── QUOTE CARD ───────────────────────────────────────────────────────────────
  Widget _buildQuoteCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF8E24AA),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              CupertinoIcons.quote_bubble,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily Motivation',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'The session plants the seed, but your daily movement is what makes it grow.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── THERAPIST CARD ───────────────────────────────────────────────────────────
  Widget _buildTherapistCard() {
    final therapist = context.read<AppProvider>().profile?.therapist ?? '';
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.heart_circle,
                color: primaryTeal,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Your Therapist',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      // Pale teal avatar in light mode; a teal tint in dark,
                      // where the pastel would glare.
                      gradient: LinearGradient(
                        colors: context.isDarkMode
                            ? [
                                primaryTeal.withValues(alpha: 0.18),
                                primaryTeal.withValues(alpha: 0.28),
                              ]
                            : const [lightTealBg, Color(0xFFB2DFDB)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.person,
                      size: 30,
                      color: primaryTeal,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      therapist.isEmpty ? 'Not assigned yet' : therapist,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Physical Therapist',
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => _selectTab(2),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryTeal,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Message',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
