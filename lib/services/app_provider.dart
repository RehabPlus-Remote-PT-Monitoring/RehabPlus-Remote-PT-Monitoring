import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/diagnostic_logger.dart';
import '../models/session.dart';
import '../screens/edit_profile_screen.dart' show ProfileData;
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/profile_service.dart';
import '../services/app_lock_service.dart';
import '../services/app_settings.dart';
import '../services/push_service.dart';
import '../services/reminder_service.dart';
import '../services/session_storage.dart';

/// App-wide state for the signed-in patient: profile and session history.
/// Cleared on sign-out so the next account never sees the previous one's data.
///
/// Live exercise tracking lives in PoseDetectorScreen; it hands finished
/// sessions here via [recordCompletedSession].
///
/// Races this class guards against
/// -------------------------------
///  - A load that finishes after sign-out (or after another patient signed
///    in) must not write the previous patient's data back into the state.
///    Every load remembers the uid and the "account epoch" it started under
///    ([_epoch], bumped by [signOut] and [dispose]) and discards its result
///    if either changed ("Discarded stale ..." in the log).
///  - Overlapping [loadHistory] calls: only the newest one may assign, so
///    an older, slower read can't overwrite a newer result.
///  - A session recorded while a history load is in flight: sessions saved
///    in this run are merged into every later load result, so they can't
///    vanish from the list.
///  - Overlapping [init]/[loadUserData] calls for the same user (startup and
///    the login page) share one load; double-tapping Sign Out runs it once.
///  - [notifyListeners] after [dispose] is ignored instead of throwing.
///
/// Log events (tag 'AppProvider'): "Load user data done/failed" {uid, ms},
/// "Profile load failed", "History load failed" {code}, "Discarded stale
/// profile/history" {reason}, "Session recorded" {id, count}, "Signing out" /
/// "Signed out", "Sign-out step failed" {step}.
class AppProvider extends ChangeNotifier {
  /// All parameters are for tests; the app uses the defaults.
  ///
  /// [currentUid] reports the signed-in uid (default: Firebase Auth).
  /// [signOutHandler] performs the external part of signing out (default:
  /// unregister push, cancel the reminder, Firebase sign-out).
  AppProvider({
    SessionStorage? storage,
    ProfileService? profiles,
    NotificationService? notifications,
    String? Function()? currentUid,
    Future<void> Function()? signOutHandler,
  }) : _storage = storage ?? SessionStorage(),
       _profiles = profiles ?? ProfileService(),
       _notifications = notifications ?? NotificationService(),
       _currentUid = currentUid ?? _firebaseUid,
       _signOutHandler = signOutHandler ?? _signOutOfServices;

  final DiagnosticLogger _logger = DiagnosticLogger.I;
  final SessionStorage _storage;
  final ProfileService _profiles;
  final NotificationService _notifications;
  final String? Function() _currentUid;
  final Future<void> Function() _signOutHandler;

  List<ExerciseSession> _sessionHistory = [];
  ProfileData? _profile;

  /// Bumped on sign-out and dispose; results of loads started under an
  /// older epoch are dropped.
  int _epoch = 0;

  /// Id of the newest [loadHistory] call; older calls don't assign.
  int _historyRequest = 0;

  /// Sessions recorded during this sign-in, by id (see the class comment).
  final Map<String, ExerciseSession> _recordedThisSignIn = {};

  Future<void>? _pendingLoad;
  String? _pendingLoadUid;
  Future<void>? _signingOut;
  bool _disposed = false;

  List<ExerciseSession> get sessionHistory => _sessionHistory;

  /// Null until loaded (or when signed out / offline with no cache).
  ProfileData? get profile => _profile;

  static String? _firebaseUid() => FirebaseAuth.instance.currentUser?.uid;

  Future<void> init() async {
    _logger.info('AppProvider', 'Initializing');
    await loadUserData();
    _logger.info('AppProvider', 'Initialized');
  }

  /// Loads everything for the currently signed-in user. Call after sign-in.
  ///
  /// Profile and history are independent, so they load in parallel. A call
  /// made while a load for the same user is still running joins that load.
  Future<void> loadUserData() {
    final uid = _currentUid();
    final pending = _pendingLoad;
    if (pending != null && _pendingLoadUid == uid) {
      _logger.info('AppProvider', 'User data load already running; joining', {
        'uid': uid,
      });
      return pending;
    }
    if (uid == null) {
      _logger.info('AppProvider', 'No user signed in; nothing to load');
      return Future.value();
    }

    final load = _logger.timed(
      'AppProvider',
      'Load user data',
      () => Future.wait([loadProfile(), loadHistory()]),
      data: {'uid': uid},
    );
    _pendingLoad = load;
    _pendingLoadUid = uid;
    return load.whenComplete(() {
      if (identical(_pendingLoad, load)) _pendingLoad = null;
    });
  }

  /// Reloads the profile. On failure the current profile is kept (an
  /// offline refresh shouldn't blank the Profile page).
  Future<void> loadProfile() async {
    final epoch = _epoch;
    final uid = _currentUid();
    final ProfileData? profile;
    try {
      profile = await _profiles.load();
    } catch (e, st) {
      _logger.warn('AppProvider', 'Profile load failed', {'uid': uid}, e, st);
      return;
    }
    if (_isStale(epoch, uid, 'profile')) return;
    _profile = profile;
    notifyListeners();
  }

