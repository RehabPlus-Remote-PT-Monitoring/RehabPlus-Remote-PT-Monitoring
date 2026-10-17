import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';
import '../models/app_notification.dart';
import '../models/session.dart';

/// The signed-in patient's notification list (patients/{uid}/notifications).
class NotificationService {
  final _db = FirebaseFirestore.instance;
  final _logger = DiagnosticLogger.I;

  CollectionReference<Map<String, dynamic>>? get _col {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return _db.collection('patients').doc(uid).collection('notifications');
  }

  /// Newest first.
  Stream<List<AppNotification>> watch() {
    final col = _col;
    if (col == null) return Stream.value(const []);
    return col
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final d = doc.data();
            return AppNotification(
              id: doc.id,
              type: d['type'] as String? ?? 'general',
              title: d['title'] as String? ?? '',
              body: d['body'] as String? ?? '',
              // Null only for a local write the server hasn't stamped yet.
              createdAt:
                  (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              read: d['read'] == true,
              data:
                  (d['data'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ??
                  const {},
            );
          }).toList(),
        );
  }

  Stream<int> unreadCount() {
    final col = _col;
    if (col == null) return Stream.value(0);
    return col.where('read', isEqualTo: false).snapshots().map((s) => s.size);
  }

  void markRead(String id) {
    final col = _col;
    if (col == null) return;
    unawaited(
      col
          .doc(id)
          .update({'read': true})
          .catchError(
            (Object e) => _logger.warn(
              'NotificationService',
              'markRead failed',
              {'error': e.toString()},
            ),
          ),
    );
  }

  Future<void> markAllRead() async {
    final col = _col;
    if (col == null) return;
    final unread = await col.where('read', isEqualTo: false).get();
    if (unread.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'read': true});
    }
    unawaited(
      batch.commit().catchError(
        (Object e) => _logger.warn(
          'NotificationService',
          'markAllRead failed',
          {'error': e.toString()},
        ),
      ),
    );
  }

  /// Logged after a session is saved. Already read: the patient just did it,
  /// so it shouldn't light up the badge, but it shows in their history.
  void addSessionCompleted(ExerciseSession s) {
    final col = _col;
    if (col == null) return;
    final unit = s.targetReps == 1 ? 'rep' : 'reps';
    final body = s.endedEarly
        ? 'You did ${s.completedReps} of ${s.targetReps} $unit of ${s.exerciseName}.'
        : 'Great job! You completed ${s.exerciseName} (${s.completedReps} $unit).';
    unawaited(
      col
          .add({
            'type': 'session_completed',
            'title': s.endedEarly
                ? 'Session Ended Early'
                : 'Exercise Completed',
            'body': body,
            'createdAt': FieldValue.serverTimestamp(),
            'read': true,
          })
          .then(
            (_) {},
            onError: (Object e, StackTrace _) => _logger.warn(
              'NotificationService',
              'addSessionCompleted failed',
              {'error': e.toString()},
            ),
          ),
    );
  }
}
