import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';
import '../models/exercise_model.dart';
import '../models/prescription.dart';

/// Loads the signed-in patient's active prescriptions and turns them into
/// [ExerciseConfig]s the pose screen can run.
class PrescriptionService {
  final _db = FirebaseFirestore.instance;
  final _logger = DiagnosticLogger.I;

  Future<List<ExerciseConfig>> loadAssignedExercises() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const [];

    final snap = await _db
        .collection('patients')
        .doc(uid)
        .collection('prescriptions')
        .where('active', isEqualTo: true)
        .get();

    final result = <ExerciseConfig>[];
    for (final doc in snap.docs) {
      final Prescription p;
      try {
        p = Prescription.fromMap(doc.id, doc.data());
      } catch (e) {
        _logger.warn('PrescriptionService', 'Malformed prescription', {
          'id': doc.id,
          'error': e.toString(),
        });
        continue;
      }

      final base = availableExercises
          .where((c) => c.type.name == p.exerciseType)
          .firstOrNull;
      if (base == null) {
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
      'count': result.length,
      'fromCache': snap.metadata.isFromCache,
    });
    return result;
  }
}
