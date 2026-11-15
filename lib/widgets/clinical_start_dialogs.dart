// lib/widgets/clinical_start_dialogs.dart
//
// The clinician's safeguards before an exercise starts (design doc §2):
//   - an exercise the clinician restricted can't be started at all;
//   - with low exercise tolerance, a caution is confirmed first.
// The decision is a pure function ([checkExerciseStart], unit-tested); the
// dialogs only show it. Used by AnimatedExerciseCard._startExercise and, via
// [confirmClinicalStart], by every other Start button (the How-to-do-it
// sheet, Today's plan), so no button can open the camera for a restricted
// exercise.

import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../models/clinical_profile.dart';
import '../models/exercise_model.dart';

/// What has to happen before [type] may start.
enum ExerciseStartCheck {
  /// No clinical profile, or nothing in it applies: start as usual.
  allowed,

  /// Paused by the clinician: never open the camera screen.
  restricted,

  /// Low tolerance: ask the patient to confirm the caution first.
  caution,
}

/// Decides [ExerciseStartCheck] for [type]. A null [profile] (none set, or
/// it couldn't be read) means the app behaves exactly as before.
ExerciseStartCheck checkExerciseStart(
  ClinicalProfile? profile,
  ExerciseType type,
) {
  if (profile == null) return ExerciseStartCheck.allowed;
  if (profile.restricts(type)) return ExerciseStartCheck.restricted;
  if (profile.lowTolerance) return ExerciseStartCheck.caution;
  return ExerciseStartCheck.allowed;
}

/// The caution text, e.g. "Your clinician noted low exercise tolerance:
/// gets dizzy after 5 minutes. Stop if pain increases."
String lowToleranceMessage(String? toleranceNote) {
  final note = toleranceNote?.trim() ?? '';
  if (note.isEmpty) {
    return 'Your clinician noted low exercise tolerance. '
        'Stop if pain increases.';
  }
  final sentence = note.endsWith('.')
      ? note.substring(0, note.length - 1)
      : note;
  return 'Your clinician noted low exercise tolerance: $sentence. '
      'Stop if pain increases.';
}

/// Explains that [exerciseTitle] is paused by the clinician.
Future<void> showRestrictedExerciseDialog(
  BuildContext context,
  String exerciseTitle,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: context.palette.surface,
      icon: const Icon(Icons.lock_rounded, color: AppPalette.teal),
      title: Text(
        'Paused by your clinician',
        style: TextStyle(color: context.palette.textPrimary),
      ),
      content: Text(
        '$exerciseTitle is paused by your clinician, so it can\'t be started '
        'for now. Message your therapist if you have questions about it.',
        style: TextStyle(color: context.palette.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK', style: TextStyle(color: AppPalette.teal)),
        ),
      ],
    ),
  );
}

/// Shows the low-tolerance caution. True when the patient chose Start.
Future<bool> confirmLowToleranceStart(
  BuildContext context,
  String? toleranceNote,
) async {
  final start = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: context.palette.surface,
      icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFF9A825)),
      title: Text(
        'Take it easy',
        style: TextStyle(color: context.palette.textPrimary),
      ),
      content: Text(
        lowToleranceMessage(toleranceNote),
        style: TextStyle(color: context.palette.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Cancel',
            style: TextStyle(color: context.palette.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text(
            'Start',
            style: TextStyle(
              color: AppPalette.teal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
  return start ?? false; // dismissed by tapping outside = don't start
}

/// The whole safeguard for one Start button: shows the restricted dialog or
/// the low-tolerance caution as needed, logs the outcome with [source] (which
/// button), and returns true only when the exercise may start.
Future<bool> confirmClinicalStart(
  BuildContext context,
  ClinicalProfile? profile,
  ExerciseConfig config, {
  required String source,
}) async {
  final logData = {'type': config.type.name, 'source': source};
  switch (checkExerciseStart(profile, config.type)) {
    case ExerciseStartCheck.allowed:
      return true;
    case ExerciseStartCheck.restricted:
      DiagnosticLogger.I.info(_tag, 'Restricted exercise blocked', logData);
      await showRestrictedExerciseDialog(context, config.title);
      return false;
    case ExerciseStartCheck.caution:
      final start = await confirmLowToleranceStart(
        context,
        profile?.toleranceNote,
      );
      DiagnosticLogger.I.info(_tag, 'Low tolerance caution', {
        ...logData,
        'started': start,
      });
      return start;
  }
}

const String _tag = 'ClinicalStart';
