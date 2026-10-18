// Widget smoke tests for the progress UI: the report screen renders from the
// provider's sessions through the loader, logs opening and range changes,
// and the charts cope with empty and odd data.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rehabplus/core/diagnostic_logger.dart';
import 'package:rehabplus/services/app_provider.dart';
import 'package:rehabplus/services/progress_report.dart';
import 'package:rehabplus/screens/progress_report_screen.dart';
import 'package:rehabplus/widgets/progress_charts.dart';

void main() {
  final logger = DiagnosticLogger.I;

  setUp(() {
    logger.setSink((_) {});
    logger.clearBuffer();
  });

  testWidgets('report screen: empty history, range change is logged', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>(
        create: (_) => AppProvider(),
        child: const MaterialApp(home: ProgressReportScreen(initialDays: 30)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Progress Report'), findsOneWidget);
    expect(find.text('No sessions yet'), findsOneWidget);
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(
      logger.recent().where((e) => e.message == 'Screen opened'),
      hasLength(1),
    );

    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();
    expect(find.text('Last 7 days'), findsOneWidget);
    final change = logger.recent().lastWhere(
      (e) => e.message == 'Range changed',
    );
    expect(change.data, {'fromDays': 30, 'toDays': 7});
  });

  testWidgets('charts render with no data and with odd values', (tester) async {
    final empty = ProgressReport.build(
      const [],
      DateTime(2026, 10, 16),
      days: 7,
    );
    final odd = [
      ProgressPoint(
        start: DateTime(2026, 10, 16),
        days: 1,
        sessions: 2,
        formScore: double.nan,
        pain: 99,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              SessionsBarChart(points: empty.points),
              TrendLineChart.form(points: empty.points),
              TrendLineChart.pain(points: odd),
              TrendLineChart.form(points: odd),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Form: no points at all, and a NaN-only point, both show the message.
    expect(find.text('No data for this period yet'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
