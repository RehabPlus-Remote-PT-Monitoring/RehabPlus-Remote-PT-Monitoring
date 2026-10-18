// AppProvider race handling, with in-memory fakes (no Firebase needed).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/diagnostic_logger.dart';
import 'package:rehabplus/models/session.dart';
import 'package:rehabplus/screens/edit_profile_screen.dart' show ProfileData;
import 'package:rehabplus/services/app_provider.dart';
import 'package:rehabplus/services/notification_service.dart';
import 'package:rehabplus/services/profile_service.dart';
import 'package:rehabplus/services/session_storage.dart';

/// Each fetchSessions() call returns a future the test completes by hand.
class FakeStorage extends SessionStorage {
  final List<Completer<List<ExerciseSession>>> fetches = [];
  final List<ExerciseSession> saved = [];

  @override
  Future<List<ExerciseSession>> fetchSessions() {
    final c = Completer<List<ExerciseSession>>();
    fetches.add(c);
    return c.future;
  }

  @override
  Future<void> saveSession(ExerciseSession session) async => saved.add(session);
}

class FakeProfiles extends ProfileService {
  final List<Completer<ProfileData?>> loads = [];

  @override
  Future<ProfileData?> load() {
    final c = Completer<ProfileData?>();
    loads.add(c);
    return c.future;
  }
}

class FakeNotifications extends NotificationService {
  int completed = 0;

  @override
  void addSessionCompleted(ExerciseSession s) => completed++;
}

ExerciseSession _session(String id, int day) => ExerciseSession(
  id: id,
  exerciseId: 'kneeExtension',
  exerciseName: 'Knee Extension',
  startTime: DateTime(2026, 10, day, 9),
  targetReps: 10,
  targetSets: 1,
  painLevel: 2,
);

const _profile = ProfileData(
  name: 'Test',
  email: '',
  phone: '',
  dob: '',
  condition: '',
);

void main() {
  late FakeStorage storage;
  late FakeProfiles profiles;
  late FakeNotifications notifications;
  late String? uid;
  late int signOutCalls;
  late AppProvider provider;

  setUp(() {
    DiagnosticLogger.I.setSink(null);
    storage = FakeStorage();
    profiles = FakeProfiles();
    notifications = FakeNotifications();
    uid = 'patientA';
    signOutCalls = 0;
    provider = AppProvider(
      storage: storage,
      profiles: profiles,
      notifications: notifications,
      currentUid: () => uid,
      signOutHandler: () async {
        signOutCalls++;
        uid = null;
      },
    );
  });

  test('a history load that finishes after sign-out is discarded', () async {
    final load = provider.loadHistory();
    await provider.signOut();
    storage.fetches.single.complete([_session('a', 1)]);
    await load;
    expect(provider.sessionHistory, isEmpty);
  });

  test('a profile load for a previous user is discarded', () async {
    final load = provider.loadProfile();
    uid = 'patientB'; // someone else signed in meanwhile
    profiles.loads.single.complete(_profile);
    await load;
    expect(provider.profile, isNull);
  });

  test('an older, slower history load cannot overwrite a newer one', () async {
    final first = provider.loadHistory();
    final second = provider.loadHistory();
    storage.fetches[1].complete([_session('new', 2)]);
    await second;
    storage.fetches[0].complete([_session('old', 1)]);
    await first;
    expect(provider.sessionHistory.map((s) => s.id), ['new']);
  });

  test('a session recorded during a load survives the load result', () async {
    final load = provider.loadHistory();
    await provider.recordCompletedSession(_session('fresh', 5));
    expect(provider.sessionHistory.map((s) => s.id), ['fresh']);

    storage.fetches.single.complete([_session('older', 1)]);
    await load;
    expect(provider.sessionHistory.map((s) => s.id), ['fresh', 'older']);
    expect(storage.saved.single.id, 'fresh');
    expect(notifications.completed, 1);
  });

  test('recording a session does not re-read the whole history', () async {
    await provider.recordCompletedSession(_session('s', 3));
    expect(storage.fetches, isEmpty);
    expect(provider.sessionHistory.single.id, 's');
  });

  test('overlapping loadUserData calls for one user share a load', () async {
    final a = provider.loadUserData();
    final b = provider.loadUserData();
    expect(storage.fetches, hasLength(1));
    expect(profiles.loads, hasLength(1));
    storage.fetches.single.complete([_session('a', 1)]);
    profiles.loads.single.complete(_profile);
    await Future.wait([a, b]);
    expect(provider.profile, isNotNull);
    expect(provider.sessionHistory, hasLength(1));
  });

  test('loadUserData does nothing when signed out', () async {
    uid = null;
    await provider.loadUserData();
    expect(storage.fetches, isEmpty);
    expect(profiles.loads, isEmpty);
  });

  test('a failed reload keeps the current history and profile', () async {
    final first = provider.loadUserData();
    storage.fetches.single.complete([_session('a', 1)]);
    profiles.loads.single.complete(_profile);
    await first;

    final retry = provider.loadUserData();
    storage.fetches.last.completeError(StateError('offline'));
    profiles.loads.last.completeError(StateError('offline'));
    await retry;
    expect(provider.sessionHistory.single.id, 'a');
    expect(provider.profile, isNotNull);
  });

  test('a double sign-out runs the sign-out steps once', () async {
    await Future.wait([provider.signOut(), provider.signOut()]);
    expect(signOutCalls, 1);
  });

  test('sign-out clears state even when a step fails', () async {
    final failing = AppProvider(
      storage: storage,
      profiles: profiles,
      notifications: notifications,
      currentUid: () => uid,
      signOutHandler: () async => throw StateError('auth down'),
    );
    await failing.recordCompletedSession(_session('s', 1));
    await expectLater(failing.signOut(), throwsStateError);
    expect(failing.sessionHistory, isEmpty);
  });

  test('a load finishing after dispose does not throw', () async {
    final load = provider.loadHistory();
    provider.dispose();
    storage.fetches.single.complete([_session('a', 1)]);
    await load; // would throw "used after being disposed" without the guard
  });
}
