import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
// `show`: intl also exports a TextDirection that clashes with Flutter's.
import 'package:intl/intl.dart' show DateFormat;
import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../services/app_provider.dart';
import '../services/progress_stats.dart';
import '../models/session.dart';
import '../core/responsive.dart';

/// Card shadow for this screen. Light mode keeps the design's soft glow in
/// the card's own colour; on a dark page a coloured glow reads as a smudge,
/// so dark mode uses a plain, slightly stronger black shadow instead.
BoxShadow _cardShadow(BuildContext context, Color glow, {double alpha = 0.08}) {
  final dark = context.isDarkMode;
  return BoxShadow(
    color: dark
        ? context.palette.shadow.withValues(alpha: 0.3)
        : glow.withValues(alpha: alpha),
    blurRadius: 12,
    offset: const Offset(0, 4),
  );
}

/// Totals for the summary row, computed once per session list (see
/// [_HistoryScreenState._summaryFor]) instead of on every rebuild.
class _HistorySummary {
  const _HistorySummary({
    required this.sessions,
    required this.sets,
    required this.avgScore,
  });

  factory _HistorySummary.of(List<ExerciseSession> sessions) {
    var sets = 0;
    var compliance = 0.0;
    for (final s in sessions) {
      sets += s.completedSets < 0 ? 0 : s.completedSets;
      // NaN-safe: a NaN here used to throw in toInt() and break the screen.
      compliance += s.safeCompliance;
    }
    return _HistorySummary(
      sessions: sessions.length,
      sets: sets,
      avgScore: sessions.isEmpty
          ? 0
          : (compliance / sessions.length * 100).toInt(),
    );
  }

