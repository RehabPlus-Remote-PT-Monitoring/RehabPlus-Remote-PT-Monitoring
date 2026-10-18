import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';
import '../models/exercise_model.dart';
import '../models/prescription.dart';

/// Loads the signed-in patient's active prescriptions and turns them into
/// [ExerciseConfig]s the pose screen can run.
///
/// Log events (tag 'PrescriptionService'): "Load prescriptions done/failed"
/// {uid, ms}, "Loaded prescriptions" {count, docs, skipped, fromCache},
/// "Malformed prescription skipped" {id, reason}, "Prescription repaired"
/// {id, fields}, "Unknown exercise type" {id, exerciseType}.
class PrescriptionService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  final _logger = DiagnosticLogger.I;

  /// The app's exercise catalogue keyed by type code, built once. Lookups
  /// per prescription are then constant time instead of a list scan.
  static final Map<String, ExerciseConfig> _catalogue = {
    for (final config in availableExercises) config.type.name: config,
  };

  /// Active prescriptions as runnable exercises. Empty when signed out.
  /// Throws when Firestore can't be read at all (callers show a fallback);
  /// a single malformed or unknown prescription is skipped and logged.
  Future<List<ExerciseConfig>> loadAssignedExercises() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const [];

    final snap = await _logger.timed(
      'PrescriptionService',
      'Load prescriptions',
      () => _db
          .collection('patients')
          .doc(uid)
          .collection('prescriptions')
          .where('active', isEqualTo: true)
          .get(),
      data: {'uid': uid},
    );

    final result = <ExerciseConfig>[];
    var skipped = 0;
    for (final doc in snap.docs) {
      final parsed = Prescription.parse(doc.id, doc.data());
      final p = parsed.value;
      if (p == null) {
        skipped++;
        _logger.warn('PrescriptionService', 'Malformed prescription skipped', {
          'id': doc.id,
          'reason': parsed.error,
        });
        continue;
      }
      if (parsed.repaired.isNotEmpty) {
        _logger.warn('PrescriptionService', 'Prescription repaired', {
          'id': doc.id,
          'fields': parsed.repaired,
        });
      }

      final base = _catalogue[p.exerciseType];
      if (base == null) {
        // A type this app version doesn't know (API_CONTRACT.md: skipped).
        skipped++;
        _logger.warn('PrescriptionService', 'Unknown exercise type', {
          'id': doc.id,
          'exerciseType': p.exerciseType,
        });
        continue;
      }

      final hold = p.holdSeconds ?? base.holdSeconds;
      result.add(
        base.copyWith(
          targetReps: p.targetReps,
          holdSeconds: hold,
          repsText: hold > 0
              ? '${p.targetReps} Holds | $hold sec'
              : '1 Set | ${p.targetReps} Reps',
          prescription: p,
        ),
      );
    }

    _logger.info('PrescriptionService', 'Loaded prescriptions', {
      'uid': uid,
      'count': result.length,
      'docs': snap.size,
      'skipped': skipped,
      'fromCache': snap.metadata.isFromCache,
    });
    return result;
  }
}
