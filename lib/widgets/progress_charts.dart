import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../services/progress_report.dart';

// Performance: both charts build their fl_chart data object (bars/spots,
// titles, grid, tooltips) once and keep it until the points or the size
// change. The points list comes from a cached ProgressReport, so its
// identity only changes when the report does; a rebuild of the parent (a
// tab tap, a clock tick, a fade-in) reuses the same data object, and
// fl_chart sees nothing new to lay out or animate.

const _teal = Color(0xFF23A8AA);
const _axisStyle = TextStyle(fontSize: 9, color: Colors.black45);

/// Bottom-axis label for a chart point: weekday letter for daily points,
/// otherwise the first day of the group ("12/10").
String _label(ProgressPoint p) => p.days == 1
    ? DateFormat('E').format(p.start).substring(0, 2)
    : DateFormat('d/M').format(p.start);

/// Show every label when there are few points, every other one otherwise.
bool _showLabel(int i, int count) => count <= 8 || i.isEven || i == count - 1;

FlTitlesData _titles(
  List<ProgressPoint> points, {
  required double leftInterval,
  required String Function(double) left,
}) {
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 30,
        interval: leftInterval,
        getTitlesWidget: (v, _) => Text(left(v), style: _axisStyle),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 22,
        interval: 1,
        getTitlesWidget: (v, _) {
          final i = v.round();
          if (i < 0 || i >= points.length || v != i.toDouble()) {
            return const SizedBox.shrink();
          }
          if (!_showLabel(i, points.length)) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_label(points[i]), style: _axisStyle),
          );
        },
      ),
    ),
  );
}

FlGridData _grid(double interval) => FlGridData(
  show: true,
  drawVerticalLine: false,
  horizontalInterval: interval,
  getDrawingHorizontalLine: (_) =>
      FlLine(color: Colors.grey.shade200, strokeWidth: 1),
);

/// Sessions per day (or per group of days).
class SessionsBarChart extends StatefulWidget {
  const SessionsBarChart({super.key, required this.points, this.height = 150});

  final List<ProgressPoint> points;
  final double height;

  @override
  State<SessionsBarChart> createState() => _SessionsBarChartState();
}

class _SessionsBarChartState extends State<SessionsBarChart> {
  late BarChartData _data = _buildData(widget.points);

  @override
  void didUpdateWidget(SessionsBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.points, widget.points)) {
      _data = _buildData(widget.points);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: widget.height, child: BarChart(_data));
  }

  static BarChartData _buildData(List<ProgressPoint> points) {
    final most = points.fold(0, (m, p) => p.sessions > m ? p.sessions : m);
    final maxY = (most < 3 ? 3 : most + 1).toDouble();
    final barWidth = points.length <= 7
        ? 16.0
        : (points.length <= 8 ? 12.0 : 9.0);
    return BarChartData(
      maxY: maxY,
      minY: 0,
      barGroups: [
        for (var i = 0; i < points.length; i++)
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: points[i].sessions.toDouble(),
                width: barWidth,
                color: _teal,
                borderRadius: BorderRadius.circular(5),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY,
                  color: Colors.grey.shade100,
                ),
              ),
            ],
          ),
      ],
      titlesData: _titles(
        points,
        leftInterval: maxY <= 4 ? 1 : (maxY / 4).ceilToDouble(),
        left: (v) => '${v.toInt()}',
      ),
      gridData: _grid(maxY <= 4 ? 1 : (maxY / 4).ceilToDouble()),
      borderData: FlBorderData(show: false),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => Colors.black87,
          getTooltipItem: (group, _, rod, _) => BarTooltipItem(
            '${rod.toY.toInt()} session${rod.toY == 1 ? '' : 's'}',
            const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ),
    );
  }
}

/// A line over the period for one measure (form score or pain). Points with
/// no data are skipped, so the line joins the days that have data.
class TrendLineChart extends StatefulWidget {
  const TrendLineChart({
    super.key,
    required this.points,
    required this.value,
    required this.maxY,
    required this.color,
    required this.format,
    this.interval,
    this.height = 150,
  });

  /// Form score: 0–100, pain: 0–10.
  const TrendLineChart.form({
    super.key,
    required this.points,
    this.height = 150,
  }) : value = _formOf,
       maxY = 100,
       color = _teal,
       format = _percent,
       interval = 25;

  const TrendLineChart.pain({
    super.key,
    required this.points,
    this.height = 150,
  }) : value = _painOf,
       maxY = 10,
       color = const Color(0xFFFF6B35),
       format = _outOfTen,
       interval = 2;

  static double? _formOf(ProgressPoint p) => p.formScore;
  static double? _painOf(ProgressPoint p) => p.pain;
  static String _percent(double v) => '${v.toInt()}%';
  static String _outOfTen(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

  final List<ProgressPoint> points;
  final double? Function(ProgressPoint) value;
  final double maxY;
  final Color color;
  final String Function(double) format;
  final double? interval;
  final double height;

  @override
  State<TrendLineChart> createState() => _TrendLineChartState();
}

class _TrendLineChartState extends State<TrendLineChart> {
  /// Null when no point has a value (the "no data" message is shown).
  late LineChartData? _data = _buildData(widget);

  @override
  void didUpdateWidget(TrendLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // value/format are static functions and the colours constants, so in
    // practice only the points change; compare all inputs to be safe.
    if (!identical(oldWidget.points, widget.points) ||
        oldWidget.value != widget.value ||
        oldWidget.maxY != widget.maxY ||
        oldWidget.color != widget.color ||
        oldWidget.format != widget.format ||
        oldWidget.interval != widget.interval) {
      _data = _buildData(widget);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text(
            'No data for this period yet',
            style: TextStyle(fontSize: 12, color: Colors.black38),
          ),
        ),
      );
    }
    return SizedBox(height: widget.height, child: LineChart(data));
  }

  static LineChartData? _buildData(TrendLineChart w) {
    final points = w.points;
    final maxY = w.maxY;
    final color = w.color;
    final spots = [
      for (var i = 0; i < points.length; i++)
        // Non-finite values would break the chart's layout maths; the
        // report never produces them, but the widget doesn't rely on it.
        if (w.value(points[i]) case final v? when v.isFinite)
          FlSpot(i.toDouble(), v.clamp(0, maxY).toDouble()),
    ];
    if (spots.isEmpty) return null;
    final step = w.interval ?? maxY / 4;
    return LineChartData(
      minX: 0,
      maxX: (points.length - 1).toDouble().clamp(1, double.infinity),
      minY: 0,
      maxY: maxY,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: color,
          barWidth: 3,
          dotData: FlDotData(
            show: true,
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
              radius: 3.5,
              color: Colors.white,
              strokeWidth: 2.5,
              strokeColor: color,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.25),
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
      titlesData: _titles(points, leftInterval: step, left: w.format),
      gridData: _grid(step),
      borderData: FlBorderData(show: false),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.black87,
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(
                maxY == 100
                    ? '${s.y.round()}%'
                    : '${s.y.toStringAsFixed(1)}/10',
                const TextStyle(color: Colors.white, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}

