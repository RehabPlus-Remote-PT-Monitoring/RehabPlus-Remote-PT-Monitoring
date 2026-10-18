import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/screens/app_lock_offer_screen.dart';
import 'package:rehabplus/screens/app_lock_screen.dart';
import 'package:rehabplus/services/app_lock_service.dart';

/// In-memory stand-in for the Keystore-backed storage.
class MemoryStore implements AppLockStore {
  final Map<String, String> values = {};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw Exception('disk full');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class FakeBiometrics implements BiometricAuth {
  bool available = true;
  BiometricResult next = BiometricResult.success;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BiometricResult> authenticate(String reason) async {
    prompts++;
    return next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryStore store;
  late FakeBiometrics bio;
  late DateTime now;
  late bool signedIn;

  AppLockService newService() => AppLockService(
    store: store,
    biometrics: bio,
    clock: () => now,
    isSignedIn: () => signedIn,
  );

  setUp(() {
    store = MemoryStore();
    bio = FakeBiometrics();
    now = DateTime(2026, 10, 18, 9);
    signedIn = true;
  });

  group('PinHasher', () {
    test('verifies the right PIN only', () {
      final record = PinHasher.create('2580');
      expect(PinHasher.verify('2580', record), isTrue);
      expect(PinHasher.verify('2581', record), isFalse);
      expect(record, isNot(contains('2580')));
    });

    test('same PIN gets a different salt each time', () {
      expect(PinHasher.create('2580'), isNot(PinHasher.create('2580')));
    });

    test('rejects malformed records instead of crashing', () {
      for (final bad in ['', 'v2\$1\$a\$b', 'v1\$x\$a\$b', 'v1\$10\$%%\$b']) {
        expect(PinHasher.isValidRecord(bad), isFalse, reason: bad);
        expect(PinHasher.verify('2580', bad), isFalse);
      }
    });

    test('hashing is fast enough for the UI thread', () {
      final watch = Stopwatch()..start();
      PinHasher.create('2580');
      // Generous bound for slow CI; a phone in release mode is faster.
      expect(watch.elapsedMilliseconds, lessThan(1500));
    });
  });

  group('PIN rules', () {
    test('only 4 digits are valid', () {
      expect(AppLockService.isValidPin('2580'), isTrue);
      for (final bad in ['', '258', '25801', '25a0', ' 258']) {
        expect(AppLockService.isValidPin(bad), isFalse, reason: bad);
      }
    });

    test('obvious PINs are refused when choosing one', () {
      for (final weak in ['0000', '7777', '1234', '6789', '4321', '9876']) {
        expect(AppLockService.weakPinReason(weak), isNotNull, reason: weak);
      }
      for (final ok in ['2580', '1357', '0912', '1123']) {
        expect(AppLockService.weakPinReason(ok), isNull, reason: ok);
      }
    });
  });

  group('AppLockService', () {
    test('off by default; setPin turns it on and survives a reload', () async {
      final lock = newService();
      await lock.load();
      expect(lock.isEnabled, isFalse);

      await lock.setPin('2580');
      expect(lock.isEnabled, isTrue);

      final reloaded = newService();
      await reloaded.load();
      expect(reloaded.isEnabled, isTrue);
      expect(await reloaded.verifyPin('2580'), PinCheck.correct);
    });

    test('malformed PIN is refused', () async {
      final lock = newService();
      expect(() => lock.setPin('12'), throwsArgumentError);
    });

    test('a failed save is reported and leaves the lock off', () async {
      final lock = newService();
      store.failWrites = true;
      await expectLater(lock.setPin('2580'), throwsException);
      expect(lock.isEnabled, isFalse);
    });

    test('wrong PINs are counted across restarts, then sign-out', () async {
      final lock = newService();
      await lock.setPin('2580');
      for (var i = 1; i < AppLockService.maxAttempts - 1; i++) {
        expect(await lock.verifyPin('1111'), PinCheck.wrong);
      }
      // Killing the app doesn't reset the count.
      final reloaded = newService();
      await reloaded.load();
      expect(reloaded.attemptsLeft, 2);
      expect(await reloaded.verifyPin('1111'), PinCheck.wrong);
      expect(await reloaded.verifyPin('1111'), PinCheck.tooManyAttempts);
      // Even the right PIN no longer works.
      expect(await reloaded.verifyPin('2580'), PinCheck.tooManyAttempts);
    });

    test('a correct PIN resets the wrong-PIN count', () async {
      final lock = newService();
      await lock.setPin('2580');
      await lock.verifyPin('1111');
      await lock.verifyPin('2580');
      expect(lock.attemptsLeft, AppLockService.maxAttempts);
    });

    test('locks at startup only when on and signed in', () async {
      final lock = newService();
      expect(lock.lockIfEnabled('startup'), isFalse);
      await lock.setPin('2580');
      signedIn = false;
      expect(lock.lockIfEnabled('startup'), isFalse);
      signedIn = true;
      expect(lock.lockIfEnabled('startup'), isTrue);
      expect(lock.isLocked, isTrue);
      expect(lock.needsLockScreen, isFalse, reason: 'main.dart shows it');
      expect(await lock.verifyPin('2580'), PinCheck.correct);
      expect(lock.isLocked, isFalse);
    });

    test('relocks after a minute away, not after a short trip', () async {
      final lock = newService();
      await lock.setPin('2580');
      lock.arm();

      lock.didChangeAppLifecycleState(AppLifecycleState.hidden);
      now = now.add(const Duration(seconds: 59));
      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(lock.isLocked, isFalse);

      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 1));
      lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(lock.isLocked, isTrue);
      expect(lock.needsLockScreen, isTrue);
      lock.dispose();
    });

    test('the fingerprint prompt (inactive) does not count as away', () {
      final lock = newService();
      lock.arm();
      lock.didChangeAppLifecycleState(AppLifecycleState.inactive);
      now = now.add(const Duration(minutes: 5));
      lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(lock.isLocked, isFalse);
      lock.dispose();
    });

    test('before arm(), coming back never locks (splash/startup)', () async {
      final lock = newService();
      await lock.setPin('2580');
      lock.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 5));
      lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(lock.isLocked, isFalse);
    });

