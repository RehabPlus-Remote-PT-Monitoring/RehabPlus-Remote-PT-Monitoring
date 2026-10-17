import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/diagnostic_logger.dart';
import '../models/session.dart';
import '../screens/edit_profile_screen.dart' show ProfileData;
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/profile_service.dart';
import '../services/push_service.dart';
import '../services/session_storage.dart';

/// App-wide state for the signed-in patient: profile and session history.
/// Cleared on sign-out so the next account never sees the previous one's data.
///
/// Live exercise tracking lives in PoseDetectorScreen; it hands finished
/// sessions here via [recordCompletedSession].
class AppProvider extends ChangeNotifier {
  final DiagnosticLogger _logger = DiagnosticLogger.I;
  final SessionStorage _storage = SessionStorage();

  List<ExerciseSession> _sessionHistory = [];
  ProfileData? _profile;

  List<ExerciseSession> get sessionHistory => _sessionHistory;

  /// Null until loaded (or when signed out / offline with no cache).
  ProfileData? get profile => _profile;

  Future<void> init() async {
    _logger.info('AppProvider', 'Initializing');
    await loadUserData();
    _logger.info('AppProvider', 'Initialized');
  }

  /// Loads everything for the currently signed-in user. Call after sign-in.
  Future<void> loadUserData() => Future.wait([loadProfile(), loadHistory()]);

  Future<void> loadProfile() async {
    try {
      _profile = await ProfileService().load();
    } catch (e) {
      _logger.warn('AppProvider', 'Profile load failed', {'error': e.toString()});
      _profile = null;
    }
    notifyListeners();
  }

  void updateProfile(ProfileData profile) {
    _profile = profile;
    notifyListeners();
  }

  Future<void> loadHistory() async {
    _sessionHistory = await _storage.loadSessions();
    _logger.info('AppProvider', 'Loaded ${_sessionHistory.length} sessions from storage');
    notifyListeners();
  }

  Future<void> recordCompletedSession(ExerciseSession session) async {
    _logger.info('AppProvider', 'Recording completed session: ${session.exerciseName}');
    await _storage.saveSession(session);
    NotificationService().addSessionCompleted(session);
    await loadHistory();
  }

  Future<void> signOut() async {
    // Before auth sign-out: removing the device token needs the user's auth.
    await PushService.I.unregister();
    await AuthService.I.signOut();
    _sessionHistory = [];
    _profile = null;
    notifyListeners();
  }
}

/// Extension for easy access in widgets
extension AppProviderExtensions on BuildContext {
  AppProvider get appProvider => read<AppProvider>();
}
