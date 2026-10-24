import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/ios_segmented_control.dart';
import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../models/prescription.dart';
import '../services/app_provider.dart';
import '../services/progress_report.dart';
import '../services/progress_report_loader.dart';
import '../services/progress_stats.dart';
import '../widgets/ios_page.dart';
import '../widgets/pressable.dart';
import '../widgets/progress_charts.dart';
import '../widgets/report_key_numbers.dart';
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
      icon: CupertinoIcons.rosette,
    ),
    ProgressStatus.onTrack => (
      fg: _infoColor(context),
      bg: tint(_infoColor(context), const Color(0xFFE0F4F4)),
      icon: CupertinoIcons.arrow_up_right,
    ),
    ProgressStatus.needsAttention => (
      fg: _warningColor(context),
      bg: tint(_warningColor(context), const Color(0xFFFFF3E0)),
      icon: CupertinoIcons.exclamationmark_circle,
    ),
    ProgressStatus.noData => (
      fg: palette.textSecondary,
      bg: palette.surfaceMuted,
      icon: CupertinoIcons.hourglass,
    ),
  };
}

/// One finding: an icon (its shape tells good / info / warning apart, not
/// only its colour) and the sentence.
Widget _findingRow(BuildContext context, Finding f, {TextStyle? style}) {
  final (icon, color) = switch (f.kind) {
    FindingKind.good => (CupertinoIcons.checkmark_circle_fill, _goodColor(context)),
    FindingKind.info => (CupertinoIcons.info_circle, _infoColor(context)),
    FindingKind.warning => (
      CupertinoIcons.exclamationmark_triangle,
      _warningColor(context),
    ),
  };
  final textStyle =
      style ??
      Theme.of(context).textTheme.bodySmall?.copyWith(
        color: context.palette.textPrimary,
      );
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Lines the icon up with the first line of text.
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(f.text, style: textStyle)),
      ],
    ),
  );
}

