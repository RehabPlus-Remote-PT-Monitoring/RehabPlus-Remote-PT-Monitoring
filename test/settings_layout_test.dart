// Layout checks for Settings and Settings > App Lock (iOS inset grouped
// lists): Settings keeps one column on a phone and splits into two columns
// on a wide tablet, and both pages build in light and dark mode.
//
// No Firebase here: Settings loads its notification choices through a
// try/catch that falls back to the defaults, and the camera permission and
// app version plugins fail the same safe way in a widget test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/app_theme.dart';
import 'package:rehabplus/screens/app_lock_settings_screen.dart';
import 'package:rehabplus/screens/settings_screen.dart';
import 'package:rehabplus/services/app_lock_service.dart';

/// In-memory stand-in for the Keystore-backed PIN storage.
class _MemoryStore implements AppLockStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// A phone without fingerprint hardware.
class _NoBiometrics implements BiometricAuth {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<BiometricResult> authenticate(String reason) async =>
      BiometricResult.unavailable;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app(Widget home, {Brightness brightness = Brightness.light}) =>
      MaterialApp(theme: buildAppTheme(brightness), home: home);

  /// Sets the test window to [size] (logical pixels) for one test.
  void useScreen(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  Offset headerAt(WidgetTester tester, String header) =>
      tester.getTopLeft(find.text(header));

  testWidgets('Settings: one column on a phone, in the usual order', (
    tester,
  ) async {
    // Tall, so every section is laid out without scrolling.
    useScreen(tester, const Size(390, 3000));
    await tester.pumpWidget(app(const SettingsScreen()));
    await tester.pump();

    final exercise = headerAt(tester, 'EXERCISE FEEDBACK');
    final notifications = headerAt(tester, 'NOTIFICATIONS');
    final support = headerAt(tester, 'SUPPORT');
    expect(notifications.dx, exercise.dx);
    expect(notifications.dy, greaterThan(exercise.dy));
    expect(support.dy, greaterThan(notifications.dy));
    expect(find.text('App lock'), findsOneWidget);
    expect(find.text('Report a problem'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('Settings: two columns on a landscape tablet ($brightness)', (
      tester,
    ) async {
      useScreen(tester, const Size(1290, 2000));
      await tester.pumpWidget(
        app(const SettingsScreen(), brightness: brightness),
      );
      await tester.pump();

      final exercise = headerAt(tester, 'EXERCISE FEEDBACK');
      final notifications = headerAt(tester, 'NOTIFICATIONS');
      // Side by side: same top, notifications in the right-hand column.
      expect(notifications.dy, closeTo(exercise.dy, 1));
      expect(notifications.dx, greaterThan(exercise.dx + 300));
      expect(find.text('Report a problem'), findsOneWidget);
      expect(find.text('Countdown'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('App Lock: rows, footnote and disabled Change PIN', (
    tester,
  ) async {
    useScreen(tester, const Size(390, 1600));
    final service = AppLockService(
      store: _MemoryStore(),
      biometrics: _NoBiometrics(),
      currentUid: () => 'patientA',
    );
    await tester.pumpWidget(
      app(AppLockSettingsScreen(service: service), brightness: Brightness.dark),
    );
    await tester.pump();

    expect(find.text('PIN lock'), findsOneWidget);
    expect(find.text('Change PIN'), findsOneWidget);
    expect(find.text('Unlock with fingerprint'), findsOneWidget);
    expect(find.textContaining('Forgot PIN'), findsOneWidget);

    // No PIN yet: tapping Change PIN must not open the PIN check.
    await tester.tap(find.text('Change PIN'));
    await tester.pumpAndSettle();
    expect(find.text('Change PIN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
