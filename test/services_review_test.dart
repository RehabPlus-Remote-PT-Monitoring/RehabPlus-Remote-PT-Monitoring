// Tests for the fixes made in the services/models review pass: races
// between sign-out and in-flight work, PIN hashing compatibility, consent
// records that only exist locally, and session fields the rules refuse.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/models/session.dart';
import 'package:rehabplus/services/app_lock_service.dart';
import 'package:rehabplus/services/consent_service.dart';

/// In-memory lock storage whose reads can be held until [release]d, so a
/// test can change who is signed in while a load is half-way.
class GatedStore implements AppLockStore {
  final Map<String, String> values = {};
  Completer<void>? gate;

  void hold() => gate = Completer<void>();
  void release() => gate?.complete();

  @override
  Future<String?> read(String key) async {
    final pending = gate;
    if (pending != null) await pending.future;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class NoBiometrics implements BiometricAuth {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<BiometricResult> authenticate(String reason) async =>
      BiometricResult.unavailable;
}

/// The PIN hash exactly as the first release computed it (a new list per
/// round). Records already stored on patients' phones use this.
List<int> legacyHash(String pin, List<int> salt, int rounds) {
  var digest = sha256.convert([...salt, ...utf8.encode(pin)]).bytes;
  for (var i = 1; i < rounds; i++) {
    digest = sha256.convert([...digest, ...salt]).bytes;
  }
  return digest;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GatedStore store;
  String? uid;

  AppLockService newService() => AppLockService(
    store: store,
    biometrics: NoBiometrics(),
    currentUid: () => uid,
  );

  setUp(() {
    store = GatedStore();
    uid = 'patientA';
  });

  group('AppLockService races', () {
    test('a load that finishes after sign-out does not apply', () async {
      await newService().setPin('2580');

      final lock = newService();
      store.hold();
      final loading = lock.load();
      uid = null; // signed out while the storage read is in flight
      store.release();
      await loading;

      expect(lock.isEnabled, isFalse);
      expect(lock.lockIfEnabled('test'), isFalse);
    });

    test('a wrong PIN checked across a sign-out is not counted', () async {
      final lock = newService();
      await lock.setPin('2580');

      final check = lock.verifyPin('1111');
      lock.forget(); // sign-out while the hash is being computed
      await check;

      expect(store.values['lock_failed_attempts_patientA'], '0');
      final reloaded = newService();
      await reloaded.load();
      expect(reloaded.attemptsLeft, AppLockService.maxAttempts);
    });

    test('setPin refuses to save after the patient signed out', () async {
      final lock = newService();
      final saving = lock.setPin('2580');
      uid = null;
      await expectLater(saving, throwsStateError);
      expect(store.values, isEmpty);
      expect(lock.isEnabled, isFalse);
    });

    test('the background PIN helpers agree with the sync ones', () async {
      final record = await PinHasher.createInBackground('2580');
      expect(PinHasher.verify('2580', record), isTrue);
      expect(await PinHasher.verifyInBackground('2580', record), isTrue);
      expect(await PinHasher.verifyInBackground('0852', record), isFalse);
    });
  });

  group('PinHasher compatibility', () {
    test('records made by the original hashing loop still verify', () {
      final salt = List<int>.generate(16, (i) => i * 7 % 256);
      const rounds = 50;
      final record =
          'v1\$$rounds\$${base64Encode(salt)}'
          '\$${base64Encode(legacyHash('2580', salt, rounds))}';
      expect(PinHasher.verify('2580', record), isTrue);
      expect(PinHasher.verify('2581', record), isFalse);
    });
  });

  group('AppLockService.awayLongEnough', () {
    final since = DateTime(2026, 11, 12, 9);

    test('a minute or more away relocks', () {
      expect(
        AppLockService.awayLongEnough(
          since,
          since.add(AppLockService.relockAfter),
        ),
        isTrue,
      );
    });

    test('a short trip or a clock set back does not', () {
      expect(
        AppLockService.awayLongEnough(
          since,
          since.add(const Duration(seconds: 59)),
        ),
        isFalse,
      );
      expect(
        AppLockService.awayLongEnough(
          since,
          since.subtract(const Duration(hours: 1)),
        ),
        isFalse,
      );
    });
  });

  group('ConsentService.isRecordConfirmed', () {
    test('only a document the server has counts as consent', () {
      expect(
        ConsentService.isRecordConfirmed(exists: true, hasPendingWrites: false),
        isTrue,
      );
      expect(
        ConsentService.isRecordConfirmed(exists: true, hasPendingWrites: true),
        isFalse,
        reason: 'a queued offline write has not reached the clinic yet',
      );
      expect(
        ConsentService.isRecordConfirmed(
          exists: false,
          hasPendingWrites: false,
        ),
        isFalse,
      );
    });
  });

  group('ExerciseSession vs firestore.rules', () {
    final start = DateTime(2026, 11, 12, 9);

    ExerciseSession session({DateTime? end, String? prescriptionId}) =>
        ExerciseSession(
          id: 's1',
          exerciseId: 'kneeExtension',
          exerciseName: 'Knee Extension',
          startTime: start,
          endTime: end,
          targetReps: 10,
          targetSets: 1,
          painLevel: 2,
          prescriptionId: prescriptionId,
        );

    test(
      'an end before the start (clock set back) is written as the start',
      () {
        final data = session(
          end: start.subtract(const Duration(seconds: 5)),
        ).toFirestore();
        expect(data['endTime'], Timestamp.fromDate(start));
      },
    );

    test('a normal end time is written unchanged', () {
      final end = start.add(const Duration(minutes: 3));
      expect(
        session(end: end).toFirestore()['endTime'],
        Timestamp.fromDate(end),
      );
      expect(session().toFirestore()['endTime'], isNull);
    });

    test('a prescription id longer than the rules allow is reported', () {
      expect(session(prescriptionId: 'p' * 128).firestoreProblems(), isEmpty);
      expect(session(prescriptionId: 'p' * 129).firestoreProblems(), [
        'prescriptionId',
      ]);
    });

    test('painNote is always present so the rules can read it', () {
      // validSession reads d.painNote unguarded: a missing key is an error
      // in the rules language and would reject the whole session.
      expect(session().toFirestore().containsKey('painNote'), isTrue);
    });
  });
}
