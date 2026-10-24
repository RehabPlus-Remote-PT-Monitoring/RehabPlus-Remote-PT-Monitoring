// Layout tests for the restyled progress report: the key-number column
// rule, and the phone (one column) vs wide tablet (summary left, charts
// right) arrangement, with no overflow at either size.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rehabplus/core/app_theme.dart';
import 'package:rehabplus/core/diagnostic_logger.dart';
import 'package:rehabplus/services/app_provider.dart';
import 'package:rehabplus/screens/progress_report_screen.dart';
import 'package:rehabplus/widgets/report_key_numbers.dart';

Future<void> _pumpReport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppProvider>(
      create: (_) => AppProvider(),
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const ProgressReportScreen(initialDays: 30),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => DiagnosticLogger.I.setSink((_) {}));

  group('ReportKeyNumbers.columnsFor', () {
    test('phone widths use three columns', () {
      expect(ReportKeyNumbers.columnsFor(328, 6), 3);
    });

    test('four columns only when they fit and fill whole rows', () {
      // Wide enough, but 6 tiles would leave a half-empty row.
      expect(ReportKeyNumbers.columnsFor(800, 6), 3);
      expect(ReportKeyNumbers.columnsFor(800, 8), 4);
      // Fills rows, but tiles would be too narrow.
      expect(ReportKeyNumbers.columnsFor(400, 8), 3);
    });
  });

  testWidgets('phone: one column, charts before the breakdown', (tester) async {
    await _pumpReport(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);

    // Everything shares one left edge, and the per-exercise card comes
    // after the last chart.
    await tester.scrollUntilVisible(find.text('By exercise'), 200);
    final pain = tester.getTopLeft(find.text('Pain level'));
    final breakdown = tester.getTopLeft(find.text('By exercise'));
    expect(breakdown.dx, moreOrLessEquals(pain.dx));
    expect(breakdown.dy, greaterThan(pain.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape tablet: charts sit to the right of the numbers', (
    tester,
  ) async {
    await _pumpReport(tester, const Size(1290, 800));
    expect(tester.takeException(), isNull);

    final verdictX = tester.getTopLeft(find.text('Last 30 days')).dx;
    final chartX = tester.getTopLeft(find.text('Form score').last).dx;
    expect(chartX, greaterThan(verdictX + 300));
    // The breakdown stays in the left column.
    expect(tester.getTopLeft(find.text('By exercise')).dx, lessThan(chartX));
  });
}
