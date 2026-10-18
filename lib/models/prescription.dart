// lib/models/prescription.dart
//
// A therapist-assigned exercise, stored at
// patients/{patientUid}/prescriptions/{id} in Firestore. Written only by the
// Laravel dashboard (service account, so the rules don't check it); the app
// therefore parses it defensively (see firestore_fields.dart).

import 'firestore_fields.dart';

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

  /// Parses `schedule`. Never throws: unknown weekdays are dropped, hours
  /// outside 0–23 / 0–24 are ignored, and a window whose start isn't before
  /// its end (which would block every hour) is treated as "any time".
  factory PrescriptionSchedule.fromMap(Map<String, dynamic> m) =>
      _fromReader(FieldReader(m));

  static PrescriptionSchedule _fromReader(FieldReader r) {
    final days = <int>{};
    for (final value in r.list('days') ?? const []) {
      final day = value is num && value.isFinite ? value.toInt() : null;
      if (day != null && day >= DateTime.monday && day <= DateTime.sunday) {
        days.add(day);
      } else {
        r.markRepaired('days');
      }
    }

    int? hour(String key, int max) {
      final value = r.data[key];
      if (value == null) return null;
      if (value is num && value.isFinite) {
        final h = value.toInt();
        if (h >= 0 && h <= max) return h;
      }
      r.markRepaired(key);
      return null;
    }

    var startHour = hour('startHour', 23);
    var endHour = hour('endHour', 24);
    if (startHour != null && endHour != null && startHour >= endHour) {
      r.markRepaired('hours');
      startHour = null;
      endHour = null;
    }

    return PrescriptionSchedule(
      days: days.toList()..sort(),
      startHour: startHour,
      endHour: endHour,
    );
  }
}

class Prescription {
  /// Sessions per week when the dashboard doesn't say (API_CONTRACT.md).
  static const int defaultFrequencyPerWeek = 3;

  /// Reps/holds above this are treated as corrupt and clamped.
  static const int maxTargetReps = 1000;

  /// Holds longer than this (10 minutes) are treated as corrupt and clamped.
  static const int maxHoldSeconds = 600;

  /// Longest instructions kept in memory.
  static const int maxNotesLength = 2000;

  final String id;

  /// Matches an [ExerciseType] name, e.g. "kneeExtension".
  final String exerciseType;
  final int targetReps;
  final int? holdSeconds;
  final int frequencyPerWeek;
  final PrescriptionSchedule? schedule;
  final String? notes;

  /// When the therapist assigned it (prescriptions/{id}.createdAt).
  final DateTime? assignedAt;

  const Prescription({
    required this.id,
    required this.exerciseType,
    required this.targetReps,
    required this.frequencyPerWeek,
    this.holdSeconds,
    this.schedule,
    this.notes,
    this.assignedAt,
  });

  bool isWithinSchedule(DateTime t) => schedule?.allows(t) ?? true;

  /// Whether [t]'s weekday is a scheduled day (ignores the hour window).
  bool isDueOn(DateTime t) {
    final days = schedule?.days ?? const [];
    return days.isEmpty || days.contains(t.weekday);
  }

  /// Builds a prescription from its Firestore document.
  ///
  /// Throws [FormatException] when `exerciseType` is missing or `targetReps`
  /// is missing / not a positive number (the exercise can't be run).
  /// Optional fields fall back to defaults; see [parse] for which did.
  factory Prescription.fromMap(String id, Map<String, dynamic> m) =>
      _fromReader(id, FieldReader(m));

  /// Like [Prescription.fromMap], but never throws.
  static Parsed<Prescription> parse(String id, Map<String, dynamic> m) =>
      Parsed.guard((reader) => _fromReader(id, reader), m);

  static Prescription _fromReader(String id, FieldReader r) {
    final exerciseType = r.requireString('exerciseType');

    final targetReps = r.integer('targetReps', max: maxTargetReps);
    if (targetReps == null || targetReps < 1) {
      throw const FormatException(
        'Missing or invalid required field "targetReps"',
      );
    }

    // 0 or negative means "use the exercise's default hold".
    var holdSeconds = r.integer('holdSeconds', max: maxHoldSeconds);
    if (holdSeconds != null && holdSeconds < 1) {
      r.markRepaired('holdSeconds');
      holdSeconds = null;
    }

    var frequency = r.integer('frequencyPerWeek');
    if (frequency != null && frequency < 1) {
      r.markRepaired('frequencyPerWeek');
      frequency = null;
    }

    final scheduleMap = r.map('schedule');
    return Prescription(
      id: id,
      exerciseType: exerciseType,
      targetReps: targetReps,
      holdSeconds: holdSeconds,
      frequencyPerWeek: frequency ?? defaultFrequencyPerWeek,
      schedule: scheduleMap == null ? null : _parseSchedule(scheduleMap, r),
      notes: r.string('notes', maxLength: maxNotesLength),
      assignedAt: r.dateTime('createdAt'),
    );
  }

  /// Parses the nested schedule and reports its repaired fields on [parent]
  /// as `schedule.<field>`.
  static PrescriptionSchedule _parseSchedule(
    Map<String, dynamic> map,
    FieldReader parent,
  ) {
    final reader = FieldReader(map);
    final schedule = PrescriptionSchedule._fromReader(reader);
    for (final field in reader.repaired) {
      parent.markRepaired('schedule.$field');
    }
    return schedule;
  }
}
