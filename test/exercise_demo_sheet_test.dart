// The "How to do it" link on an exercise card opens the demo sheet. The sheet
// shows the outside "Open video" card only when the video's creator has
// consented (authorConsent). Otherwise, or with no demo at all, it shows the
// "coming soon" note.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/exercise_demo_videos.dart';
import 'package:rehabplus/models/exercise_model.dart';
import 'package:rehabplus/screens/exercise_page.dart';
import 'package:rehabplus/widgets/exercise_demo_sheet.dart';

/// Loads the real Roboto font from the Flutter SDK (see
/// tablet_report_exercise_demo_test.dart): the default test font is much
/// wider, so layout checks need the real one.
Future<void> _loadRoboto() async {
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final fonts = Directory('${artifacts.path}/material_fonts');
  if (!fonts.existsSync()) return;
  final loader = FontLoader('Roboto');
  for (final name in ['Regular', 'Medium', 'Bold']) {
    final file = File('${fonts.path}/Roboto-$name.ttf');
    if (!file.existsSync()) return;
    loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await loader.load();
}

// Has an outside demo link with creator consent, so it shows.
final _withLink = availableExercises.firstWhere(
  (c) => c.type == ExerciseType.kneeExtension,
);

// Has no demo at all, so the sheet shows the "coming soon" note.
final _noVideo = availableExercises.firstWhere(
  (c) => c.type == ExerciseType.forwardPush,
);

void main() {
  setUpAll(_loadRoboto);

  Future<void> pumpCard(WidgetTester tester, ExerciseConfig config) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              ExerciseCardGrid(
                children: [AnimatedExerciseCard(index: 0, config: config)],
              ),
            ],
          ),
        ),
      ),
    );
    // Let the card's entrance animation finish.
    await tester.pumpAndSettle();
  }

  testWidgets('a video with creator consent shows the Open video card', (tester) async {
    await pumpCard(tester, _withLink);

    await tester.tap(find.text('How to do it'));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseDemoSheet), findsOneWidget);
    expect(find.text(_withLink.title), findsWidgets);
    expect(find.text('Watch the demo'), findsOneWidget);
    expect(find.text('Open video'), findsOneWidget);
    expect(find.text('Video by Physitrack'), findsOneWidget);
    expect(find.text('Demo video coming soon.'), findsNothing);
    expect(find.text('Start exercise'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an exercise with no demo shows the coming-soon note', (tester) async {
    await pumpCard(tester, _noVideo);

    await tester.tap(find.text('How to do it'));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseDemoSheet), findsOneWidget);
    expect(find.text('Demo video coming soon.'), findsOneWidget);
    expect(find.text('Open video'), findsNothing);
    expect(find.text('Start exercise'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the link does not start the exercise', (tester) async {
    await pumpCard(tester, _withLink);
    await tester.tap(find.text('How to do it'));
    await tester.pumpAndSettle();

    // The sheet is up, and the card's own tap did not push the pose screen:
    // the exercise page's card grid is still underneath.
    expect(find.byType(ExerciseDemoSheet), findsOneWidget);
    expect(find.byType(ExerciseCardGrid), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('every outside demo link is HTTPS and every exercise has one except forwardPush', () {
    for (final link in exerciseDemoLinks.values) {
      expect(Uri.parse(link.url).scheme, 'https', reason: link.url);
    }
    for (final type in ExerciseType.values) {
      if (type == ExerciseType.forwardPush) {
        expect(exerciseDemoLinks.containsKey(type), isFalse);
      } else {
        expect(exerciseDemoLinks.containsKey(type), isTrue, reason: type.name);
      }
    }
  });
}
