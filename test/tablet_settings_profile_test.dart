// Settings and Profile on a phone (one column) and a landscape tablet
// (two columns).
//
// Both screens build without Firebase: Settings catches the failed
// notification-prefs load and the missing camera/version plugins and shows
// its defaults; Profile only reads AppProvider, which gets fakes here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rehabplus/core/diagnostic_logger.dart';
import 'package:rehabplus/models/session.dart';
import 'package:rehabplus/screens/edit_profile_screen.dart' show ProfileData;
import 'package:rehabplus/screens/profile_screen.dart';
import 'package:rehabplus/screens/settings_screen.dart';
import 'package:rehabplus/services/app_provider.dart';
import 'package:rehabplus/services/notification_service.dart';
import 'package:rehabplus/services/profile_service.dart';
import 'package:rehabplus/services/session_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Size _phone = Size(400, 800);
const Size _tablet = Size(1280, 800);

/// Keeps sessions in memory instead of Firestore.
class _MemoryStorage extends SessionStorage {
  @override
  Future<List<ExerciseSession>> fetchSessions() async => [];

  @override
  Future<void> saveSession(ExerciseSession session) async {}
}

/// No Firestore profile; the test sets one with updateProfile().
class _NoProfiles extends ProfileService {
  @override
  Future<ProfileData?> load() async => null;
}

/// Ignores the "session completed" notification.
class _QuietNotifications extends NotificationService {
  @override
  void addSessionCompleted(ExerciseSession s) {}
}

void _setScreenSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpSettings(WidgetTester tester, Size size) async {
  _setScreenSize(tester, size);
  await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
  // Let the async loads in initState (prefs, camera, version) settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Pumps Profile the way the dashboard shows it, with one finished session
/// so the Exercise Breakdown card is there too.
Future<void> _pumpProfile(WidgetTester tester, Size size) async {
  _setScreenSize(tester, size);
  final provider = AppProvider(
    storage: _MemoryStorage(),
    profiles: _NoProfiles(),
    notifications: _QuietNotifications(),
    currentUid: () => 'patient-1',
    signOutHandler: () async {},
  );
  addTearDown(provider.dispose);
  provider.updateProfile(
    const ProfileData(
      name: 'Alex Test',
      email: 'alex@example.com',
      phone: '555-0100',
      dob: '1990-01-01',
      condition: 'Knee',
    ),
  );
  await provider.recordCompletedSession(
    ExerciseSession(
      id: 's1',
      exerciseId: 'kneeExtension',
      exerciseName: 'Knee Extension',
      startTime: DateTime(2026, 10, 1, 9),
      targetReps: 10,
      targetSets: 1,
      painLevel: 2,
    ),
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<AppProvider>.value(
      value: provider,
      child: const MaterialApp(home: Scaffold(body: ProfileScreen())),
    ),
  );
  await tester.pump();
}

/// Top-left corner of the card whose heading is [title]: the nearest
/// Container around the heading that casts a shadow.
Offset _cardTopLeft(WidgetTester tester, String title) {
  final card = find.ancestor(
    of: find.text(title),
    matching: find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration && decoration.boxShadow != null;
    }),
  );
  return tester.getTopLeft(card.first);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DiagnosticLogger.I.setSink(null); // keep test output quiet
  });

  group('Settings', () {
    testWidgets('phone: one column in the usual order, no overflow', (
      tester,
    ) async {
      await _pumpSettings(tester, _phone);
      expect(tester.takeException(), isNull);

      final exercise = _cardTopLeft(tester, 'Exercise feedback');
      final appearance = _cardTopLeft(tester, 'Appearance');
      expect(appearance.dx, exercise.dx);
      expect(appearance.dy, greaterThan(exercise.dy));
    });

    testWidgets('tablet: two top-aligned columns', (tester) async {
      await _pumpSettings(tester, _tablet);
      expect(tester.takeException(), isNull);

      final left = _cardTopLeft(tester, 'Exercise feedback');
      final right = _cardTopLeft(tester, 'Appearance');
      expect(right.dx, greaterThan(left.dx));
      expect(right.dy, left.dy);

      // Nothing went missing: the last sections are still there.
      await tester.scrollUntilVisible(find.text('App version'), 200);
      expect(find.text('Report a problem'), findsOneWidget);
      expect(find.text('Clinic reminders'), findsOneWidget);
    });

    testWidgets('tablet: header lines up with the cards', (tester) async {
      await _pumpSettings(tester, _tablet);
      // Content is 1100 wide on a 1280 screen: 90 inset each side, plus
      // the header's own 8 px and the list's 16 px padding.
      final back = tester.getTopLeft(find.byIcon(Icons.arrow_back_ios));
      expect(back.dx, greaterThanOrEqualTo(90));
      expect(_cardTopLeft(tester, 'Exercise feedback').dx, 90 + 16);
    });
  });

  group('Profile', () {
    testWidgets('phone: one column in the usual order, no overflow', (
      tester,
    ) async {
      await _pumpProfile(tester, _phone);
      expect(tester.takeException(), isNull);

      final personal = _cardTopLeft(tester, 'Personal Info');
      final breakdown = _cardTopLeft(tester, 'Exercise Breakdown');
      expect(breakdown.dx, personal.dx);
      expect(breakdown.dy, greaterThan(personal.dy));
    });

    testWidgets('tablet: two top-aligned columns under the stats', (
      tester,
    ) async {
      await _pumpProfile(tester, _tablet);
      expect(tester.takeException(), isNull);

      final left = _cardTopLeft(tester, 'Personal Info');
      final right = _cardTopLeft(tester, 'Exercise Breakdown');
      expect(right.dx, greaterThan(left.dx));
      expect(right.dy, left.dy);

      // The stats row spans both columns, above them.
      final stats = tester.getRect(
        find
            .ancestor(of: find.text('Sessions'), matching: find.byType(Row))
            .first,
      );
      expect(stats.bottom, lessThan(left.dy));
      expect(stats.width, greaterThan(900));

      // Every entry is still reachable.
      for (final label in ['My Goals', 'Settings', 'Privacy & Legal']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.scrollUntilVisible(find.text('Sign Out'), 200);
      expect(find.text('Sign Out'), findsOneWidget);
    });
  });
}
