import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';
import 'firestore_diagnostics.dart';

/// Which push notifications the patient wants, stored at
/// patients/{uid}/preferences/notifications so the dashboard can check it
/// before sending a push. In-app Notifications-page entries are always kept.
class NotificationPrefs {
  const NotificationPrefs({this.messages = true, this.exercises = true});

  /// Pushes for new messages from the therapist or clinic (type `chat`).
  final bool messages;

  /// Pushes for newly assigned exercises (type `exercise_assigned`).
  final bool exercises;

  /// Reads the stored document. A missing document or a non-bool value
  /// means "on" (the API_CONTRACT default), never "off": silently muting a
  /// patient's pushes because of bad data would be the worse failure.
  factory NotificationPrefs.fromMap(Map<String, dynamic>? data) =>
      NotificationPrefs(
        messages: data?['messages'] is bool ? data!['messages'] as bool : true,
        exercises: data?['exercises'] is bool
            ? data!['exercises'] as bool
            : true,
      );

  /// The document body the rules accept (plus the server timestamp).
  Map<String, Object> toFirestore() => {
    'messages': messages,
    'exercises': exercises,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

/// Log events (tag 'NotificationPrefs'): "Loaded" {messages, exercises,
/// exists, fromCache}, "Load failed" {code}, "Save done/failed" {ms, code}.
class NotificationPrefsService {
  NotificationPrefsService._();
  static final NotificationPrefsService I = NotificationPrefsService._();

  final _logger = DiagnosticLogger.I;

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('patients')
        .doc(uid)
        .collection('preferences')
        .doc('notifications');
  }

  /// The saved choices; the defaults (both on) when signed out or when the
  /// document can't be read.
  Future<NotificationPrefs> load() async {
    final doc = _doc;
    if (doc == null) return const NotificationPrefs();
    try {
      final snap = await doc.get();
      final prefs = NotificationPrefs.fromMap(snap.data());
      _logger.info('NotificationPrefs', 'Loaded', {
        'messages': prefs.messages,
        'exercises': prefs.exercises,
        'exists': snap.exists,
        'fromCache': snap.metadata.isFromCache,
      });
      return prefs;
    } catch (e, st) {
      _logger.warn('NotificationPrefs', 'Load failed', firebaseErrorData(e),
          e, st);
      return const NotificationPrefs();
    }
  }

  /// Saves both choices. Throws if it can't be saved within 15 seconds.
  ///
  /// This one IS awaited (unlike most writes in the app): Settings shows
  /// whether the change reached the clinic, because the dashboard reads it
  /// before sending each push.
  Future<void> save(NotificationPrefs prefs) async {
    final doc = _doc;
    if (doc == null) throw StateError('Not signed in');
    await _logger.timed(
      'NotificationPrefs',
      'Save',
      () => doc.set(prefs.toFirestore()).timeout(const Duration(seconds: 15)),
      data: {'messages': prefs.messages, 'exercises': prefs.exercises},
    );
  }
}
