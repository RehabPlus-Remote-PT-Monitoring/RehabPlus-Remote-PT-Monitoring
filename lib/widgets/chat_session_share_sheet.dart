// lib/widgets/chat_session_share_sheet.dart
//
// The "Share a session" sheet in the therapist chat: the patient's most
// recent sessions; tapping one returns it so the chat can send its summary
// (see sessionShareText) as an ordinary message.

import 'package:flutter/material.dart';
// `show`: the full intl library also exports a TextDirection that clashes
// with Flutter's.
import 'package:intl/intl.dart' show DateFormat;

import '../core/app_palette.dart';
import '../models/session.dart';

/// How many recent sessions the sheet offers. Enough to cover the last few
/// days of a typical plan without turning into a history screen.
const int kShareableSessionCount = 5;

/// Shows the sheet for [newestFirst] (the provider's session history) and
/// returns the session the patient picked, or null if they closed it.
Future<ExerciseSession?> showChatSessionShareSheet(
  BuildContext context,
  List<ExerciseSession> newestFirst,
) {
  final recent = newestFirst.take(kShareableSessionCount).toList();
  return showModalBottomSheet<ExerciseSession>(
    context: context,
    backgroundColor: context.palette.surface,
    showDragHandle: true,
    builder: (context) => _ShareSheet(sessions: recent),
  );
}

class _ShareSheet extends StatelessWidget {
  const _ShareSheet({required this.sessions});

  final List<ExerciseSession> sessions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              'Share a session',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Tap one to send its summary to your therapist.',
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
          ),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Text(
                'No sessions yet. Finish an exercise and it will show here.',
                style: TextStyle(fontSize: 14, color: palette.textMuted),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final session in sessions)
                    _SessionTile(
                      session: session,
                      onTap: () => Navigator.pop(context, session),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.onTap});

  final ExerciseSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final when = DateFormat('EEE, MMM d · h:mm a').format(session.startTime);
    final reps = '${session.completedReps}/${session.targetReps} reps';
    return ListTile(
      onTap: onTap,
      leading: const CircleAvatar(
        backgroundColor: AppPalette.teal,
        child: Icon(Icons.fitness_center, color: Colors.white, size: 20),
      ),
      title: Text(
        session.exerciseName,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
      ),
      subtitle: Text(
        '$when · $reps',
        style: TextStyle(fontSize: 12, color: palette.textSecondary),
      ),
      trailing: Icon(Icons.send_rounded, color: palette.textMuted, size: 20),
    );
  }
}
