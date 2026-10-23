import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';
import '../models/therapy_goal.dart';
import 'firestore_diagnostics.dart';

/// The signed-in patient's rehab goals (patients/{uid}/goals), read-only.
/// The therapist sets and updates them on the clinic dashboard.
///
/// Log events (tag 'GoalService'), never including goal text:
///   "Goals stream started|first snapshot|error|stopped" {docs, fromCache, ms}
///   "Malformed goal skipped" {id, reason}
///   "Goal repaired" {id, fields}
class GoalService {
  GoalService({FirebaseFirestore? db, FirebaseAuth? auth})
      : _dbOverride = db,
        _authOverride = auth;

  final FirebaseFirestore? _dbOverride;
  final FirebaseAuth? _authOverride;
  final _logger = DiagnosticLogger.I;

  // Lazy, so constructing the service never touches Firebase (tests).
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  /// Live list in display order (see [TherapyGoal.displayOrder]). A
  /// malformed goal is left out and logged instead of breaking the list.
  /// Empty when signed out.
  Stream<List<TherapyGoal>> watch() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    final col = _db.collection('patients').doc(uid).collection('goals');
    return observeStream(
      col.snapshots(),
      tag: 'GoalService',
      name: 'Goals',
      describe: describeQuery,
    ).map((snap) => parseGoals(
          snap.docs.map((d) => MapEntry(d.id, d.data())),
          logger: _logger,
        ));
  }

  /// Parses and sorts goal documents (id -> data). Pure apart from logging,
  /// so it is unit-tested without Firebase.
  static List<TherapyGoal> parseGoals(
    Iterable<MapEntry<String, Map<String, dynamic>>> docs, {
    DiagnosticLogger? logger,
  }) {
    final goals = <TherapyGoal>[];
    for (final doc in docs) {
      final parsed = TherapyGoal.parse(doc.key, doc.value);
      if (!parsed.isOk) {
        logger?.warn('GoalService', 'Malformed goal skipped', {
          'id': doc.key,
          'reason': parsed.error,
        });
        continue;
      }
      if (parsed.repaired.isNotEmpty) {
        logger?.info('GoalService', 'Goal repaired', {
          'id': doc.key,
          'fields': parsed.repaired,
        });
      }
      goals.add(parsed.value!);
    }
    goals.sort(TherapyGoal.displayOrder);
    return goals;
  }
}
