// "Share a session" in the therapist chat: the message text built from a
// session, and the sheet that picks one. Same cases as the iPhone branch
// (test/chat_features_test.dart and test/ios_review_test.dart there), so
// both platforms send identical summaries.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/diagnostic_logger.dart';
import 'package:rehabplus/models/chat.dart';
import 'package:rehabplus/models/session.dart';
import 'package:rehabplus/services/chat_session_share.dart';
import 'package:rehabplus/widgets/chat_session_share_sheet.dart';

bool _logged(String message) =>
    DiagnosticLogger.I.recent(limit: 200).any((e) => e.message == message);

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// A button that opens the share sheet for [sessions] and hands the picked
/// session to [onPicked].
Widget _opener(
  List<ExerciseSession> sessions,
  void Function(ExerciseSession?) onPicked,
) => _host(
  Builder(
    builder: (context) => TextButton(
      onPressed: () async =>
          onPicked(await showChatSessionShareSheet(context, sessions)),
      child: const Text('open'),
    ),
  ),
);

ExerciseSession _plain(int i) => ExerciseSession(
  id: 's$i',
  exerciseId: 'e$i',
  exerciseName: 'Exercise $i',
  startTime: DateTime(2026, 11, 7 - i, 8),
  targetReps: 10,
  targetSets: 1,
);

void main() {
  setUp(DiagnosticLogger.I.clearBuffer);

  group('sessionShareText', () {
    ExerciseSession session({
      int completed = 10,
      int target = 10,
      List<double> scores = const [1, 1, 1, 0.68],
      int? pain = 2,
      String? painNote,
      bool endedEarly = false,
      String name = 'Knee Extension',
    }) => ExerciseSession(
      id: 'x',
      exerciseId: 'kneeExtension',
      exerciseName: name,
      startTime: DateTime(2026, 11, 7, 8, 15),
      targetReps: target,
      targetSets: 1,
      completedReps: completed,
      repComplianceScores: scores,
      painLevel: pain,
      painNote: painNote,
      endedEarly: endedEarly,
    );

    test('name, time, reps, accuracy and pain', () {
      expect(
        sessionShareText(session()),
        'Session summary - Knee Extension (Nov 7, 8:15 AM)\n'
        '10/10 reps, accuracy 92%, pain 2/10',
      );
    });

    test('ended early and the pain note are included', () {
      expect(
        sessionShareText(
          session(completed: 4, endedEarly: true, painNote: 'Sharp at the end'),
        ),
        'Session summary - Knee Extension (Nov 7, 8:15 AM)\n'
        '4/10 reps, accuracy 92%, pain 2/10 - ended early\n'
        'Pain note: Sharp at the end',
      );
    });

    test('missing accuracy and pain are left out, not shown as 0', () {
      expect(
        sessionShareText(session(scores: const [], pain: null)),
        'Session summary - Knee Extension (Nov 7, 8:15 AM)\n10/10 reps',
      );
    });

    test('a blank pain note is left out', () {
      expect(
        sessionShareText(session(painNote: '   ')),
        isNot(contains('note')),
      );
    });

    test('never longer than a message may be', () {
      final text = sessionShareText(
        session(name: 'N' * 100, painNote: 'x' * 5000),
      );
      expect(text.length, lessThanOrEqualTo(ChatMessage.maxTextLength));
      expect(text, startsWith('Session summary - N'));
    });
  });

  group('share sheet', () {
    testWidgets('lists the 5 newest sessions and returns the tap', (
      tester,
    ) async {
      final sessions = [for (var i = 0; i < 7; i++) _plain(i)];
      // Tall enough for all five rows (the sheet scrolls on short phones).
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      ExerciseSession? picked;
      await tester.pumpWidget(_opener(sessions, (s) => picked = s));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Exercise 0'), findsOneWidget);
      expect(find.text('Exercise 4'), findsOneWidget);
      expect(find.text('Exercise 5'), findsNothing);

      await tester.tap(find.text('Exercise 2'));
      await tester.pumpAndSettle();
      expect(picked?.id, 's2');
    });

    testWidgets('with no sessions says so', (tester) async {
      await tester.pumpWidget(_opener(const [], (_) {}));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No sessions yet'), findsOneWidget);
    });

    testWidgets('a double tap does not close the page under the sheet', (
      tester,
    ) async {
      ExerciseSession? picked;
      await tester.pumpWidget(_opener([_plain(0)], (s) => picked = s));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final tileWidget = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Exercise 0'),
          matching: find.byType(ListTile),
        ),
      );
      // Two taps in the same frame, before the sheet's exit animation can
      // block input.
      tileWidget.onTap!();
      tileWidget.onTap!();
      await tester.pumpAndSettle();

      expect(picked?.id, 's0');
      expect(find.text('open'), findsOneWidget);
      expect(_logged('Repeated share tap ignored'), isTrue);
    });
  });
}
