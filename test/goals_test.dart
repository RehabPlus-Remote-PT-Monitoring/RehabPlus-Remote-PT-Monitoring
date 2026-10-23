import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/models/therapy_goal.dart';
import 'package:rehabplus/screens/goals_screen.dart';
import 'package:rehabplus/services/goal_service.dart';

Map<String, dynamic> goalDoc({
  String title = 'Walk 1 km without a cane',
  String? status = 'active',
  Object? progress = 40,
  DateTime? target,
  DateTime? achieved,
  DateTime? created,
}) =>
    {
      'title': title,
      'details': 'Daily walks around the block.',
      'status': ?status,
      'progress': ?progress,
      'targetDate': target == null ? null : Timestamp.fromDate(target),
      'achievedAt': achieved == null ? null : Timestamp.fromDate(achieved),
      'createdAt': created == null ? null : Timestamp.fromDate(created),
      'therapistName': 'Dr. Cruz',
    };

void main() {
  group('TherapyGoal.parse', () {
    test('reads a dashboard goal', () {
      final p = TherapyGoal.parse('g1', goalDoc(target: DateTime(2026, 12, 1)));
      expect(p.isOk, isTrue);
      final g = p.value!;
      expect(g.title, 'Walk 1 km without a cane');
      expect(g.status, GoalStatus.active);
      expect(g.progress, 40);
      expect(g.targetDate, DateTime(2026, 12, 1));
      expect(g.therapistName, 'Dr. Cruz');
    });

    test('a goal without a title is rejected', () {
      expect(TherapyGoal.parse('g1', goalDoc(title: '  ')).isOk, isFalse);
    });

    test('achieved goals always show 100%', () {
      final g = TherapyGoal.parse('g1', goalDoc(status: 'achieved', progress: 70)).value!;
      expect(g.progress, 100);
    });

    test('bad progress is clamped and reported; unknown status means active', () {
      final p = TherapyGoal.parse('g1', goalDoc(status: 'paused', progress: 250));
      expect(p.value!.progress, 100);
      expect(p.value!.status, GoalStatus.active);
      expect(p.repaired, contains('progress'));
    });

    test('isOverdue only for active goals past their target day', () {
      final now = DateTime(2026, 10, 24, 15);
      TherapyGoal goal(String status, DateTime target) =>
          TherapyGoal.parse('g', goalDoc(status: status, target: target)).value!;
      expect(goal('active', DateTime(2026, 10, 23)).isOverdue(now), isTrue);
      expect(goal('active', DateTime(2026, 10, 24)).isOverdue(now), isFalse);
      expect(goal('achieved', DateTime(2026, 10, 1)).isOverdue(now), isFalse);
    });
  });

  test('GoalService.parseGoals skips bad docs and sorts active, achieved, stopped', () {
    final goals = GoalService.parseGoals([
      MapEntry('stopped', goalDoc(title: 'Stopped', status: 'discontinued')),
      MapEntry('later', goalDoc(title: 'Later', target: DateTime(2026, 12, 1))),
      MapEntry('nodate', goalDoc(title: 'No date')),
      MapEntry('bad', {'title': 42}),
      MapEntry('soon', goalDoc(title: 'Soon', target: DateTime(2026, 11, 1))),
      MapEntry('done', goalDoc(title: 'Done', status: 'achieved', achieved: DateTime(2026, 9, 1))),
    ]);
    expect(goals.map((g) => g.title), ['Soon', 'Later', 'No date', 'Done', 'Stopped']);
  });

  group('GoalsScreen', () {
    Future<void> pump(WidgetTester tester, Stream<List<TherapyGoal>> goals) async {
      await tester.pumpWidget(MaterialApp(home: GoalsScreen(goals: goals)));
      await tester.pump();
    }

    testWidgets('lists goals with progress and status', (tester) async {
      final goals = GoalService.parseGoals([
        MapEntry('a', goalDoc(title: 'Climb stairs', progress: 60)),
        MapEntry('b', goalDoc(title: 'Full squat', status: 'achieved', achieved: DateTime(2026, 10, 3))),
      ]);
      await pump(tester, Stream.value(goals));
      expect(find.text('Climb stairs'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('Achieved'), findsOneWidget);
      expect(find.text('Achieved 3 Oct 2026'), findsOneWidget);
      expect(find.text('1 in progress · 1 achieved'), findsOneWidget);
    });

    testWidgets('empty list explains where goals come from', (tester) async {
      await pump(tester, Stream.value(const []));
      expect(find.text('No goals yet'), findsOneWidget);
    });

    testWidgets('a load error shows a message instead of spinning', (tester) async {
      final controller = StreamController<List<TherapyGoal>>();
      await pump(tester, controller.stream);
      controller.addError(Exception('offline'));
      await tester.pump();
      expect(find.text('Could not load your goals'), findsOneWidget);
      await controller.close();
    });
  });
}
