import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';
import '../models/session.dart';

/// Stores sessions in Firestore at patients/{uid}/sessions/{sessionId}.
///
/// Firestore's on-device cache doubles as the offline queue: a session saved
/// without signal is kept locally and uploaded when the phone reconnects.
class SessionStorage {
  final DiagnosticLogger _logger;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  SessionStorage({DiagnosticLogger? logger})
    : _logger = logger ?? DiagnosticLogger.I {
    _logger.info('SessionStorage', 'Initialized');
  }

  CollectionReference<Map<String, dynamic>>? get _sessions {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return _db.collection('patients').doc(uid).collection('sessions');
  }

  Future<List<ExerciseSession>> loadSessions() async {
    final col = _sessions;
    if (col == null) return [];
    try {
      // Falls back to the local cache automatically when offline.
      final snap = await col.orderBy('startTime', descending: true).get();
      final sessions = snap.docs
          .map((d) => ExerciseSession.fromFirestore(d.id, d.data()))
          .toList();
      _logger.info('SessionStorage', 'Loaded ${sessions.length} sessions', {
        'fromCache': snap.metadata.isFromCache,
      });
      return sessions;
    } catch (e, stackTrace) {
      _logger.error('SessionStorage', 'Failed to load sessions', {
        'error': e.toString(),
        'stackTrace': stackTrace.toString(),
      });
      return [];
    }
  }

  Future<void> saveSession(ExerciseSession session) async {
    final col = _sessions;
    if (col == null) {
      _logger.error('SessionStorage', 'Not signed in; session dropped', {
        'id': session.id,
      });
      throw StateError('Not signed in');
    }
    // Not awaited: the returned future only completes once the server
    // confirms, which never happens while offline. The write is already in
    // the local cache, so loadSessions() sees it immediately.
    unawaited(
      col
          .doc(session.id)
          .set(session.toFirestore())
          .then(
            (_) => _logger.info('SessionStorage', 'Session synced', {
              'id': session.id,
            }),
            onError: (Object e, StackTrace st) => _logger.error(
              'SessionStorage',
              'Session sync failed',
              {'id': session.id, 'error': e.toString()},
            ),
          ),
    );
    _logger.info('SessionStorage', 'Saved session: ${session.exerciseName}', {
      'id': session.id,
      'reps': session.completedReps,
    });
  }
}
