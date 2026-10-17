// lib/models/prescription.dart
//
// A therapist-assigned exercise, stored at
// patients/{patientUid}/prescriptions/{id} in Firestore.

/// When the patient is allowed to do an exercise unassisted.
class PrescriptionSchedule {
  /// Allowed weekdays, using [DateTime.weekday] numbering (1 = Mon … 7 = Sun).
  /// Empty means any day.
  final List<int> days;

  /// Allowed hours as [startHour, endHour), 24h clock in the phone's local
  /// time. Null means any time of day.
  final int? startHour;
  final int? endHour;

  const PrescriptionSchedule({
    this.days = const [],
    this.startHour,
    this.endHour,
  });

  bool allows(DateTime t) {
    if (days.isNotEmpty && !days.contains(t.weekday)) return false;
    if (startHour != null && t.hour < startHour!) return false;
    if (endHour != null && t.hour >= endHour!) return false;
    return true;
  }

  factory PrescriptionSchedule.fromMap(Map<String, dynamic> m) =>
      PrescriptionSchedule(
        days:
            (m['days'] as List?)?.map((d) => (d as num).toInt()).toList() ??
            const [],
        startHour: (m['startHour'] as num?)?.toInt(),
        endHour: (m['endHour'] as num?)?.toInt(),
      );
}

class Prescription {
  final String id;

  /// Matches an [ExerciseType] name, e.g. "kneeExtension".
  final String exerciseType;
  final int targetReps;
  final int? holdSeconds;
  final int frequencyPerWeek;
  final PrescriptionSchedule? schedule;
  final String? notes;

  const Prescription({
    required this.id,
    required this.exerciseType,
    required this.targetReps,
    required this.frequencyPerWeek,
    this.holdSeconds,
    this.schedule,
    this.notes,
  });

  bool isWithinSchedule(DateTime t) => schedule?.allows(t) ?? true;

  /// Whether [t]'s weekday is a scheduled day (ignores the hour window).
  bool isDueOn(DateTime t) {
    final days = schedule?.days ?? const [];
    return days.isEmpty || days.contains(t.weekday);
  }

  factory Prescription.fromMap(String id, Map<String, dynamic> m) =>
      Prescription(
        id: id,
        exerciseType: m['exerciseType'] as String,
        targetReps: (m['targetReps'] as num).toInt(),
        holdSeconds: (m['holdSeconds'] as num?)?.toInt(),
        frequencyPerWeek: (m['frequencyPerWeek'] as num?)?.toInt() ?? 3,
        schedule: m['schedule'] is Map
            ? PrescriptionSchedule.fromMap(
                Map<String, dynamic>.from(m['schedule'] as Map),
              )
            : null,
        notes: m['notes'] as String?,
      );
}
