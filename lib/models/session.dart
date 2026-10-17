import 'package:cloud_firestore/cloud_firestore.dart';

class ExerciseSession {
  final String id;
  final String exerciseId;
  final String exerciseName;
  final DateTime startTime;
  DateTime? endTime;
  int completedReps;
  int completedSets;
  final int targetReps;
  final int targetSets;
  List<double> repComplianceScores;
  String? notes;

  /// Prescription this session was done for (null for unassigned practice).
  final String? prescriptionId;

  /// Attempts not counted because of form or range.
  final int rejectedReps;

  /// Patient-reported pain after the session, 0 (none) to 10 (worst).
  int? painLevel;
  String? painNote;

  /// True when done outside the prescription's allowed days/hours.
  final bool outsideSchedule;

  /// True when the patient stopped before reaching the target reps.
  final bool endedEarly;

  ExerciseSession({
    required this.id,
    required this.exerciseId,
    required this.exerciseName,
    required this.startTime,
    required this.targetReps,
    required this.targetSets,
    this.endTime,
    this.completedReps = 0,
    this.completedSets = 0,
    this.repComplianceScores = const [],
    this.notes,
    this.prescriptionId,
    this.rejectedReps = 0,
    this.painLevel,
    this.painNote,
    this.outsideSchedule = false,
    this.endedEarly = false,
  });

  double get overallCompliance {
    if (repComplianceScores.isEmpty) return 0;
    return repComplianceScores.reduce((a, b) => a + b) /
        repComplianceScores.length;
  }

  double get repCompletionRate =>
      targetReps > 0 ? (completedReps / targetReps).clamp(0, 1) : 0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'exerciseId': exerciseId,
    'exerciseName': exerciseName,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'completedReps': completedReps,
    'completedSets': completedSets,
    'targetReps': targetReps,
    'targetSets': targetSets,
    'repComplianceScores': repComplianceScores,
    'notes': notes,
    'prescriptionId': prescriptionId,
    'rejectedReps': rejectedReps,
    'painLevel': painLevel,
    'painNote': painNote,
    'outsideSchedule': outsideSchedule,
    'endedEarly': endedEarly,
  };

  factory ExerciseSession.fromJson(Map<String, dynamic> json) =>
      ExerciseSession(
        id: json['id'],
        exerciseId: json['exerciseId'],
        exerciseName: json['exerciseName'],
        startTime: DateTime.parse(json['startTime']),
        endTime: json['endTime'] != null
            ? DateTime.parse(json['endTime'])
            : null,
        completedReps: json['completedReps'],
        completedSets: json['completedSets'],
        targetReps: json['targetReps'],
        targetSets: json['targetSets'],
        repComplianceScores: List<double>.from(json['repComplianceScores']),
        notes: json['notes'],
        prescriptionId: json['prescriptionId'],
        rejectedReps: json['rejectedReps'] ?? 0,
        painLevel: json['painLevel'],
        painNote: json['painNote'],
        outsideSchedule: json['outsideSchedule'] ?? false,
        endedEarly: json['endedEarly'] ?? false,
      );

  /// Firestore shape: same fields as [toJson] but with real Timestamps (so
  /// the dashboard can query by date) and the derived accuracy score.
  Map<String, dynamic> toFirestore() => {
    ...toJson()..remove('id'),
    'startTime': Timestamp.fromDate(startTime),
    'endTime': endTime == null ? null : Timestamp.fromDate(endTime!),
    'overallCompliance': overallCompliance,
    'createdAt': FieldValue.serverTimestamp(),
  };

  factory ExerciseSession.fromFirestore(String id, Map<String, dynamic> d) =>
      ExerciseSession(
        id: id,
        exerciseId: d['exerciseId'],
        exerciseName: d['exerciseName'],
        startTime: (d['startTime'] as Timestamp).toDate(),
        endTime: (d['endTime'] as Timestamp?)?.toDate(),
        completedReps: (d['completedReps'] as num).toInt(),
        completedSets: (d['completedSets'] as num).toInt(),
        targetReps: (d['targetReps'] as num).toInt(),
        targetSets: (d['targetSets'] as num).toInt(),
        repComplianceScores: (d['repComplianceScores'] as List? ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(),
        notes: d['notes'],
        prescriptionId: d['prescriptionId'],
        rejectedReps: (d['rejectedReps'] as num?)?.toInt() ?? 0,
        painLevel: (d['painLevel'] as num?)?.toInt(),
        painNote: d['painNote'],
        outsideSchedule: d['outsideSchedule'] ?? false,
        endedEarly: d['endedEarly'] ?? false,
      );
}
