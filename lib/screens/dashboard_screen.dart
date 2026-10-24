import 'dart:async';
import 'dart:math' as math;

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
import '../widgets/dashboard_sidebar.dart';
import '../widgets/profile_avatar.dart';
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
  int _bottomNavIndex = 0;
  int _prevNavIndex = 0;

  /// Shared by the page slide and the bottom-nav pill so they move in step.
  static const Duration _navDuration = Duration(milliseconds: 380);
  static const Curve _navCurve = Curves.easeInOutCubic;

  static const Color primaryTeal = Color(0xFF23A8AA);
  static const Color darkTeal = Color(0xFF0D6E71);
  static const Color lightTealBg = Color(0xFFE0F5F5);

  static const List<String> _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

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

  /// Home. [pageContext] is from inside the page area, so its MediaQuery
  /// width excludes the tablet sidebar (this State's own context is above
  /// that narrowed MediaQuery and would measure the whole screen).
  Widget _buildDashboardBody(BuildContext pageContext) {
    // One column width for the header content and the cards below it:
    // wide when Home shows two columns, the normal reading width otherwise.
    final columnWidth = adaptiveMaxWidth(pageContext);
    // Read once per build; the loader returns cached results unless the
    // list (or the day, plan or period) actually changed.
    final sessions = context.watch<AppProvider>().sessionHistory;
    final overview = _progress.overviewFor(sessions, prescriptions: _plan);
    final reportView = _progress.reportFor(
      sessions,
      days: _tabDays[_selectedTab],
      prescriptions: _plan,
    );

    return Column(
      children: [
        SlideTransition(
          position: _headerSlide,
          child: FadeTransition(
            opacity: _headerFade,
            child: _buildHeader(readableInset(pageContext, columnWidth)),
          ),
        ),
        Expanded(
          child: SlideTransition(
            position: _cardsSlide,
            child: FadeTransition(
              opacity: _cardsFade,
              child: SingleChildScrollView(
                // Wide screens (landscape tablets) get two columns of
                // cards; phones and portrait tablets keep one column in
                // the same order as before.
                padding: readablePadding(
                  pageContext,
                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  columnWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 18),
                    _buildActionChips(),
                    const SizedBox(height: 16),
                    AdaptiveColumns(
                      // Left: this week and the numbers.
                      left: [
                        _buildProgressCard(overview.week),
                        const SizedBox(height: 14),
                        _buildStatsRow(overview),
                        const SizedBox(height: 14),
                        _buildSummaryCard(reportView),
                        const SizedBox(height: 14),
                      ],
                      // Right: the daily quote and the therapist.
                      right: [
                        _buildQuoteCard(),
                        const SizedBox(height: 14),
                        _buildTherapistCard(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ],
                ),
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

  /// The four tabs, shared by the bottom bar (phones, portrait tablets) and
  /// the sidebar (landscape tablets).
  static final List<DashboardDestination> _destinations = [
    DashboardDestination(label: 'Home', icon: PhosphorIcons.squaresFour()),
    DashboardDestination(label: 'Exercise', icon: PhosphorIcons.barbell()),
    DashboardDestination(label: 'Messages', icon: PhosphorIcons.chatCircle()),
    DashboardDestination(label: 'Profile', icon: PhosphorIcons.userCircle()),
  ];

  /// Keeps the open page (its scroll position, a half-typed message, ...)
  /// when rotating moves it between the bottom-bar and the sidebar layout.
  final GlobalKey _pageAreaKey = GlobalKey(debugLabel: 'dashboard pages');

  void _selectTab(int index) {
    if (index == _bottomNavIndex) return;
    setState(() {
      _prevNavIndex = _bottomNavIndex;
      _bottomNavIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final showSidebar = media.size.width >= kSidebarBreakpoint;

    if (showSidebar) {
      // Landscape tablet: navigation on the left, no bottom bar. The page
      // area gets a MediaQuery as wide as the space right of the sidebar,
      // so readablePadding / isTwoColumn inside the pages measure what
      // they really have, not the whole screen.
      return Scaffold(
        backgroundColor: context.palette.background,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DashboardSidebar(
              destinations: _destinations,
              selectedIndex: _bottomNavIndex,
              onSelect: _selectTab,
            ),
            Expanded(
              child: MediaQuery(
                data: _pageAreaMedia(media),
                child: _buildPageArea(),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.palette.background,
      body: _buildPageArea(),
      bottomNavigationBar: ReadableWidth(child: _buildBottomNav()),
    );
  }

  /// The MediaQuery for the area right of the sidebar: narrower by the
  /// sidebar's width, and without the left safe-area inset, which the
  /// sidebar already covers.
  MediaQueryData _pageAreaMedia(MediaQueryData media) {
    final withoutLeftInset = media
        .removePadding(removeLeft: true)
        .removeViewPadding(removeLeft: true);
    final width = math.max(0.0, media.size.width - DashboardSidebar.width);
    return withoutLeftInset.copyWith(size: Size(width, media.size.height));
  }

  /// Pages slide sideways like a carousel: tapping a tab to the right (or
  /// lower in the sidebar) pushes the current page out to the left, and
  /// vice versa. Both pages share the same curve so they move together
  /// without a gap.
  Widget _buildPageArea() {
    return KeyedSubtree(
      key: _pageAreaKey,
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: _navDuration,
          switchInCurve: _navCurve,
          switchOutCurve: _navCurve,
          transitionBuilder: (child, anim) {
            final isIncoming = child.key == ValueKey(_bottomNavIndex);
            final dir = _bottomNavIndex >= _prevNavIndex ? 1.0 : -1.0;
            return SlideTransition(
              position: Tween<Offset>(
                begin: Offset(isIncoming ? dir : -dir, 0),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            );
          },
          child: KeyedSubtree(
            key: ValueKey(_bottomNavIndex),
            // Built under the page area's MediaQuery (see _buildDashboardBody).
            child: Builder(
              builder: (pageContext) => _buildPage(pageContext, _bottomNavIndex),
            ),
          ),
        ),
      ),
    );
  }

  // ── HEADER ─────────────────────────────────────────────────────────────────
  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  /// The teal Home header. [inset] lines its content up with the card
  /// column below on tablets (0 on phones).
  Widget _buildHeader(double inset) {
    final profile = context.watch<AppProvider>().profile;
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
          // On tablets the header's content lines up with the card column
          // below instead of hugging the screen edges (the teal background
          // itself stays full width).
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
                  Row(
                    children: [
                      UnreadNotifications(
                        builder: (context, unread) => _headerIconBtn(
                          PhosphorIcons.bell(),
                          badge: unread > 0,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NotificationPage(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _headerIconBtn(
                        PhosphorIcons.plus(),
                        onTap: () => setState(() {
                          _prevNavIndex = _bottomNavIndex;
                          _bottomNavIndex = 1;
                        }),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  // The patient's profile picture; tap to open the Profile tab.
                  GestureDetector(
                    onTap: () => setState(() {
                      _prevNavIndex = _bottomNavIndex;
                      _bottomNavIndex = 3;
                    }),
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
                        PhosphorIcon(
                          PhosphorIcons.calendarBlank(),
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

  Widget _headerIconBtn(
    PhosphorIconData icon, {
    bool badge = false,
    VoidCallback? onTap,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            onPressed: onTap,
            icon: PhosphorIcon(icon, color: Colors.white, size: 20),
          ),
        ),
        if (badge)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
                border: Border.all(color: darkTeal, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }

  // ── ACTION CHIPS ─────────────────────────────────────────────────────────────
  Widget _buildActionChips() {
    return Row(
      children: [
        _chip(
          PhosphorIcons.bellSimple(),
          'Alerts',
          const Color(0xFFFF6B35),
          hasBadge: true,
          onTap: () => setState(() {
            _prevNavIndex = _bottomNavIndex;
            _bottomNavIndex = 2;
          }),
        ),
        const SizedBox(width: 10),
        _chip(
          PhosphorIcons.chartLineUp(),
          'Progress',
          const Color(0xFF4A90D9),
          onTap: _openReport,
        ),
        const SizedBox(width: 10),
        _chip(
          PhosphorIcons.playCircle(),
          'Demo',
          const Color(0xFFE53935),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DemoScreen()),
          ),
        ),
      ],
    );
  }

  Widget _chip(
    PhosphorIconData icon,
    String label,
    Color color, {
    bool hasBadge = false,
    VoidCallback? onTap,
  }) {
    final palette = context.palette;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
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
                    child: PhosphorIcon(icon, size: 22, color: color),
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
        boxShadow: [
          BoxShadow(
            color: primaryTeal.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
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
                  gradient: const LinearGradient(
                    colors: [primaryTeal, darkTeal],
                  ),
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
              return Opacity(
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
                        boxShadow: checked
                            ? [
                                BoxShadow(
                                  color: primaryTeal.withValues(alpha: 0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: checked
                            ? const Icon(
                                Icons.check_rounded,
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
                    const SizedBox(height: 6),
                    Text(
                      _days[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: checked
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: checked ? primaryTeal : palette.textMuted,
                      ),
                    ),
                  ],
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
                          gradient: const LinearGradient(
                            colors: [primaryTeal, darkTeal],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: primaryTeal.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
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
    final timeDelta = cur.time.inMinutes - prev.time.inMinutes;

    // Trend badges compare with the previous window of the same length.
    String signed(int n, [String unit = '']) => n > 0 ? '+$n$unit' : '$n$unit';

    return Row(
      children: [
        _buildStatCard(
          'Active Days',
          '${cur.activeDays}',
          cur.activeDays - prev.activeDays,
          signed(cur.activeDays - prev.activeDays),
          PhosphorIcons.calendarCheck(),
          const Color(0xFFFF6B35),
        ),
        const SizedBox(width: 10),
        _buildStatCard(
          'Sessions',
          '${cur.sessions}',
          cur.sessions - prev.sessions,
          signed(cur.sessions - prev.sessions),
          PhosphorIcons.heartbeat(),
          primaryTeal,
        ),
        const SizedBox(width: 10),
        _buildStatCard(
          'Time',
          ProgressStats.formatDuration(cur.time),
          timeDelta,
          signed(timeDelta, 'm'),
          PhosphorIcons.timer(),
          const Color(0xFF7C4DFF),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    int delta,
    String sub,
    PhosphorIconData icon,
    Color color,
  ) {
    final trendColor = delta > 0
        ? Colors.green
        : delta < 0
            ? Colors.red
            : Colors.grey;
    final palette = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: PhosphorIcon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: palette.textMuted),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                // shade50 is a glaring pastel on a dark card: use a tint.
                color: context.isDarkMode
                    ? trendColor.withValues(alpha: 0.15)
                    : trendColor.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PhosphorIcon(
                    delta > 0
                        ? PhosphorIconsRegular.arrowUp
                        : delta < 0
                            ? PhosphorIconsRegular.arrowDown
                            : PhosphorIconsRegular.minus,
                    size: 10,
                    color: trendColor,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 10,
                      color: trendColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
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
        gradient: const LinearGradient(
          colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0), Color(0xFFAB47BC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9C27B0).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
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
            child: const PhosphorIcon(
              PhosphorIconsRegular.quotes,
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
    final therapist = context.watch<AppProvider>().profile?.therapist ?? '';
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: primaryTeal.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhosphorIcon(
                PhosphorIcons.stethoscope(),
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
                    child: const PhosphorIcon(
                      PhosphorIconsRegular.user,
                      size: 30,
                      color: primaryTeal,
                    ),
                  ),
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.surface, width: 2),
                      ),
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
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF4CAF50),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Available now',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF4CAF50),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => setState(() {
                  _prevNavIndex = _bottomNavIndex;
                  _bottomNavIndex = 2;
                }),
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
                  'Contact',
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

  // ── BOTTOM NAV ───────────────────────────────────────────────────────────────
  /// Bottom nav with one highlight pill that slides (and resizes) to the
  /// selected tab, in step with the page slide.
  ///
  /// Each item gets an explicit width (icon, plus the label when selected), and
  /// the Row spaces them with spaceAround. Item x positions are then a linear
  /// function of the widths, so animating the widths and the pill's
  /// left/width with the same duration and curve keeps the pill exactly under
  /// its item for the whole animation.
  Widget _buildBottomNav() {
    final items = [for (final d in _destinations) (d.icon, d.label)];

    const iconSize = 22.0;
    const labelGap = 6.0;
    const hPad = 16.0;
    const itemHeight = 38.0;
    const labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final palette = context.palette;

    double labelWidth(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      return painter.width.ceilToDouble();
    }

    double itemWidth(int i) =>
        hPad * 2 +
        iconSize +
        (i == _bottomNavIndex ? labelGap + labelWidth(items[i].$2) : 0);

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final widths = List.generate(items.length, itemWidth);
              // Where spaceAround puts the selected item once settled.
              final spacing =
                  (constraints.maxWidth - widths.reduce((a, b) => a + b)) /
                  items.length;
              var pillLeft = spacing / 2 + spacing * _bottomNavIndex;
              for (var i = 0; i < _bottomNavIndex; i++) {
                pillLeft += widths[i];
              }

              return SizedBox(
                height: itemHeight,
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: _navDuration,
                      curve: _navCurve,
                      left: pillLeft,
                      width: widths[_bottomNavIndex],
                      top: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [primaryTeal, darkTeal],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: primaryTeal.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(items.length, (i) {
                        final selected = _bottomNavIndex == i;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _selectTab(i),
                          child: AnimatedContainer(
                            duration: _navDuration,
                            curve: _navCurve,
                            width: widths[i],
                            height: itemHeight,
                            // The label is clipped while the item shrinks.
                            child: ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.centerLeft,
                                minWidth: 0,
                                maxWidth: double.infinity,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: hPad),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TweenAnimationBuilder<Color?>(
                                        tween: ColorTween(
                                          end: selected
                                              ? Colors.white
                                              : palette.textFaint,
                                        ),
                                        duration: _navDuration,
                                        curve: _navCurve,
                                        builder: (context, color, _) =>
                                            PhosphorIcon(
                                              items[i].$1,
                                              size: iconSize,
                                              color: color,
                                            ),
                                      ),
                                      const SizedBox(width: labelGap),
                                      AnimatedOpacity(
                                        opacity: selected ? 1 : 0,
                                        duration: _navDuration,
                                        curve: _navCurve,
                                        child: Text(
                                          items[i].$2,
                                          style: labelStyle,
                                          maxLines: 1,
                                          softWrap: false,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
