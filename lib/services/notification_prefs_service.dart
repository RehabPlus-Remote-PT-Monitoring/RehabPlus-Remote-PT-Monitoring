import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';

/// Which push notifications the patient wants, stored at
/// patients/{uid}/preferences/notifications so the dashboard can check it
/// before sending a push. In-app Notifications-page entries are always kept.
class NotificationPrefs {
  const NotificationPrefs({this.messages = true, this.exercises = true});

  /// Pushes for new messages from the therapist or clinic (type `chat`).
  final bool messages;

  /// Pushes for newly assigned exercises (type `exercise_assigned`).
  final bool exercises;
}

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

  Future<NotificationPrefs> load() async {
    try {
      final data = (await _doc?.get())?.data() ?? const {};
      return NotificationPrefs(
        messages: data['messages'] as bool? ?? true,
        exercises: data['exercises'] as bool? ?? true,
      );
    } on FirebaseException catch (e) {
      _logger.warn('NotificationPrefs', 'Load failed', {'code': e.code});
      return const NotificationPrefs();
    }
  }

  /// Saves both choices. Throws if it can't be saved.
  Future<void> save(NotificationPrefs prefs) async {
    final doc = _doc;
    if (doc == null) throw StateError('Not signed in');
    await doc
        .set({
          'messages': prefs.messages,
          'exercises': prefs.exercises,
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 15));
  }
}
