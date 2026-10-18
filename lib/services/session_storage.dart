import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/background.dart';
import '../core/diagnostic_logger.dart';
import '../models/session.dart';
import 'firestore_diagnostics.dart';

/// Stores sessions in Firestore at patients/{uid}/sessions/{sessionId}.
///
/// Firestore's on-device cache doubles as the offline queue: a session saved
/// without signal is kept locally and uploaded when the phone reconnects.
///
/// Log events (tag 'SessionStorage'):
///   "Load sessions done/failed" {uid, ms, code}
///   "Loaded sessions" {uid, count, docs, skipped, repaired, fromCache}
///   "Malformed session skipped" {id, reason}; "Session repaired" {id, fields}
///   "Session queued" {id, exerciseId, reps, endedEarly}
///   "Session synced / sync failed" {id, code, ms}
///   "Session invalid; not saved" {id, fields}
class SessionStorage {
  final DiagnosticLogger _logger;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// From this many documents up, parsing runs on a background isolate.
  ///
  /// Why a threshold: Firestore already decodes snapshots off the UI thread
  /// (on the platform side); what is left on the UI isolate is turning each
  /// document map into an [ExerciseSession], roughly a few microseconds per
  /// document. For a typical history (tens to a few hundred sessions) that
  /// is well under a frame, and spawning an isolate plus copying the data
  /// would cost more than it saves. A patient several years into therapy
  /// can have thousands, where it starts to cost frames on a slow phone.
  static const int backgroundParseThreshold = 500;

  /// How many malformed/repaired documents are logged individually per load
  /// (the totals are always logged), so a badly corrupted history can't
  /// flood the log ring buffer.
  static const int _maxDetailLogs = 10;

  SessionStorage({DiagnosticLogger? logger})
    : _logger = logger ?? DiagnosticLogger.I {
    _logger.info('SessionStorage', 'Initialized');
  }

  CollectionReference<Map<String, dynamic>>? _sessionsOf(String? uid) =>
      uid == null
      ? null
      : _db.collection('patients').doc(uid).collection('sessions');

  /// All sessions, newest first, or an empty list when signed out or when
  /// they can't be loaded (the error is logged). Prefer [fetchSessions] when
  /// a failure must be told apart from "no sessions".
  Future<List<ExerciseSession>> loadSessions() async {
    try {
      return await fetchSessions();
    } catch (_) {
      return []; // already logged by fetchSessions
    }
  }

  /// All sessions, newest first; empty when signed out. Throws when they
  /// can't be read. Malformed documents are skipped (and logged), so one
  /// bad record never hides the rest of the history.
  Future<List<ExerciseSession>> fetchSessions() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final col = _sessionsOf(uid);
    if (col == null) return [];

    // Falls back to the local cache automatically when offline.
    final snap = await _logger.timed(
      'SessionStorage',
      'Load sessions',
      () => col.orderBy('startTime', descending: true).get(),
      data: {'uid': uid},
    );

    // Copy out plain (id, map) pairs: they can cross to an isolate, the
    // snapshot objects (which hold platform handles) can't.
    final raw = [for (final doc in snap.docs) (doc.id, doc.data())];
    final batch = await _parse(raw);
    _logParseResult(batch, uid: uid, fromCache: snap.metadata.isFromCache);
    return batch.sessions;
  }

  /// Parses [raw] inline or on an isolate (see [backgroundParseThreshold]).
  /// Static on purpose: the closure handed to the isolate must only capture
  /// [raw], not `this` (whose fields can't be sent between isolates).
  static Future<SessionParseBatch> _parse(
    List<(String, Map<String, dynamic>)> raw,
  ) => runInBackground(
    'Parse sessions',
    () => ExerciseSession.parseFirestoreBatch(raw),
    heavy: raw.length >= backgroundParseThreshold,
    data: {'docs': raw.length},
  );

  void _logParseResult(
    SessionParseBatch batch, {
    required String? uid,
    required bool fromCache,
  }) {
    for (final entry in batch.skipped.entries.take(_maxDetailLogs)) {
      _logger.warn('SessionStorage', 'Malformed session skipped', {
        'id': entry.key,
        'reason': entry.value,
      });
    }
    for (final entry in batch.repaired.entries.take(_maxDetailLogs)) {
      _logger.warn('SessionStorage', 'Session repaired', {
        'id': entry.key,
        'fields': entry.value,
      });
    }
    _logger.info('SessionStorage', 'Loaded sessions', {
      'uid': uid,
      'count': batch.sessions.length,
      'docs': batch.sessions.length + batch.skipped.length,
      'skipped': batch.skipped.length,
      'repaired': batch.repaired.length,
      'fromCache': fromCache,
    });
  }

  /// Saves [session]. Returns as soon as it is in the local cache.
  ///
  /// Throws [StateError] when signed out, and [ArgumentError] when the
  /// session breaks a Firestore rule (e.g. no pain level): the server would
  /// reject it and Firestore would silently drop it from the cache, so it is
  /// better to fail here, where the caller can tell the patient.
  Future<void> saveSession(ExerciseSession session) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final col = _sessionsOf(uid);
    if (col == null) {
      _logger.error('SessionStorage', 'Not signed in; session dropped', {
        'id': session.id,
      });
      throw StateError('Not signed in');
    }

    final problems = session.firestoreProblems();
    if (problems.isNotEmpty) {
      _logger.error('SessionStorage', 'Session invalid; not saved', {
        'id': session.id,
        'fields': problems,
      });
      throw ArgumentError('Invalid session fields: ${problems.join(', ')}');
    }

    // Not awaited: the returned future only completes once the server
    // confirms, which never happens while offline. The write is already in
    // the local cache, so loadSessions() sees it immediately.
    logUnawaitedWrite(
      col.doc(session.id).set(session.toFirestore()),
      tag: 'SessionStorage',
      operation: 'Session',
      data: {'uid': uid, 'id': session.id},
    );
    _logger.info('SessionStorage', 'Session queued', {
      'id': session.id,
      'exerciseId': session.exerciseId,
      'reps': session.completedReps,
      'endedEarly': session.endedEarly,
    });
  }
}
