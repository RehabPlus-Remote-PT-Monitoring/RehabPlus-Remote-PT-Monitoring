import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';
import '../models/app_notification.dart';
import '../models/firestore_fields.dart';
import '../models/session.dart';
import 'firestore_diagnostics.dart';

/// The signed-in patient's notification list (patients/{uid}/notifications).
///
/// Log events (tag 'NotificationService'), never including titles/bodies:
///   "Notifications / Unread count stream started|first snapshot|error|
///     stopped" {docs, fromCache, ms}
///   "Malformed notification skipped" {id, reason}
///   "Mark read synced / sync failed" {id}
///   "Mark all read" {count, batches}; "Mark all read synced / failed"
///   "Session completed entry synced / sync failed" {sessionId}
class NotificationService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  final _logger = DiagnosticLogger.I;

  /// How many of the newest entries the Notifications page shows.
  static const int listLimit = 100;

  /// Firestore allows at most 500 writes per batch.
  static const int _maxBatchWrites = 500;

  CollectionReference<Map<String, dynamic>>? get _col {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return _db.collection('patients').doc(uid).collection('notifications');
  }

  /// Newest first. A malformed entry is left out (and logged) instead of
  /// breaking the whole list. Empty when signed out.
  Stream<List<AppNotification>> watch() {
    final col = _col;
    if (col == null) return Stream.value(const []);
    return observeStream(
      col.orderBy('createdAt', descending: true).limit(listLimit).snapshots(),
      tag: 'NotificationService',
      name: 'Notifications',
      describe: describeQuery,
    ).map(_parseList);
  }

  List<AppNotification> _parseList(QuerySnapshot<Map<String, dynamic>> snap) {
    final result = <AppNotification>[];
    for (final doc in snap.docs) {
      final parsed = AppNotification.parse(doc.id, doc.data());
      if (parsed.isOk) {
        result.add(parsed.value!);
      } else {
        _logger.warn('NotificationService', 'Malformed notification skipped', {
          'id': doc.id,
          'reason': parsed.error,
        });
      }
    }
    return result;
  }

  /// Live number of unread entries (for the bell badge). 0 when signed out.
  Stream<int> unreadCount() {
    final col = _col;
    if (col == null) return Stream.value(0);
    return observeStream(
      col.where('read', isEqualTo: false).snapshots(),
      tag: 'NotificationService',
      name: 'Unread count',
      describe: describeQuery,
    ).map((s) => s.size);
  }

  void markRead(String id) {
    final col = _col;
    if (col == null) return;
    logUnawaitedWrite(
      col.doc(id).update({'read': true}),
      tag: 'NotificationService',
      operation: 'Mark read',
      data: {'id': id},
    );
  }

  /// Marks every unread entry read. Awaits only the query for unread
  /// entries; the updates themselves go through the offline cache. Split
  /// into batches of at most 500 writes (Firestore's per-batch limit), so a
  /// very long backlog can't make the whole operation fail.
  Future<void> markAllRead() async {
    final col = _col;
    if (col == null) return;
    final unread = await _logger.timed(
      'NotificationService',
      'Query unread',
      () => col.where('read', isEqualTo: false).get(),
    );
    if (unread.docs.isEmpty) return;

    var batches = 0;
    for (var start = 0; start < unread.docs.length; start += _maxBatchWrites) {
      final batch = _db.batch();
      for (final doc in unread.docs.skip(start).take(_maxBatchWrites)) {
        batch.update(doc.reference, {'read': true});
      }
      batches++;
      logUnawaitedWrite(
        batch.commit(),
        tag: 'NotificationService',
        operation: 'Mark all read',
        data: {'batch': batches},
      );
    }
    _logger.info('NotificationService', 'Mark all read', {
      'count': unread.docs.length,
      'batches': batches,
      'fromCache': unread.metadata.isFromCache,
    });
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
    logUnawaitedWrite(
      col.add({
        'type': 'session_completed',
        'title': s.endedEarly ? 'Session Ended Early' : 'Exercise Completed',
        // The rules allow at most 300 characters; only a very long exercise
        // name could reach that, and clipping beats a rejected write.
        'body': clipText(body, AppNotification.maxBodyLength),
        'createdAt': FieldValue.serverTimestamp(),
        'read': true,
      }),
      tag: 'NotificationService',
      operation: 'Session completed entry',
      data: {'sessionId': s.id, 'endedEarly': s.endedEarly},
    );
  }
}
