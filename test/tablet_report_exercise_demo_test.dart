// Tablet layout tests for the Progress Report, the exercise list and the
// App Demo: no overflow on a phone or a landscape tablet, one column on the
// phone (same order as before) and two columns side by side when wide.
//
// The exercise page itself loads the plan from Firebase, so its card grid
// (ExerciseCardGrid with the real AnimatedExerciseCard) is tested directly.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rehabplus/core/diagnostic_logger.dart';
import 'package:rehabplus/models/exercise_model.dart';
import 'package:rehabplus/screens/demo_screen.dart';
import 'package:rehabplus/screens/exercise_page.dart';
import 'package:rehabplus/screens/progress_report_screen.dart';
import 'package:rehabplus/services/app_provider.dart';

const _phone = Size(400, 800);
const _tablet = Size(1280, 800);

/// Same as the dashboard's page area on a landscape tablet (1280 minus the
/// 240 dp sidebar), where the exercise list actually lives.
const _tabletPage = Size(1040, 800);

/// Smallest width that still gets two columns.
const _narrowTablet = Size(900, 800);

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Loads the real Roboto font from the Flutter SDK, so text in these tests
/// is as wide as on a device. The default test font draws every glyph as a
/// full square, which makes "1 Set | 10 Reps" look about twice as long as
/// it really is (and would hide or invent cut-off text).
///
/// The test runner (flutter_tester) lives in
/// `<flutter>/bin/cache/artifacts/engine/<platform>/`, and the fonts in
/// `<flutter>/bin/cache/artifacts/material_fonts/`. Returns false if they
/// can't be found; the layout checks still run, the text checks are skipped.
Future<bool> _loadRoboto() async {
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final fonts = Directory('${artifacts.path}/material_fonts');
  if (!fonts.existsSync()) return false;
  final loader = FontLoader('Roboto');
  for (final name in ['Regular', 'Medium', 'Bold']) {
    final file = File('${fonts.path}/Roboto-$name.ttf');
    if (!file.existsSync()) return false;
    final bytes = file.readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
  return true;
}

void main() {
  var realFont = false;

  setUpAll(() async {
    realFont = await _loadRoboto();
  });

  setUp(() {
    DiagnosticLogger.I.setSink((_) {});
    DiagnosticLogger.I.clearBuffer();
  });

  group('ProgressReportScreen', () {
    Future<void> pumpReport(WidgetTester tester, Size size) async {
      _setSize(tester, size);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>(
          create: (_) => AppProvider(),
          child: const MaterialApp(home: ProgressReportScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    testWidgets('phone: one column in the original order', (tester) async {
      await pumpReport(tester, _phone);

      final verdict = tester.getTopLeft(find.text('Last 30 days'));
      final numbers = tester.getTopLeft(find.text('Active days'));
      expect(verdict.dy, lessThan(numbers.dy));

      // The breakdown is further down; scroll to it.
      await tester.scrollUntilVisible(
        find.text('By exercise'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final pain = tester.getTopLeft(find.text('Pain level'));
      final byExercise = tester.getTopLeft(find.text('By exercise'));
      expect(byExercise.dy, greaterThan(pain.dy));
      expect(byExercise.dx, closeTo(pain.dx, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet: charts left, verdict and breakdown right', (
      tester,
    ) async {
      await pumpReport(tester, _tablet);

      final chart = tester.getTopLeft(find.text('Sessions').last);
      final verdict = tester.getTopLeft(find.text('Last 30 days'));
      final byExercise = tester.getTopLeft(find.text('By exercise'));

      expect(verdict.dx, greaterThan(chart.dx + 300));
      expect(byExercise.dx, greaterThan(chart.dx + 300));
      expect(byExercise.dy, greaterThan(verdict.dy));
      // Both columns start near the top, side by side.
      expect(verdict.dy, lessThan(300));

      // The header title lines up with the content column, not the edge.
      final title = tester.getTopLeft(find.text('Progress Report'));
      expect(title.dx, greaterThan((1280 - 1100) / 2));
    });
  });

  group('ExerciseCardGrid', () {
    Future<void> pumpGrid(WidgetTester tester, Size size) async {
      _setSize(tester, size);
      final configs = availableExercises.take(5).toList();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  ExerciseCardGrid(
                    children: [
                      for (var i = 0; i < configs.length; i++)
                        AnimatedExerciseCard(
                          index: i,
                          config: configs[i],
                          progress: i.isEven ? 0.5 : null,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      // Let the staggered entrance animations finish.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    /// No reps / camera-view line is cut off with an ellipsis.
    void expectNoTruncatedText(WidgetTester tester) {
      if (!realFont) return;
      for (final element in find.byType(RichText).evaluate()) {
        final paragraph = element.renderObject! as RenderParagraph;
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: 'cut off: ${paragraph.text.toPlainText()}',
        );
      }
    }

    testWidgets('phone: one card per row', (tester) async {
      await pumpGrid(tester, _phone);
      final cards = find.byType(AnimatedExerciseCard);
      final first = tester.getTopLeft(cards.at(0));
      final second = tester.getTopLeft(cards.at(1));
      expect(second.dx, first.dx);
      expect(second.dy, greaterThan(first.dy));
      expectNoTruncatedText(tester);
    });

    for (final size in [_tablet, _tabletPage, _narrowTablet]) {
      testWidgets('${size.width.toInt()} wide: two cards per row', (
        tester,
      ) async {
        await pumpGrid(tester, size);
        final cards = find.byType(AnimatedExerciseCard);
        final first = tester.getRect(cards.at(0));
        final second = tester.getRect(cards.at(1));
        final third = tester.getRect(cards.at(2));
        final last = tester.getRect(cards.at(4));

        expect(second.top, first.top);
        expect(second.left, greaterThan(first.right));
        expect(third.top, greaterThan(first.top));
        // A lone last card keeps the same width as the rest.
        expect(last.width, closeTo(first.width, 0.5));
        expectNoTruncatedText(tester);
      });
    }
  });

  group('DemoScreen', () {
    Future<void> pumpDemo(WidgetTester tester, Size size) async {
      _setSize(tester, size);
      await tester.pumpWidget(const MaterialApp(home: DemoScreen()));
      // The "Live" dot pulses forever, so pump a fixed time, not settle.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    }

    testWidgets('phone: one column, features first', (tester) async {
      await pumpDemo(tester, _phone);
      final features = tester.getTopLeft(find.text('Key Features'));
      final videos = tester.getTopLeft(find.text('Exercise Videos'));
      expect(videos.dy, greaterThan(features.dy));
      expect(videos.dx, features.dx);

      await tester.scrollUntilVisible(
        find.text('Sample Progress'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final demo = tester.getTopLeft(find.text('Exercise Demo'));
      final stats = tester.getTopLeft(find.text('Sample Progress'));
      expect(stats.dy, greaterThan(demo.dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet: two columns side by side', (tester) async {
      await pumpDemo(tester, _tablet);
      final features = tester.getTopLeft(find.text('Key Features'));
      final demo = tester.getTopLeft(find.text('Exercise Demo'));
      final stats = tester.getTopLeft(find.text('Sample Progress'));

      expect(demo.dx, greaterThan(features.dx + 300));
      // Both columns start at the top of the page.
      expect((demo.dy - features.dy).abs(), lessThan(40));
      expect(stats.dx, greaterThan(features.dx + 300));

      // Header content lines up with the columns.
      final title = tester.getTopLeft(find.text('App Demo'));
      expect(title.dx, greaterThan((1280 - 1100) / 2));

      // Steps still work in the right column.
      await tester.tap(find.text('Next Step'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Step 2 of 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
