// lib/models/session.dart
//
// One exercise session, stored at patients/{uid}/sessions/{id}. Created by
// the app when the patient finishes (or ends early) and submits the pain
// check-in; never updated or deleted (see firestore.rules: validSession).

import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_fields.dart';

class ExerciseSession {
  /// Pain scale bounds (firestore.rules: painLevel 0..10).
  static const int minPainLevel = 0;
  static const int maxPainLevel = 10;

  /// Longest pain note the rules accept (painNote.size() <= 300).
  static const int maxPainNoteLength = 300;

  /// Upper bound for the app-generated summary; the rules refuse longer
  /// notes (notes.size() <= 2000), so [toFirestore] clips to it.
  static const int maxNotesLength = 2000;

  /// Longest exercise id / name the rules accept (size() <= 100).
  static const int maxNameLength = 100;

  /// Rep and set counts above this are treated as corrupt and clamped when
  /// read, and refused by the rules (validCount) when written.
  /// No prescription comes anywhere near it.
  static const int maxCount = 10000;

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

  /// Parses the [toJson] shape. Tolerates bad optional fields like
  /// [ExerciseSession.fromFirestore]; throws [FormatException] when `id`,
  /// `exerciseId` or `startTime` is missing.
  factory ExerciseSession.fromJson(Map<String, dynamic> json) {
    final reader = FieldReader(json);
    return _fromReader(reader.requireString('id'), reader);
  }

  /// Firestore shape: same fields as [toJson] but with real Timestamps (so
  /// the dashboard can query by date) and the derived accuracy score.
  ///
  /// The pain note is clipped to the rules' limit so a long note can never
  /// get the whole session rejected (the text field already limits it; this
  /// is the last line of defence).
  Map<String, dynamic> toFirestore() => {
    ...toJson()..remove('id'),
    // Clipped to the rules' limits (validSession) so a long title or note can
    // never get the whole session rejected.
    'exerciseName': clipText(exerciseName, maxNameLength),
    'notes': notes == null ? null : clipText(notes!, maxNotesLength),
    'startTime': Timestamp.fromDate(startTime),
    'endTime': endTime == null ? null : Timestamp.fromDate(endTime!),
    'painNote': painNote == null
        ? null
        : clipText(painNote!, maxPainNoteLength),
    'overallCompliance': overallCompliance,
    'createdAt': FieldValue.serverTimestamp(),
  };

  /// Builds a session from a Firestore document.
  ///
  /// Throws [FormatException] only when `exerciseId` or `startTime` is
  /// unusable (reports can't place such a session). Every other field falls
  /// back to a safe default; see [parseFirestore] to learn which ones did.
  factory ExerciseSession.fromFirestore(String id, Map<String, dynamic> d) =>
      _fromReader(id, FieldReader(d));

  /// Like [ExerciseSession.fromFirestore], but never throws: returns the
  /// session plus the names of repaired fields, or why it was unusable.
  static Parsed<ExerciseSession> parseFirestore(
    String id,
    Map<String, dynamic> d,
  ) => Parsed.guard((reader) => _fromReader(id, reader), d);

  /// Parses many documents at once (the session history). Pure and
  /// isolate-safe: takes and returns plain data only, so SessionStorage can
  /// run it on a background isolate for very large histories.
  static SessionParseBatch parseFirestoreBatch(
    List<(String id, Map<String, dynamic> data)> docs,
  ) {
    final sessions = <ExerciseSession>[];
    final skipped = <String, String>{};
    final repaired = <String, List<String>>{};
    for (final (id, data) in docs) {
      final parsed = parseFirestore(id, data);
      if (parsed.isOk) {
        sessions.add(parsed.value!);
        if (parsed.repaired.isNotEmpty) repaired[id] = parsed.repaired;
      } else {
        skipped[id] = parsed.error!;
      }
    }
    return SessionParseBatch(
      sessions: sessions,
      skipped: skipped,
      repaired: repaired,
    );
  }

  static ExerciseSession _fromReader(String id, FieldReader r) {
    final exerciseId = r.requireString('exerciseId');
    final startTime = r.requireDateTime('startTime');

    // An end before the start would give negative durations in reports.
    var endTime = r.dateTime('endTime');
    if (endTime != null && endTime.isBefore(startTime)) {
      r.markRepaired('endTime');
      endTime = null;
    }

    // Each score is 1.0 (counted) or 0.0 (rejected); keep only real numbers
    // and clamp into 0..1 so the accuracy average stays a percentage.
    final scores = <double>[];
    for (final value in r.list('repComplianceScores') ?? const []) {
      if (value is num && value.isFinite) {
        scores.add(
          clampToRange(
            value.toDouble(),
            min: 0,
            max: 1,
            onClamp: () => r.markRepaired('repComplianceScores'),
          ),
        );
      } else {
        r.markRepaired('repComplianceScores');
      }
    }

    return ExerciseSession(
      id: id,
      exerciseId: exerciseId,
      exerciseName: r.string('exerciseName') ?? exerciseId,
      startTime: startTime,
      endTime: endTime,
      completedReps: r.integer('completedReps', min: 0, max: maxCount) ?? 0,
      completedSets: r.integer('completedSets', min: 0, max: maxCount) ?? 0,
      targetReps: r.integer('targetReps', min: 0, max: maxCount) ?? 0,
      targetSets: r.integer('targetSets', min: 0, max: maxCount) ?? 0,
      repComplianceScores: scores,
      notes: r.string('notes', maxLength: maxNotesLength),
      prescriptionId: r.string('prescriptionId'),
      rejectedReps: r.integer('rejectedReps', min: 0, max: maxCount) ?? 0,
      // Out-of-range pain is CLAMPED rather than dropped: a "15" written by
      // a buggy client most likely means "very bad pain", and dropping it
      // would hide exactly the value the pain-safety rules must react to.
      painLevel: r.integer('painLevel', min: minPainLevel, max: maxPainLevel),
      painNote: r.string('painNote', maxLength: maxPainNoteLength),
      outsideSchedule: r.boolean('outsideSchedule'),
      endedEarly: r.boolean('endedEarly'),
    );
  }

  /// Fields that would make Firestore reject this session (validSession in
  /// firestore.rules), by name. Empty means it can be saved. Checked before
  /// writing so a bad session fails loudly here instead of being silently
  /// rolled back by the server later.
  List<String> firestoreProblems() => [
    if (exerciseId.trim().isEmpty || exerciseId.length > maxNameLength)
      'exerciseId',
    for (final (name, value) in [
      ('completedReps', completedReps),
      ('completedSets', completedSets),
      ('targetReps', targetReps),
      ('targetSets', targetSets),
      ('rejectedReps', rejectedReps),
    ])
      if (value < 0 || value > maxCount) name,
    if (repComplianceScores.length > maxCount) 'repComplianceScores',
    if (painLevel == null ||
        painLevel! < minPainLevel ||
        painLevel! > maxPainLevel)
      'painLevel',
  ];
}

/// Result of [ExerciseSession.parseFirestoreBatch]: the usable sessions in
/// input order, plus value-free diagnostics for the log.
class SessionParseBatch {
  const SessionParseBatch({
    required this.sessions,
    required this.skipped,
    required this.repaired,
  });

  final List<ExerciseSession> sessions;

  /// Document id -> why it was skipped.
  final Map<String, String> skipped;

  /// Document id -> fields that were replaced by defaults.
  final Map<String, List<String>> repaired;
}