  void updateProfile(ProfileData profile) {
    _profile = profile;
    notifyListeners();
  }

  /// Reloads the session history. On failure the current list is kept.
  Future<void> loadHistory() async {
    final request = ++_historyRequest;
    final epoch = _epoch;
    final uid = _currentUid();
    final List<ExerciseSession> loaded;
    try {
      loaded = await _storage.fetchSessions();
    } catch (e, st) {
      _logger.warn('AppProvider', 'History load failed', {'uid': uid}, e, st);
      return;
    }
    if (request != _historyRequest) {
      _logger.info('AppProvider', 'Discarded stale history', {
        'reason': 'newer load started',
      });
      return;
    }
    if (_isStale(epoch, uid, 'history')) return;

    _sessionHistory = _mergeNewestFirst(loaded, _recordedThisSignIn.values);
    _logger.info('AppProvider', 'History updated', {
      'uid': uid,
      'count': _sessionHistory.length,
      'loaded': loaded.length,
    });
    notifyListeners();
  }

  /// Saves a finished session and shows it in the history straight away.
  ///
  /// The session is added to the in-memory list directly instead of
  /// re-reading the whole history from Firestore (the old behaviour): the
  /// result is identical, it is instant even offline, and it saves one read
  /// per stored session every time an exercise is finished.
  ///
  /// Throws (from [SessionStorage.saveSession]) when signed out or when the
  /// session is invalid; the caller shows an error.
  Future<void> recordCompletedSession(ExerciseSession session) async {
    final epoch = _epoch;
    final uid = _currentUid();
    _logger.info('AppProvider', 'Recording completed session', {
      'id': session.id,
      'exerciseId': session.exerciseId,
    });
    await _storage.saveSession(session);
    _notifications.addSessionCompleted(session);
    if (_isStale(epoch, uid, 'recorded session')) return;

    _recordedThisSignIn[session.id] = session;
    _sessionHistory = _mergeNewestFirst(_sessionHistory, [session]);
    _logger.info('AppProvider', 'Session recorded', {
      'id': session.id,
      'count': _sessionHistory.length,
    });
    notifyListeners();
  }

  /// Signs out and clears all state. A second call while one is running
  /// returns the same future.
  Future<void> signOut() {
    final running = _signingOut;
    if (running != null) return running;
    final run = _signOut();
    _signingOut = run;
    return run.whenComplete(() => _signingOut = null);
  }

  Future<void> _signOut() async {
    final uid = _currentUid();
    _logger.info('AppProvider', 'Signing out', {'uid': uid});
    // First, so loads still in flight for this user are discarded.
    _epoch++;
    _pendingLoad = null;
    try {
      await _signOutHandler();
    } finally {
      // Even if a step failed, never leave this patient's data on screen.
      _sessionHistory = [];
      _profile = null;
      _recordedThisSignIn.clear();
      notifyListeners();
      _logger.info('AppProvider', 'Signed out', {'uid': uid});
    }
  }

  /// The default sign-out steps. Push and reminder cleanup are best-effort:
  /// their failure must never stop the actual sign-out.
  static Future<void> _signOutOfServices() async {
    final logger = DiagnosticLogger.I;
    // Before auth sign-out: removing the device token needs the user's auth.
    await PushService.I.unregister(); // never throws
    try {
      if (AppSettings.I.reminderEnabled) {
        await ReminderService.I.cancel();
        await AppSettings.I.setReminderEnabled(false);
      }
    } catch (e, st) {
      logger.warn('AppProvider', 'Sign-out step failed', {
        'step': 'reminder',
      }, e, st);
    }
    // The PIN stays saved for this patient (it comes back when they sign in
    // again) but is dropped from memory so the next person doesn't get it.
    AppLockService.I.forget();
    await AuthService.I.signOut();
  }

  /// True (and logged) when a result started under [epoch] for [uid] no
  /// longer belongs to the current state.
  bool _isStale(int epoch, String? uid, String what) {
    final String? reason;
    if (_disposed) {
      reason = 'disposed';
    } else if (epoch != _epoch) {
      reason = 'signed out';
    } else if (uid != _currentUid()) {
      reason = 'user changed';
    } else {
      reason = null;
    }
    if (reason == null) return false;
    _logger.info('AppProvider', 'Discarded stale $what', {'reason': reason});
    return true;
  }

  /// [base] plus [extra], one entry per id (entries in [extra] win), newest
  /// start time first. Returns a new list, so widgets comparing by identity
  /// see a change.
  static List<ExerciseSession> _mergeNewestFirst(
    Iterable<ExerciseSession> base,
    Iterable<ExerciseSession> extra,
  ) {
    final byId = <String, ExerciseSession>{
      for (final s in base) s.id: s,
      for (final s in extra) s.id: s,
    };
    return byId.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  @override
  void notifyListeners() {
    if (_disposed) return; // a late async result after dispose: ignore
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}

/// Extension for easy access in widgets
extension AppProviderExtensions on BuildContext {
  AppProvider get appProvider => read<AppProvider>();
}
