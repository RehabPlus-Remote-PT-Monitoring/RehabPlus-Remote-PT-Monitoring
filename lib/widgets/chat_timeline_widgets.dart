// lib/widgets/chat_timeline_widgets.dart
//
// The small markers between chat bubbles: the day separator chip, the
// "New messages" divider, and the top-of-list footer while older messages
// load. They sit on the chat's teal gradient: the chip is a surface-coloured
// pill (like the bubbles), the divider and footer are white text like the
// screen's other captions on the gradient, which reads in both themes.

import 'package:flutter/material.dart';

import '../core/app_palette.dart';

/// Text and lines drawn straight on the chat gradient.
const Color _onGradient = Colors.white;

/// "Today" / "Yesterday" / "Nov 3" centred above the first message of a day.
class ChatDaySeparator extends StatelessWidget {
  const ChatDaySeparator({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Center(
        child: Semantics(
          header: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: palette.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A line labelled "New messages" above the oldest reply that was unread
/// when the patient opened the chat.
class ChatNewMessagesDivider extends StatelessWidget {
  const ChatNewMessagesDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Divider(color: _onGradient, thickness: 1, height: 1),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'New messages',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _onGradient,
                letterSpacing: 0.3,
              ),
            ),
          ),
          line,
        ],
      ),
    );
  }
}

/// The last item of the reversed list (so the top of the screen): a spinner
/// while an older page loads, "Beginning of conversation" once the first
/// message is shown, otherwise nothing.
class ChatHistoryFooter extends StatelessWidget {
  const ChatHistoryFooter({
    super.key,
    required this.loading,
    required this.reachedStart,
    required this.failed,
  });

  final bool loading;
  final bool reachedStart;

  /// The last page failed to load; the patient can scroll up to retry.
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (loading) {
      child = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: _onGradient),
      );
    } else if (failed || reachedStart) {
      child = Text(
        failed
            ? "Couldn't load older messages. Scroll up to try again."
            : 'Beginning of conversation',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: _onGradient),
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(child: child),
    );
  }
}
