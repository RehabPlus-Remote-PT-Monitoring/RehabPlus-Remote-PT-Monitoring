// Regression tests for the second review pass over the remaining screens and
// widgets: double-tap guards, startup retry robustness, validation limits,
// diagnostic log events and the demo-link configuration.
//
// Everything here runs without Firebase: the screens under test either
// don't touch it on the tested path, or take injectable services.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/diagnostic_logger.dart';
import 'package:rehabplus/core/exercise_demo_videos.dart';
import 'package:rehabplus/models/exercise_model.dart';
import 'package:rehabplus/screens/app_lock_offer_screen.dart';
import 'package:rehabplus/screens/edit_profile_screen.dart';
import 'package:rehabplus/screens/forgot_password_screen.dart';
import 'package:rehabplus/screens/settings_screen.dart';
import 'package:rehabplus/screens/startup_error_screen.dart';
import 'package:rehabplus/services/app_lock_service.dart';
import 'package:rehabplus/services/profile_service.dart';
import 'package:rehabplus/widgets/exercise_demo_sheet.dart';
import 'package:rehabplus/widgets/profile_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// No fingerprint hardware.
class _NoBiometrics implements BiometricAuth {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<BiometricResult> authenticate(String reason) async =>
      BiometricResult.unavailable;
}

/// Log records with [message] since the buffer was last cleared.
List<DiagnosticEvent> _logged(String message) => DiagnosticLogger.I
    .recent(limit: DiagnosticLogger.bufferCapacity)
    .where((e) => e.message == message)
    .toList();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DiagnosticLogger.I.setSink(null); // keep test output quiet
    DiagnosticLogger.I.clearBuffer();
  });

  group('StartupErrorScreen', () {
    Future<void> pump(WidgetTester tester, Future<Widget> Function() retry) =>
        tester.pumpWidget(MaterialApp(home: StartupErrorScreen(onRetry: retry)));

    testWidgets('a retry that throws re-enables the button and is logged', (
      tester,
    ) async {
      var calls = 0;
      await pump(tester, () async {
        calls++;
        throw StateError('Firebase exploded');
      });

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      // Not stuck on "Trying again...": the patient can retry.
      expect(find.text('Try again'), findsOneWidget);
      expect(_logged('Startup retry crashed'), hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a successful retry moves on and logs the outcome', (
      tester,
    ) async {
      await pump(tester, () async => const Text('NEXT SCREEN'));

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('NEXT SCREEN'), findsOneWidget);
      final finished = _logged('Startup retry finished').single;
      expect(finished.data?['ok'], isTrue);
    });
  });

  group('AppLockOfferScreen', () {
    testWidgets('a double tap on "Not now" leaves only once', (tester) async {
      final lock = AppLockService(
        store: _MemoryStore(),
        biometrics: _NoBiometrics(),
        currentUid: () => 'patientA',
      );
      var built = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AppLockOfferScreen(
            uid: 'patientA',
            service: lock,
            next: () {
              built++;
              return const Text('DASHBOARD');
            },
          ),
        ),
      );

      // Two taps before any rebuild: the second used to run _notNow again.
      final notNow = find.text('Not now');
      await tester.tap(notNow);
      await tester.tap(notNow, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(built, 1);
      expect(_logged('Leaving the offer'), hasLength(1));
      expect(await lock.shouldOfferSetup('patientA'), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('ForgotPasswordScreen validation', () {
    Future<void> pumpForgot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ForgotPasswordScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('an over-long email is rejected before any network call', (
      tester,
    ) async {
      await pumpForgot(tester);

      // 255 characters: shaped like an e-mail, but longer than RFC 5321
      // allows. The old private check accepted it.
      final email = '${'a' * 243}@example.com';
      expect(email.length, 255);
      await tester.enterText(find.byType(TextField).at(0), email);
      await tester.tap(find.text('Set New Password'));
      await tester.pump();

      expect(find.text('Enter the email address on your account.'),
          findsOneWidget);
      expect(_logged('Reset blocked by validation').single.data?['field'],
          'email');
      expect(_logged('Password reset requested'), isEmpty);
    });

    testWidgets('a missing temporary password is named in the log', (
      tester,
    ) async {
      await pumpForgot(tester);

      await tester.enterText(find.byType(TextField).at(0), 'pat@example.com');
      await tester.tap(find.text('Set New Password'));
      await tester.pump();

      expect(_logged('Reset blocked by validation').single.data?['field'],
          'temporaryPassword');
    });
  });

  group('EditProfileScreen', () {
    ProfileData profile({String phone = '555-0100', String dob = ''}) =>
        ProfileData(
          name: 'Alex Test',
          email: 'alex@example.com',
          phone: phone,
          dob: dob,
          condition: 'Knee',
        );

    Future<void> pump(WidgetTester tester, ProfileData initial) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: EditProfileScreen(initial: initial)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('phone length follows ProfileService (the Firestore rule)', (
      tester,
    ) async {
      final tooLong = '1' * (ProfileService.maxPhoneLength + 1);
      await pump(tester, profile(phone: tooLong, dob: 'May 12, 1990'));

      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pump();

      expect(
        find.text(
          'Must be ${ProfileService.maxPhoneLength} characters or fewer',
        ),
        findsOneWidget,
      );
      expect(_logged('Save blocked by validation'), hasLength(1));
    });

    testWidgets('a double tap on the date of birth opens one calendar', (
      tester,
    ) async {
      await pump(tester, profile(dob: 'May 12, 1990'));

      final dob = find.text('May 12, 1990');
      await tester.tap(dob);
      await tester.tap(dob, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('a stored date outside the calendar range does not crash', (
      tester,
    ) async {
      // showDatePicker asserts initialDate <= lastDate (today).
      await pump(tester, profile(dob: 'January 1, 2999'));

      await tester.tap(find.text('January 1, 2999'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });
  });

  group('SettingsScreen', () {
    testWidgets('a double tap on Reminder time opens one clock', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final tile = find.text('Reminder time');
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.tap(tile, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsOneWidget);
    });
  });

  group('ProfileAvatar decode failures', () {
    test('are logged once per photo, not on every rebuild', () {
      final broken = Uint8List.fromList([1, 2, 3]);
      final other = Uint8List.fromList([4, 5, 6]);
      final error = Exception('bad image');

      expect(ProfileAvatar.reportUndecodablePhoto(broken, error, null), isTrue);
      expect(ProfileAvatar.reportUndecodablePhoto(broken, error, null), isFalse);
      expect(ProfileAvatar.reportUndecodablePhoto(other, error, null), isTrue);

      final events = _logged('Profile photo could not be decoded');
      expect(events, hasLength(2));
      // Only the size, never the image itself.
      expect(events.first.data, {'bytes': 3});
    });
  });

  group('Exercise demos', () {
    test('every demo video and link is a valid HTTPS URL', () {
      final urls = [
        ...exerciseDemoVideoUrls.values,
        ...exerciseDemoLinks.values.map((link) => link.url),
      ];
      for (final url in urls) {
        final uri = Uri.tryParse(url);
        expect(uri, isNotNull, reason: url);
        expect(uri!.scheme, 'https', reason: url);
        expect(uri.host, isNotEmpty, reason: url);
      }
    });

    testWidgets('opening the sheet logs what it can show', (tester) async {
      final config = availableExercises.firstWhere(
        (c) => c.type == ExerciseType.kneeExtension,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => ExerciseDemoSheet.show(context, config),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final opened = _logged('Demo sheet opened').single;
      expect(opened.data, {
        'type': 'kneeExtension',
        'hasVideo': false,
        'hasLink': true,
      });
    });
  });
}
