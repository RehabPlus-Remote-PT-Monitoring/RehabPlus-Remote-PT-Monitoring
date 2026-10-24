import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../models/prescription.dart';
import '../services/app_provider.dart';
import '../services/progress_report.dart';
import '../services/progress_report_loader.dart';
import '../services/progress_stats.dart';
import '../widgets/progress_charts.dart';
import '../core/responsive.dart';

const _primaryTeal = AppPalette.teal;
const _darkTeal = AppPalette.darkTeal;

/// Semantic colours (good / info / caution / warning). The light-mode
/// shades are too dark to read on the dark page, so dark mode uses lighter
/// tints of the same hues.
Color _goodColor(BuildContext context) =>
    context.isDarkMode ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
Color _infoColor(BuildContext context) =>
    context.isDarkMode ? const Color(0xFF4DD0E1) : _darkTeal;
Color _cautionColor(BuildContext context) =>
    context.isDarkMode ? const Color(0xFFFFD54F) : const Color(0xFFF9A825);
Color _warningColor(BuildContext context) =>
    context.isDarkMode ? const Color(0xFFFF8A65) : const Color(0xFFD84315);

/// Colours and icon for each verdict. The pale pastel chip backgrounds
/// glare on a dark page, so dark mode tints the foreground colour instead.
({Color fg, Color bg, IconData icon}) _statusStyle(
  BuildContext context,
  ProgressStatus s,
) {
  final dark = context.isDarkMode;
  final palette = context.palette;
  Color tint(Color fg, Color lightBg) =>
      dark ? fg.withValues(alpha: 0.16) : lightBg;
  return switch (s) {
    ProgressStatus.great => (
      fg: _goodColor(context),
      bg: tint(_goodColor(context), const Color(0xFFE8F5E9)),
      icon: Icons.emoji_events_outlined,
    ),
    ProgressStatus.onTrack => (
      fg: _infoColor(context),
      bg: tint(_infoColor(context), const Color(0xFFE0F4F4)),
      icon: Icons.trending_up_rounded,
    ),
    ProgressStatus.needsAttention => (
      fg: _warningColor(context),
      bg: tint(_warningColor(context), const Color(0xFFFFF3E0)),
      icon: Icons.error_outline_rounded,
    ),
    ProgressStatus.noData => (
      fg: palette.textSecondary,
      bg: palette.surfaceMuted,
      icon: Icons.hourglass_empty_rounded,
    ),
  };
}

Widget _findingRow(BuildContext context, Finding f) {
  final (icon, color) = switch (f.kind) {
    FindingKind.good => (Icons.check_circle_rounded, _goodColor(context)),
    FindingKind.info => (Icons.info_outline_rounded, _infoColor(context)),
    FindingKind.warning => (
      Icons.warning_amber_rounded,
      _warningColor(context),
    ),
  };
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            f.text,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: context.palette.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}

BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
  color: context.palette.surface,
  borderRadius: BorderRadius.circular(22),
  boxShadow: [
    BoxShadow(
      // A teal glow in light mode; on the dark page a plain black shadow
      // (a coloured glow there just looks like a smudge).
      color: context.isDarkMode
          ? context.palette.shadow.withValues(alpha: 0.3)
          : _primaryTeal.withValues(alpha: 0.08),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ],
);

/// Compact "How you're doing" card for the Home screen: verdict, the top
/// findings, a form-score chart and a link to the full report.
class ProgressSummaryCard extends StatelessWidget {
  const ProgressSummaryCard({
    super.key,
    required this.report,
    required this.onOpenReport,
  });

