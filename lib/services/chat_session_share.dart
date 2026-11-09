// lib/services/chat_session_share.dart
//
// Turns an exercise session into the text a patient sends their therapist
// from the chat ("Share a session"). It is sent as an ordinary text message,
// so the message schema, the rules and the dashboard don't change.

// `show`: the full intl library also exports a TextDirection that clashes
// with Flutter's.
import 'package:intl/intl.dart' show DateFormat;

import '../models/chat.dart';
import '../models/firestore_fields.dart';
import '../models/session.dart';

/// The message text for [session], for example:
///
///     Session summary - Knee Extension (Nov 7, 8:15 AM)
///     10/10 reps, accuracy 92%, pain 2/10 - ended early
///     Pain note: Sharp at the end
///
/// Accuracy and pain are left out when the session has none (a session
/// with no scored reps would otherwise read "accuracy 0%", which is wrong,
/// not bad). The result is clipped to [ChatMessage.maxTextLength], so a long
/// pain note can never make the rules reject the message.
String sessionShareText(ExerciseSession session) {
  final when = DateFormat('MMM d, h:mm a').format(session.startTime);
  final header = 'Session summary - ${session.exerciseName} ($when)';

  final facts = <String>[
    '${session.completedReps}/${session.targetReps} reps',
    if (session.repComplianceScores.isNotEmpty)
      'accuracy ${(session.overallCompliance * 100).round()}%',
    if (session.painLevel != null)
      'pain ${session.painLevel}/${ExerciseSession.maxPainLevel}',
  ];
  var details = facts.join(', ');
  if (session.endedEarly) details += ' - ended early';

  final note = session.painNote?.trim() ?? '';
  final lines = [header, details, if (note.isNotEmpty) 'Pain note: $note'];
  return clipText(lines.join('\n'), ChatMessage.maxTextLength);
}