    test('fingerprint unlocks and is remembered', () async {
      final lock = newService();
      await lock.setPin('2580');
      await lock.setBiometricsEnabled(true);
      lock.lockIfEnabled('startup');
      expect(
        await lock.authenticateWithBiometrics(reason: 'test'),
        BiometricResult.success,
      );
      expect(lock.isLocked, isFalse);

      final reloaded = newService();
      await reloaded.load();
      expect(reloaded.biometricsEnabled, isTrue);
    });

    test('a failed fingerprint keeps it locked', () async {
      final lock = newService();
      await lock.setPin('2580');
      lock.lockIfEnabled('startup');
      bio.next = BiometricResult.failed;
      await lock.authenticateWithBiometrics(reason: 'test');
      expect(lock.isLocked, isTrue);
    });

    test('disable (sign-out) forgets everything', () async {
      final lock = newService();
      await lock.setPin('2580');
      await lock.setBiometricsEnabled(true);
      await lock.verifyPin('1111');
      await lock.disable(reason: 'sign-out');
      expect(store.values, isEmpty);
      expect(lock.isEnabled, isFalse);
      expect(lock.biometricsEnabled, isFalse);
      expect(lock.lockIfEnabled('startup'), isFalse);
    });

    test('setup is offered after sign-in until set up or dismissed', () async {
      final lock = newService();
      expect(await lock.shouldOfferSetup('patientA'), isTrue);

      await lock.dismissSetupOffer('patientA');
      expect(await lock.shouldOfferSetup('patientA'), isFalse);
      // Another patient on the same phone still gets the offer.
      expect(await lock.shouldOfferSetup('patientB'), isTrue);

      // "Not now" survives sign-out (which only clears the PIN).
      await lock.disable(reason: 'sign-out');
      expect(await lock.shouldOfferSetup('patientA'), isFalse);

      await lock.setPin('2580');
      expect(await lock.shouldOfferSetup('patientB'), isFalse);
    });

    test('an unreadable stored record turns the lock off', () async {
      store.values['lock_pin'] = 'garbage';
      final lock = newService();
      await lock.load();
      expect(lock.isEnabled, isFalse);
    });
  });

  group('screens', () {
    Future<void> enter(WidgetTester tester, String pin) async {
      for (final d in pin.split('')) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('setup: two matching PINs save it', (tester) async {
      final lock = newService();
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PinSetupScreen(service: lock),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await enter(tester, '1234');
      expect(find.textContaining('too easy'), findsOneWidget);

      await enter(tester, '2580');
      expect(find.text('Enter the same PIN again'), findsOneWidget);
      await enter(tester, '2581');
      expect(find.textContaining('didn\'t match'), findsOneWidget);

      await enter(tester, '2580');
      await enter(tester, '2580');
      await tester.runAsync(() async {}); // let the save finish
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(lock.isEnabled, isTrue);
    });

    Future<void> showOffer(WidgetTester tester, AppLockService lock) =>
        tester.pumpWidget(
          MaterialApp(
            home: AppLockOfferScreen(
              uid: 'patientA',
              service: lock,
              next: () => const Text('DASHBOARD'),
            ),
          ),
        );

    testWidgets('offer: "Not now" goes to the dashboard and is remembered', (
      tester,
    ) async {
      final lock = newService();
      await showOffer(tester, lock);
      expect(find.text('Protect your health data'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(await lock.shouldOfferSetup('patientA'), isFalse);
      expect(lock.isEnabled, isFalse);
    });

    testWidgets('offer: PIN, then fingerprint, then the dashboard', (
      tester,
    ) async {
      final lock = newService();
      await showOffer(tester, lock);

      await tester.tap(find.text('Set up PIN'));
      await tester.pumpAndSettle();
      await enter(tester, '2580');
      await enter(tester, '2580');
      await tester.pumpAndSettle();
      expect(lock.isEnabled, isTrue);
      expect(find.text('Unlock with your fingerprint?'), findsOneWidget);

      await tester.tap(find.text('Use fingerprint'));
      await tester.pumpAndSettle();
      expect(bio.prompts, 1);
      expect(lock.biometricsEnabled, isTrue);
      expect(find.text('DASHBOARD'), findsOneWidget);
    });

    testWidgets('offer: no fingerprint on the phone skips that step', (
      tester,
    ) async {
      final lock = newService();
      bio.available = false;
      await showOffer(tester, lock);

      await tester.tap(find.text('Set up PIN'));
      await tester.pumpAndSettle();
      await enter(tester, '2580');
      await enter(tester, '2580');
      await tester.pumpAndSettle();
      expect(lock.isEnabled, isTrue);
      expect(lock.biometricsEnabled, isFalse);
      expect(find.text('DASHBOARD'), findsOneWidget);
    });

    testWidgets('confirm: wrong PIN shows tries left, right PIN pops true', (
      tester,
    ) async {
      final lock = newService();
      await tester.runAsync(() => lock.setPin('2580'));
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AppLockScreen.confirm(service: lock),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await enter(tester, '1111');
      expect(find.text('Wrong PIN. 4 tries left.'), findsOneWidget);

      await enter(tester, '2580');
      expect(result, isTrue);
    });
  });
}