  final ProgressReport report;
  final VoidCallback onOpenReport;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasForm = report.points.any((p) => p.formScore != null);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "How you're doing",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              _StatusChip(status: report.status),
            ],
          ),
          const SizedBox(height: 14),
          for (final f in report.findings.take(2)) _findingRow(context, f),
          if (report.status != ProgressStatus.noData) ...[
            const SizedBox(height: 6),
            Text(
              hasForm ? 'Form score' : 'Sessions',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            hasForm
                ? TrendLineChart.form(points: report.points, height: 120)
                : SessionsBarChart(points: report.points, height: 120),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onOpenReport,
              style: TextButton.styleFrom(
                foregroundColor: _infoColor(context),
                // Slightly stronger in dark mode so the button still shows.
                backgroundColor: _primaryTeal.withValues(
                  alpha: context.isDarkMode ? 0.16 : 0.08,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.insights_rounded, size: 18),
              label: const Text(
                'See full report',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder with the summary card's look, shown only while the first
/// report for a very long history is built in the background.
class ProgressSummaryLoading extends StatelessWidget {
  const ProgressSummaryLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(context),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: _primaryTeal,
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final ProgressStatus status;

  @override
  Widget build(BuildContext context) {
    final style = _statusStyle(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 14, color: style.fg),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: style.fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// The full progress report: verdict and findings, key numbers, charts for
/// sessions, form and pain, and a per-exercise breakdown.
class ProgressReportScreen extends StatefulWidget {
  const ProgressReportScreen({
    super.key,
    this.initialDays = 30,
    this.prescriptions = const [],
  });

  final int initialDays;

  /// Active prescriptions, for "followed X% of your plan".
  final List<Prescription> prescriptions;

  @override
  State<ProgressReportScreen> createState() => _ProgressReportScreenState();
}

class _ProgressReportScreenState extends State<ProgressReportScreen> {
  static const _tag = 'ProgressReportScreen';
  static const _periods = [7, 30, 90];
  late int _days = _periods.contains(widget.initialDays)
      ? widget.initialDays
      : 30;

  /// Builds the report once per change of the sessions, plan, day or
  /// period (not on every rebuild); long histories off the UI thread.
  late final ProgressReportLoader _loader = ProgressReportLoader(
    owner: 'report_screen',
    onBackgroundResult: () {
      if (mounted) setState(() {});
    },
  );

  @override
  void initState() {
    super.initState();
    DiagnosticLogger.I.info(_tag, 'Screen opened', {
      'initialDays': widget.initialDays,
      'days': _days,
      'prescriptions': widget.prescriptions.length,
    });
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  void _selectPeriod(int days) {
    if (days == _days) return;
    DiagnosticLogger.I.info(_tag, 'Range changed', {
      'fromDays': _days,
      'toDays': days,
    });
    setState(() => _days = days);
  }

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<AppProvider>().sessionHistory;
    final view = _loader.reportFor(
      sessions,
      days: _days,
      prescriptions: widget.prescriptions,
    );
    final report = view.report;
    final grouping = switch (ProgressReport.bucketDaysFor(_days)) {
      1 => 'per day',
      final n => 'per $n days',
    };

    return Scaffold(
      backgroundColor: context.palette.background,
      body: Column(
        children: [
          _header(),
          Expanded(
            child: ListView(
              padding: readablePadding(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
              children: [
                SegmentedButton<int>(
                  segments: [
                    for (final d in _periods)
                      ButtonSegment(value: d, label: Text('$d days')),
                  ],
                  selected: {_days},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _selectPeriod(s.first),
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: _primaryTeal,
                    selectedForegroundColor: Colors.white,
                    foregroundColor: _infoColor(context),
                  ),
                ),
                const SizedBox(height: 14),
                if (report == null)
                  _placeholder(failed: view.failed)
                else
                  // Dimmed only while a long history is rebuilt in the
                  // background; small histories never see this.
                  AnimatedOpacity(
                    opacity: view.isStale ? 0.55 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: _reportBody(report, grouping),
                  ),
                const SizedBox(height: 8),
                Text(
                  'This report is worked out from your exercise sessions. Your '
                  'therapist sees the same results. It is not a medical '
                  'assessment; ask your therapist about anything that worries you.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: context.palette.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportBody(ProgressReport report, String grouping) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _verdictCard(report),
        const SizedBox(height: 14),
        _numbers(report),
        const SizedBox(height: 14),
        _chartCard(
          'Sessions',
          'How often you exercised, $grouping',
          SessionsBarChart(points: report.points),
        ),
        _chartCard(
          'Form score',
          'How closely your reps matched good form (higher is better)',
          TrendLineChart.form(points: report.points),
        ),
        _chartCard(
          'Pain level',
          'What you reported after sessions, 0 to 10 (lower is better)',
          TrendLineChart.pain(points: report.points),
        ),
        _exerciseCard(report),
      ],
    );
  }

  /// First build of a very long history (spinner), or a failed build
  /// (already logged with its stack trace).
  Widget _placeholder({required bool failed}) {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(context),
      child: Center(
        child: failed
            ? Text(
                "Couldn't work out your report. Please try again later.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: context.palette.textSecondary),
              )
            : const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _primaryTeal,
                ),
              ),
      ),
    );
  }

  Widget _header() {
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
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Progress Report',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'How your recovery is going',
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _verdictCard(ProgressReport r) {
    final style = _statusStyle(context, r.status);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: style.bg,
                  shape: BoxShape.circle,
                ),
                child: Icon(style.icon, color: style.fg, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.status.label,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: style.fg,
                      ),
                    ),
                    Text(
                      'Last ${r.days} days',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final f in r.findings) _findingRow(context, f),
        ],
      ),
    );
  }

  Widget _numbers(ProgressReport r) {
    final palette = context.palette;
    String pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';
    final tiles = <(String, String, IconData)>[
      ('Sessions', '${r.sessions}', Icons.fitness_center_rounded),
      ('Active days', '${r.activeDays}', Icons.calendar_month_rounded),
      ('Time', ProgressStats.formatDuration(r.time), Icons.timer_outlined),
      ('Reps done', pct(r.repCompletion), Icons.repeat_rounded),
      (
        'Form score',
        r.formScore == null ? '—' : '${r.formScore!.round()}%',
        Icons.accessibility_new_rounded,
      ),
      (
        r.adherence == null ? 'Avg pain' : 'Plan followed',
        r.adherence == null
            ? (r.pain == null ? '—' : '${r.pain!.toStringAsFixed(1)}/10')
            : pct(r.adherence),
        r.adherence == null
            ? Icons.healing_outlined
            : Icons.assignment_turned_in_outlined,
      ),
    ];
    return GridView.count(
      crossAxisCount: 3,
      // Without this the grid adds the status-bar height as top padding.
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.05,
      children: [
        for (final (label, value, icon) in tiles)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: _cardDecoration(context),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: _primaryTeal),
                const SizedBox(height: 6),
                FittedBox(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 11, color: palette.textMuted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _chartCard(String title, String subtitle, Widget chart) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: palette.textMuted),
          ),
          const SizedBox(height: 14),
          chart,
        ],
      ),
    );
  }

  Widget _exerciseCard(ProgressReport r) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'By exercise',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          if (r.exercises.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'No exercises done in this period.',
                style: TextStyle(fontSize: 12, color: palette.textMuted),
              ),
            ),
          // Keyed by name: the order changes between periods.
          for (final e in r.exercises)
            KeyedSubtree(key: ValueKey(e.name), child: _exerciseRow(e)),
        ],
      ),
    );
  }

  Widget _exerciseRow(ExerciseSummary e) {
    final palette = context.palette;
    final form = e.formScore;
    final formColor = form == null
        ? palette.textFaint
        : form >= 80
        ? _goodColor(context)
        : form >= 60
        ? _cautionColor(context)
        : _warningColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Text(
                '${e.sessions}× · '
                '${e.pain == null ? 'no pain logged' : 'pain ${e.pain!.toStringAsFixed(1)}/10'}',
                style: TextStyle(fontSize: 11, color: palette.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (form ?? 0) / 100,
                    minHeight: 8,
                    backgroundColor: palette.surfaceMuted,
                    valueColor: AlwaysStoppedAnimation(formColor),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 40,
                child: Text(
                  form == null ? '—' : '${form.round()}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: formColor,
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