  final int sessions;
  final int sets;
  final int avgScore;
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with TickerProviderStateMixin {
  // Brand colours come from AppPalette so they match every other screen.
  static const Color primaryTeal = AppPalette.teal;
  static const Color darkTeal = AppPalette.darkTeal;

  int _selectedCategory = 0;
  static const List<String> _categories = [
    'All',
    'Knee',
    'Shoulder',
    'Back',
    'Hip',
  ];

  late final AnimationController _headerCtrl;
  late final AnimationController _listCtrl;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;
  late final Animation<double> _listFade;
  late final Animation<Offset> _listSlide;

  // Sample exercises shown when no real sessions exist
  static const List<_ExerciseItem> _exercises = [
    _ExerciseItem(
      name: 'Knee Extension',
      category: 'Knee',
      sets: 3,
      reps: 12,
      duration: '15 min',
      difficulty: 'Moderate',
      icon: CupertinoIcons.arrow_up_arrow_down,
      color: Color(0xFF23A8AA),
      progress: 0.75,
    ),
    _ExerciseItem(
      name: 'Shoulder Rotation',
      category: 'Shoulder',
      sets: 3,
      reps: 10,
      duration: '10 min',
      difficulty: 'Easy',
      icon: CupertinoIcons.arrow_clockwise,
      color: Color(0xFF4A90D9),
      progress: 0.5,
    ),
    _ExerciseItem(
      name: 'Hip Abduction',
      category: 'Hip',
      sets: 4,
      reps: 15,
      duration: '20 min',
      difficulty: 'Hard',
      icon: CupertinoIcons.arrow_left_right,
      color: Color(0xFFFF6B35),
      progress: 0.3,
    ),
    _ExerciseItem(
      name: 'Lower Back Stretch',
      category: 'Back',
      sets: 2,
      reps: 8,
      duration: '12 min',
      difficulty: 'Easy',
      icon: CupertinoIcons.arrow_up_arrow_down,
      color: Color(0xFF7C4DFF),
      progress: 0.9,
    ),
    _ExerciseItem(
      name: 'Quad Strengthening',
      category: 'Knee',
      sets: 3,
      reps: 10,
      duration: '18 min',
      difficulty: 'Moderate',
      icon: CupertinoIcons.bolt,
      color: Color(0xFFE53935),
      progress: 0.6,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _listCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(begin: const Offset(0, -0.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOutCubic));
    _listFade = CurvedAnimation(parent: _listCtrl, curve: Curves.easeOut);
    _listSlide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _listCtrl, curve: Curves.easeOutCubic));

    _headerCtrl.forward();
    Future.delayed(const Duration(milliseconds: 200), () => _listCtrl.forward());
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  /// Exercises for the selected category. Recomputed only when the
  /// category changes (it used to be re-filtered for every list item).
  List<_ExerciseItem> _filtered = _exercises;

  void _selectCategory(int index) {
    if (index == _selectedCategory) return;
    DiagnosticLogger.I.info('HistoryScreen', 'Category filter changed', {
      'categoryIndex': index,
    });
    setState(() {
      _selectedCategory = index;
      _filtered = index == 0
          ? _exercises
          : _exercises.where((e) => e.category == _categories[index]).toList();
    });
  }

  // Summary memo: AppProvider replaces the list on every load, so identity
  // plus length tells us exactly when the totals need recomputing.
  List<ExerciseSession>? _summarySource;
  int _summaryLength = -1;
  _HistorySummary? _summary;

  _HistorySummary _summaryFor(List<ExerciseSession> sessions) {
    final cached = _summary;
    if (cached != null &&
        identical(sessions, _summarySource) &&
        sessions.length == _summaryLength) {
      return cached;
    }
    _summarySource = sessions;
    _summaryLength = sessions.length;
    return _summary = _HistorySummary.of(sessions);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      body: Column(
        children: [
          SlideTransition(
            position: _headerSlide,
            child: FadeTransition(opacity: _headerFade, child: _buildHeader()),
          ),
          Expanded(
            child: SlideTransition(
              position: _listSlide,
              child: FadeTransition(
                opacity: _listFade,
                child: Consumer<AppProvider>(
                  builder: (context, provider, _) {
                    final sessions = provider.sessionHistory;
                    // The session history can be long, so its cards are a
                    // lazy SliverList: only the cards on screen are built.
                    // The header is a separate sliver, which (unlike a
                    // ListView item) stays alive when scrolled away, so its
                    // card animations don't replay. Same look and spacing
                    // as the old scrolling Column.
                    final header = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 18),
                        _buildSummaryRow(_summaryFor(sessions)),
                        const SizedBox(height: 18),
                        _buildCategoryFilter(),
                        const SizedBox(height: 16),
                        _buildTodayExercises(),
                        const SizedBox(height: 18),
                        if (sessions.isNotEmpty) ...[
                          _buildSectionTitle('Session History', CupertinoIcons.clock),
                          const SizedBox(height: 12),
                        ] else ...[
                          _buildSectionTitle('Recommended', CupertinoIcons.star),
                          const SizedBox(height: 12),
                          _buildRecommendedList(),
                        ],
                      ],
                    );
                    return CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: readablePadding(
                            context,
                            const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          sliver: SliverToBoxAdapter(child: header),
                        ),
                        SliverPadding(
                          // 16 padding + the old trailing 16 gap.
                          padding: readablePadding(
                            context,
                            const EdgeInsets.fromLTRB(16, 0, 16, 32),
                          ),
                          sliver: SliverList.builder(
                            itemCount: sessions.length,
                            itemBuilder: (context, i) {
                              final session = sessions[i];
                              // Keyed by id so an expanded card stays with
                              // its session when a new one is added on top.
                              return _SessionCard(
                                key: ValueKey(session.id),
                                session: session,
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── HEADER ──────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: AppPalette.midTeal,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Exercise',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Track your recovery progress',
                        style: TextStyle(fontSize: 13, color: Colors.white60),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Search bar
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(CupertinoIcons.search, color: Colors.white60, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: TextField(
                        style: TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search exercises...',
                          hintStyle: TextStyle(color: Colors.white54, fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── SUMMARY ROW ─────────────────────────────────────────────────────────────
  Widget _buildSummaryRow(_HistorySummary summary) {
    final totalSessions = summary.sessions;
    final totalSets = summary.sets;
    final avgScore = summary.avgScore;

    return Row(
      children: [
        _summaryCard('Sessions', '$totalSessions', CupertinoIcons.calendar, const Color(0xFF23A8AA)),
        const SizedBox(width: 10),
        _summaryCard('Total Sets', '$totalSets', CupertinoIcons.repeat, const Color(0xFF4A90D9)),
        const SizedBox(width: 10),
        _summaryCard('Avg Score', '$avgScore%', CupertinoIcons.chart_bar, const Color(0xFF7C4DFF)),
      ],
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [_cardShadow(context, color, alpha: 0.12)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(height: 10),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: palette.textPrimary)),
            Text(label, style: TextStyle(fontSize: 11, color: palette.textMuted)),
          ],
        ),
      ),
    );
  }

  // ── CATEGORY FILTER ──────────────────────────────────────────────────────────
  Widget _buildCategoryFilter() {
    final palette = context.palette;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final selected = _selectedCategory == i;
          return GestureDetector(
            onTap: () => _selectCategory(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(colors: [primaryTeal, darkTeal])
                    : null,
                color: selected ? null : palette.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: selected
                        ? primaryTeal.withValues(alpha: 0.3)
                        : palette.shadow.withValues(alpha: context.isDarkMode ? 0.3 : 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _categories[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : palette.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── TODAY'S EXERCISES ────────────────────────────────────────────────────────
  Widget _buildTodayExercises() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("Today's Plan", CupertinoIcons.doc_text),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _filtered.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _ExerciseCard(item: _filtered[i], index: i),
          ),
        ),
      ],
    );
  }

  // ── RECOMMENDED LIST ─────────────────────────────────────────────────────────
  Widget _buildRecommendedList() {
    return Column(
      children: _filtered
          .map((item) => _ExerciseListTile(item: item))
          .toList(),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: primaryTeal),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.textPrimary),
        ),
      ],
    );
  }
}

// ── EXERCISE CARD (horizontal scroll) ────────────────────────────────────────
class _ExerciseCard extends StatefulWidget {
  final _ExerciseItem item;
  final int index;
  const _ExerciseCard({required this.item, required this.index});

  @override
  State<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<_ExerciseCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scale = Tween<double>(begin: 0.8, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    Future.delayed(Duration(milliseconds: 100 * widget.index), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: item.color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, size: 20, color: Colors.white),
            ),
            const Spacer(),
            Text(
              item.name,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              maxLines: 2,
            ),
            const SizedBox(height: 4),
            Text(
              '${item.sets} sets · ${item.reps} reps',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: item.progress,
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── EXERCISE LIST TILE ────────────────────────────────────────────────────────
class _ExerciseListTile extends StatelessWidget {
  final _ExerciseItem item;
  const _ExerciseListTile({required this.item});

  Color get _difficultyColor => switch (item.difficulty) {
        'Easy' => const Color(0xFF4CAF50),
        'Hard' => const Color(0xFFE53935),
        _ => const Color(0xFFFF9800),
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [_cardShadow(context, item.color)],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, size: 24, color: item.color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: palette.textPrimary)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(CupertinoIcons.clock, size: 12, color: palette.textFaint),
                    const SizedBox(width: 4),
                    Text(item.duration, style: TextStyle(fontSize: 11, color: palette.textMuted)),
                    const SizedBox(width: 10),
                    Icon(CupertinoIcons.repeat, size: 12, color: palette.textFaint),
                    const SizedBox(width: 4),
                    Text('${item.sets}×${item.reps}', style: TextStyle(fontSize: 11, color: palette.textMuted)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: item.progress,
                    backgroundColor: palette.surfaceMuted,
                    valueColor: AlwaysStoppedAnimation(item.color),
                    minHeight: 5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _difficultyColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.difficulty,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _difficultyColor),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: Text(item.name),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${item.sets} sets · ${item.reps} reps · ${item.duration}',
                            style: TextStyle(fontSize: 13, color: palette.textSecondary)),
                        const SizedBox(height: 8),
                        Text('Difficulty: ${item.difficulty}',
                            style: TextStyle(fontSize: 13, color: _difficultyColor, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: item.color,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Start'),
                      ),
                    ],
                  ),
                ),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: item.color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(CupertinoIcons.play_fill, size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── SESSION HISTORY CARD ──────────────────────────────────────────────────────
class _SessionCard extends StatelessWidget {
  final ExerciseSession session;
  const _SessionCard({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    // NaN-safe (0–1): a NaN score used to throw in toInt() below.
    final compliance = session.safeCompliance;
    final color = compliance >= 0.8
        ? const Color(0xFF23A8AA)
        : compliance >= 0.5
            ? Colors.orange
            : Colors.red;

    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [_cardShadow(context, color)],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: AppPalette.teal,
          collapsedIconColor: palette.textMuted,
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                '${(compliance * 100).toInt()}%',
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          title: Text(
            session.exerciseName,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: palette.textPrimary),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(CupertinoIcons.calendar, size: 11, color: palette.textFaint),
                const SizedBox(width: 4),
                Text(
                  DateFormat('MMM d, y').format(session.startTime),
                  style: TextStyle(fontSize: 11, color: palette.textMuted),
                ),
                const SizedBox(width: 10),
                Icon(CupertinoIcons.repeat, size: 11, color: palette.textFaint),
                const SizedBox(width: 4),
                Text(
                  '${session.completedSets}/${session.targetSets} sets',
                  style: TextStyle(fontSize: 11, color: palette.textMuted),
                ),
              ],
            ),
          ),
          children: [
            if (session.repComplianceScores.isNotEmpty) ...[
              Text('Rep Performance', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.textSecondary)),
              const SizedBox(height: 10),
              SizedBox(
                height: 120,
                child: BarChart(
                  BarChartData(
                    // Bad stored values (NaN, out of 0–1) are drawn as 0 /
                    // clamped instead of breaking the chart.
                    barGroups: session.repComplianceScores
                        .map((v) => v.isFinite ? v.clamp(0.0, 1.0) : 0.0)
                        .toList()
                        .asMap().entries.map((e) =>
                      BarChartGroupData(x: e.key, barRods: [
                        BarChartRodData(
                          toY: e.value * 100,
                          color: e.value >= 0.8 ? const Color(0xFF23A8AA) : e.value >= 0.5 ? Colors.orange : Colors.red,
                          width: 14,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ]),
                    ).toList(),
                    maxY: 100,
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: TextStyle(fontSize: 11, color: palette.textMuted)),
                      )),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) => Text('R${v.toInt() + 1}', style: TextStyle(fontSize: 11, color: palette.textMuted)),
                      )),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(color: palette.divider, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── DATA MODEL ────────────────────────────────────────────────────────────────
class _ExerciseItem {
  final String name, category, duration, difficulty;
  final int sets, reps;
  final IconData icon;
  final Color color;
  final double progress;

  const _ExerciseItem({
    required this.name,
    required this.category,
    required this.sets,
    required this.reps,
    required this.duration,
    required this.difficulty,
    required this.icon,
    required this.color,
    required this.progress,
  });
}
