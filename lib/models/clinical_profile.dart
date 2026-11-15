// lib/models/clinical_profile.dart
//
// The clinician-validated clinical and dietary profile, stored at
// patients/{uid}/clinical/profile. Written only by the clinic dashboard; the
// app reads it (API_CONTRACT.md, "Clinical safeguards").
//
// What it may change in the app, and nothing else:
//   - restrictedExercises: those exercises are locked ("Paused by your
//     clinician") and can't be started.
//   - lowTolerance: a caution is shown before every exercise.
// Precautions, dietary notes and nutrition flags are DISPLAY ONLY. They never
// change a prescription, a target or the completion gate ("diet informs
// context; clinical assessment dictates exercise rules").

import 'exercise_model.dart';
import 'firestore_fields.dart';

/// A nutrition flag from the fixed list in API_CONTRACT.md. Context only.
enum NutritionFlag {
  diabetes('diabetes', 'Diabetes'),
  hypertension('hypertension', 'High blood pressure'),
  lowIntake('low_intake', 'Low food intake'),
  dehydrationRisk('dehydration_risk', 'Dehydration risk'),
  anemia('anemia', 'Anemia'),
  weightManagement('weight_management', 'Weight management'),
  renalDiet('renal_diet', 'Kidney (renal) diet'),
  foodAllergy('food_allergy', 'Food allergy');

  const NutritionFlag(this.code, this.label);

  /// The code stored in Firestore, e.g. `low_intake`.
  final String code;

  /// What the patient sees, e.g. "Low food intake".
  final String label;

  /// The flag for a stored [code], or null for a code this app doesn't know.
  static NutritionFlag? fromCode(String code) {
    for (final flag in values) {
      if (flag.code == code) return flag;
    }
    return null;
  }
}

class ClinicalProfile {
  /// Longest texts kept (the dashboard enforces the same limits).
  static const int maxPrecautionsLength = 1000;
  static const int maxDietaryNotesLength = 1000;
  static const int maxToleranceNoteLength = 500;
  static const int maxNameLength = 100;

  const ClinicalProfile({
    this.precautions,
    this.dietaryNotes,
    this.nutritionFlags = const [],
    this.restrictedExercises = const {},
    this.lowTolerance = false,
    this.toleranceNote,
    this.validatedByName,
    this.validatedAt,
    this.nextReassessmentAt,
  });

  /// Medical precautions shown to the patient (null or blank = none).
  final String? precautions;

  /// Nutritional context, shown as context only.
  final String? dietaryNotes;

  /// Known nutrition flags in stored order, without duplicates.
  final List<NutritionFlag> nutritionFlags;

  /// Exercises the patient must not do. Unknown codes are dropped (a newer
  /// dashboard may restrict an exercise this app version doesn't have, and
  /// such an exercise can't be started here anyway).
  final Set<ExerciseType> restrictedExercises;

  /// Clinician judged exercise tolerance low: caution before each session.
  final bool lowTolerance;

  /// Why tolerance is low / what to watch.
  final String? toleranceNote;

  /// Name of the clinician who validated the profile.
  final String? validatedByName;
  final DateTime? validatedAt;

  /// Planned reassessment date, if any.
  final DateTime? nextReassessmentAt;

  /// True when [type] is locked by the clinician.
  bool restricts(ExerciseType type) => restrictedExercises.contains(type);

  /// True when the profile holds nothing the patient needs to see.
  bool get isEmpty =>
      _blank(precautions) &&
      _blank(dietaryNotes) &&
      nutritionFlags.isEmpty &&
      restrictedExercises.isEmpty &&
      !lowTolerance &&
      _blank(toleranceNote);

  static bool _blank(String? text) => text == null || text.trim().isEmpty;

  /// Parses the profile document. Never throws: every field is optional,
  /// so a bad field is defaulted and listed in [Parsed.repaired].
  static Parsed<ClinicalProfile> parse(Map<String, dynamic> data) =>
      Parsed.guard(_fromReader, data);

  static ClinicalProfile _fromReader(FieldReader r) {
    return ClinicalProfile(
      precautions: r.string('precautions', maxLength: maxPrecautionsLength),
      dietaryNotes: r.string('dietaryNotes', maxLength: maxDietaryNotesLength),
      nutritionFlags: _readNutritionFlags(r),
      restrictedExercises: _readRestrictedExercises(r),
      lowTolerance: r.boolean('lowTolerance'),
      toleranceNote: r.string(
        'toleranceNote',
        maxLength: maxToleranceNoteLength,
      ),
      validatedByName: r.string('validatedByName', maxLength: maxNameLength),
      validatedAt: r.dateTime('validatedAt'),
      nextReassessmentAt: r.dateTime('nextReassessmentAt'),
    );
  }

  /// Known flags in stored order. Unknown codes are ignored silently (a
  /// newer dashboard may add codes); non-string entries are reported.
  static List<NutritionFlag> _readNutritionFlags(FieldReader r) {
    final flags = <NutritionFlag>[];
    for (final value in r.list('nutritionFlags') ?? const <Object?>[]) {
      if (value is! String) {
        r.markRepaired('nutritionFlags');
        continue;
      }
      final flag = NutritionFlag.fromCode(value);
      if (flag != null && !flags.contains(flag)) flags.add(flag);
    }
    return flags;
  }

  /// Restricted exercise types this app knows. Unknown codes are ignored
  /// (see [restrictedExercises]); non-string entries are reported.
  static Set<ExerciseType> _readRestrictedExercises(FieldReader r) {
    final byName = {for (final type in ExerciseType.values) type.name: type};
    final restricted = <ExerciseType>{};
    for (final value in r.list('restrictedExercises') ?? const <Object?>[]) {
      if (value is! String) {
        r.markRepaired('restrictedExercises');
        continue;
      }
      final type = byName[value];
      if (type != null) restricted.add(type);
    }
    return restricted;
  }
}