/// The plain iOS card: surface colour, rounded corners, no shadow and no
/// gradient (Apple Health / Fitness summaries rely on the grey page behind
/// the white cards for separation, not on shadows).
BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
  color: context.palette.surface,
  borderRadius: BorderRadius.circular(16),
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
    final text = Theme.of(context).textTheme;
    final hasForm = report.points.any((p) => p.formScore != null);
    // The whole card opens the report (a big target, like a Health
    // summary card); the button at the bottom stays as the obvious way in.
    // Taps on the chart go to the chart's tooltip, not to the card.
    return Pressable(
      onTap: onOpenReport,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "How you're doing",
                    style: text.titleMedium?.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                _StatusChip(status: report.status),
              ],
            ),
            const SizedBox(height: 12),
            for (final f in report.findings.take(2)) _findingRow(context, f),
            if (report.status != ProgressStatus.noData) ...[
              const SizedBox(height: 6),
              Text(
                hasForm ? 'Form score' : 'Sessions',
                style: text.labelMedium?.copyWith(
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
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(CupertinoIcons.graph_square, size: 18),
                label: const Text(
                  'See full report',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
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
          child: CircularProgressIndicator.adaptive(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation(_primaryTeal),
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
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
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

    return IosPage(
      title: 'Progress',
      previousPageTitle: 'Home',
      // Wide enough for the two-column layout on a landscape tablet.
      maxWidth: adaptiveMaxWidth(context),
      children: [
        // The period sits right under the large title, like the D/W/M/Y
        // control at the top of an Apple Health chart.
        IosSegmentedControl<int>(
          options: {for (final d in _periods) d: '$d days'},
          value: _days,
          onChanged: _selectPeriod,
        ),
        const SizedBox(height: 16),
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
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w400,
            color: context.palette.textMuted,
          ),
        ),
      ],
    );
  }

  /// Gap between the cards of the report.
  static const double _cardGap = 12;

  /// [cards] with a [_cardGap] after each one.
  List<Widget> _spaced(List<Widget> cards) => [
    for (final card in cards) ...[card, const SizedBox(height: _cardGap)],
  ];

  /// Phone: one column, read top to bottom (verdict, findings, numbers,
  /// then the charts, then the per-exercise details).
  ///
  /// Wide (isTwoColumn): the summary on the left (verdict, findings,
  /// numbers, per-exercise breakdown) and the charts on the right, so the
  /// trends sit next to the numbers they explain instead of a screen below.
  Widget _reportBody(ProgressReport report, String grouping) {
    final twoColumns = isTwoColumn(context);
    // Taller charts when they have half a landscape tablet to themselves.
    final chartHeight = twoColumns ? 190.0 : 150.0;

    final summary = <Widget>[
      _verdictCard(report),
      if (report.findings.isNotEmpty) _findingsCard(report),
      _numbers(report),
    ];
    final charts = <Widget>[
      _chartCard(
        'Sessions',
        'How often you exercised, $grouping',
        SessionsBarChart(points: report.points, height: chartHeight),
      ),
      _chartCard(
        'Form score',
        'How closely your reps matched good form (higher is better)',
        TrendLineChart.form(points: report.points, height: chartHeight),
      ),
      _chartCard(
        'Pain level',
        'What you reported after sessions, 0 to 10 (lower is better)',
        TrendLineChart.pain(points: report.points, height: chartHeight),
      ),
    ];
    final breakdown = _exerciseCard(report);

    if (twoColumns) {
      return AdaptiveColumns(
        left: _spaced([...summary, breakdown]),
        right: _spaced(charts),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _spaced([...summary, ...charts, breakdown]),
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.palette.textSecondary,
                ),
              )
            : const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator.adaptive(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(_primaryTeal),
                ),
              ),
      ),
    );
  }

  /// The verdict, big: a coloured icon AND the word, so the meaning never
  /// depends on colour alone.
  Widget _verdictCard(ProgressReport r) {
    final style = _statusStyle(context, r.status);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(context),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: style.bg,
              shape: BoxShape.circle,
            ),
            child: Icon(style.icon, color: style.fg, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.status.label,
                  style: text.headlineMedium?.copyWith(color: style.fg),
                ),
                const SizedBox(height: 2),
                Text(
                  'Last ${r.days} days',
                  style: text.bodySmall?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// What the report noticed, as a short list of one-line sentences.
  Widget _findingsCard(ProgressReport r) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Highlights',
            style: text.titleMedium?.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: 10),
          for (final f in r.findings)
            _findingRow(
              context,
              f,
              style: text.bodyMedium?.copyWith(color: palette.textPrimary),
            ),
        ],
      ),
    );
  }

  Widget _numbers(ProgressReport r) {
    String pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';
    final tiles = <ReportNumber>[
      ReportNumber(
        label: 'Sessions',
        value: '${r.sessions}',
        icon: CupertinoIcons.flame,
      ),
      ReportNumber(
        label: 'Active days',
        value: '${r.activeDays}',
        icon: CupertinoIcons.calendar,
      ),
      ReportNumber(
        label: 'Time',
        value: ProgressStats.formatDuration(r.time),
        icon: CupertinoIcons.timer,
      ),
      ReportNumber(
        label: 'Reps done',
        value: pct(r.repCompletion),
        icon: CupertinoIcons.repeat,
      ),
      ReportNumber(
        label: 'Form score',
        value: r.formScore == null ? '—' : '${r.formScore!.round()}%',
        icon: Icons.accessibility_new_rounded,
      ),
      // Plan adherence when the patient has a plan, average pain otherwise.
      if (r.adherence == null)
        ReportNumber(
          label: 'Avg pain',
          value: r.pain == null ? '—' : '${r.pain!.toStringAsFixed(1)}/10',
          icon: CupertinoIcons.bandage,
        )
      else
        ReportNumber(
          label: 'Plan followed',
          value: pct(r.adherence),
          icon: CupertinoIcons.doc_checkmark,
        ),
    ];
    return ReportKeyNumbers(tiles: tiles);
  }

  Widget _chartCard(String title, String subtitle, Widget chart) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.titleMedium?.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: text.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 14),
          chart,
        ],
      ),
    );
  }

  Widget _exerciseCard(ProgressReport r) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'By exercise',
            style: text.titleMedium?.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: 12),
          if (r.exercises.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'No exercises done in this period.',
                style: text.bodySmall?.copyWith(color: palette.textSecondary),
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
    final text = Theme.of(context).textTheme;
    final form = e.formScore;
    // The bar's colour follows the score, and the score is always written
    // next to it, so the colour is never the only signal.
    final formColor = form == null
        ? palette.textFaint
        : form >= 80
        ? _goodColor(context)
        : form >= 60
        ? _cautionColor(context)
        : _warningColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  e.name,
                  style: text.titleSmall?.copyWith(color: palette.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${e.sessions}× · '
                '${e.pain == null ? 'no pain logged' : 'pain ${e.pain!.toStringAsFixed(1)}/10'}',
                style: text.labelSmall?.copyWith(
                  fontWeight: FontWeight.w400,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
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
                width: 44,
                child: Text(
                  form == null ? '—' : '${form.round()}%',
                  textAlign: TextAlign.right,
                  style: text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: form == null ? palette.textMuted : palette.textPrimary,
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
