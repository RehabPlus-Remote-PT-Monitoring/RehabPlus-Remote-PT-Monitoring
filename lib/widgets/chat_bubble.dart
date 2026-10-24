// lib/widgets/chat_bubble.dart
//
// iMessage-style pieces of a conversation:
//
//   * [ChatBubble]: one message. The patient's own messages sit on the right
//     in teal with white text; staff messages sit on the left in a neutral
//     grey/white bubble. The corner nearest the sender is smaller on the last
//     bubble of a run ("tail"), so a run of messages reads as one group.
//   * [ChatTimeLabel]: the small grey centred label above a group of
//     messages ("Today 9:41 AM").
//
// These widgets only draw; the conversation screen decides which bubble is
// the last of its group and which messages staff have seen.

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
// `show`: the full intl library also exports a TextDirection that clashes
// with Flutter's.
import 'package:intl/intl.dart' show DateFormat;

import '../core/app_palette.dart';
import '../models/chat.dart';

/// Corner radius of a bubble, and of its tail corner.
const double _bubbleRadius = 18;
const double _tailRadius = 4;

/// The text of a [ChatTimeLabel], following iOS Messages:
/// "Today 9:41 AM", "Yesterday 9:41 AM", "Monday 9:41 AM" within the last
/// week, otherwise "Mon, Oct 12 at 9:41 AM".
///
/// [now] is a parameter so tests can fix the date.
String chatTimeLabelText(DateTime sentAt, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(sentAt.year, sentAt.month, sentAt.day);
  final daysAgo = today.difference(day).inDays;
  final time = DateFormat.jm().format(sentAt);
  if (daysAgo == 0) return 'Today $time';
  if (daysAgo == 1) return 'Yesterday $time';
  if (daysAgo > 1 && daysAgo < 7) {
    return '${DateFormat.EEEE().format(sentAt)} $time';
  }
  return "${DateFormat('EEE, MMM d').format(sentAt)} at $time";
}

/// Small grey centred label that starts a group of messages.
class ChatTimeLabel extends StatelessWidget {
  const ChatTimeLabel({super.key, required this.sentAt});

  final DateTime sentAt;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: context.palette.textMuted,
      fontWeight: FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Center(
        child: Text(chatTimeLabelText(sentAt, DateTime.now()), style: style),
      ),
    );
  }
}

/// One message bubble with, for the patient's own messages, a delivery
/// receipt next to it (clock while sending, one tick once on the server,
/// two teal ticks once staff have seen it).
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    this.isLastInGroup = true,
    this.seen = false,
  });

  final ChatMessage message;

  /// The last (newest) bubble of a run from the same sender: it gets the
  /// tail corner and a little more space below it.
  final bool isLastInGroup;

  /// Staff have opened the conversation since this (patient) message.
  final bool seen;

  /// Bubbles stop at about three quarters of the width, like iMessage, so
  /// it stays obvious which side a message is on.
  static const double _maxWidthFraction = 0.75;

  BorderRadius _shape(bool mine) {
    const round = Radius.circular(_bubbleRadius);
    const tail = Radius.circular(_tailRadius);
    if (!isLastInGroup) return const BorderRadius.all(round);
    return BorderRadius.only(
      topLeft: round,
      topRight: round,
      bottomLeft: mine ? round : tail,
      bottomRight: mine ? tail : round,
    );
  }

  Widget _receipt(AppPalette palette) {
    final (IconData glyph, String label) = message.pending
        ? (CupertinoIcons.clock, 'Sending')
        : seen
        ? (Icons.done_all, 'Seen')
        : (Icons.done, 'Sent');
    return Semantics(
      label: label,
      child: Icon(
        glyph,
        size: 14,
        color: seen ? AppPalette.teal : palette.textMuted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mine = message.fromPatient;
    final palette = context.palette;

    // Incoming bubbles: white cards on the grey page in light mode, the
    // muted surface on the black page in dark mode.
    final incomingColor = context.isDarkMode
        ? palette.surfaceMuted
        : palette.surface;
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: mine ? Colors.white : palette.textPrimary,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: isLastInGroup ? 8 : 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxBubbleWidth = constraints.maxWidth * _maxWidthFraction;
          return Row(
            mainAxisAlignment: mine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: mine ? AppPalette.teal : incomingColor,
                    borderRadius: _shape(mine),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Text(message.text, style: textStyle),
                  ),
                ),
              ),
              if (mine) ...[const SizedBox(width: 4), _receipt(palette)],
            ],
          );
        },
      ),
    );
  }
}
