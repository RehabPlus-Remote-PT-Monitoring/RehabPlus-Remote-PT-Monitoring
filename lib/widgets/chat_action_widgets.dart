// lib/widgets/chat_action_widgets.dart
//
// The pieces of the chat's message actions (reply, edit, unsend, pin):
//   - ChatMessageActionBar: the Reply button and the "⋯" menu beside a
//     bubble (Reply nearest the bubble, "⋯" beyond it)
//   - ChatReplyQuote: the quoted message at the top of a reply's bubble
//   - ChatComposerContextBar: "Replying to …" / "Editing message" above
//     the message box
//   - ChatPinnedBanner: the thread's pinned message, under the app bar
//   - ChatUnsentPlaceholder: what an unsent (deleted) message shows
// The copy matches the dashboard (lib/services/chat_actions.dart).

import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../services/chat_actions.dart';

const Color _teal = Color(0xFF23A8AA);

/// Unsend is destructive, so its menu entry is red (as on the dashboard).
const Color _danger = Color(0xFFE5484D);

/// The label and icon of a "⋯" menu entry.
(String, IconData) chatActionLabel(ChatMessageAction action) =>
    switch (action) {
      ChatMessageAction.copy => ('Copy', Icons.copy_rounded),
      ChatMessageAction.pin => ('Pin', Icons.push_pin_outlined),
      ChatMessageAction.unpin => ('Unpin', Icons.push_pin),
      ChatMessageAction.edit => ('Edit', Icons.edit_outlined),
      ChatMessageAction.unsend => ('Unsend', Icons.undo_rounded),
    };

/// Reply and "⋯" beside a bubble. For the patient's own messages (on the
/// right) the bar sits left of the bubble: "⋯" then Reply. For the other
/// side's it sits right of it, mirrored. Either button may be absent.
class ChatMessageActionBar extends StatelessWidget {
  const ChatMessageActionBar({
    super.key,
    required this.mine,
    required this.actions,
    this.onReply,
    required this.onAction,
  });

  /// The patient's own message (the bar is on the bubble's left).
  final bool mine;

  /// The "⋯" menu's entries; empty hides the menu button.
  final List<ChatMessageAction> actions;

  /// Null hides the Reply button.
  final VoidCallback? onReply;

  final ValueChanged<ChatMessageAction> onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reply = onReply == null
        ? null
        : _RoundButton(
            tooltip: 'Reply',
            icon: Icons.reply_rounded,
            onPressed: onReply!,
          );
    final menu = actions.isEmpty
        ? null
        : PopupMenuButton<ChatMessageAction>(
            tooltip: 'More',
            onSelected: onAction,
            color: palette.surface,
            position: PopupMenuPosition.under,
            itemBuilder: (context) => [
              for (final action in actions)
                PopupMenuItem(
                  value: action,
                  child: _MenuEntry(action: action),
                ),
            ],
            child: const _RoundButton(
              tooltip: null, // the PopupMenuButton has it
              icon: Icons.more_horiz,
            ),
          );
    final ordered = mine ? [menu, reply] : [reply, menu];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final button in ordered.nonNulls)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: button,
          ),
      ],
    );
  }
}

class _MenuEntry extends StatelessWidget {
  const _MenuEntry({required this.action});

  final ChatMessageAction action;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = chatActionLabel(action);
    final color = action == ChatMessageAction.unsend
        ? _danger
        : context.palette.textPrimary;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: 16),
        Icon(icon, size: 20, color: color),
      ],
    );
  }
}

/// A small round button on the chat gradient. Without [onPressed] it is
/// only the look (the popup menu supplies the tap).
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    this.onPressed,
  });

  final String? tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final circle = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.9),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: palette.textSecondary),
    );
    if (onPressed == null) return circle;
    return Tooltip(
      message: tooltip ?? '',
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: InkResponse(onTap: onPressed, radius: 22, child: circle),
      ),
    );
  }
}

/// The quoted message at the top of a reply's bubble: who wrote it and a
/// snippet. [onBubble] is the bubble's text colour, so the quote reads on
/// both the teal (own) and the surface (other) bubbles.
class ChatReplyQuote extends StatelessWidget {
  const ChatReplyQuote({
    super.key,
    required this.senderLabel,
    required this.text,
    required this.onBubble,
  });

  final String senderLabel;
  final String text;
  final Color onBubble;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Reply to $senderLabel: $text',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        decoration: BoxDecoration(
          color: onBubble.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: onBubble.withValues(alpha: 0.6), width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              senderLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: onBubble,
              ),
            ),
            Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: onBubble.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Above the message box while replying or editing: what the next send
/// does, the message it applies to, and a button to cancel.
class ChatComposerContextBar extends StatelessWidget {
  const ChatComposerContextBar({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.onCancel,
    required this.cancelTooltip,
  });

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onCancel;
  final String cancelTooltip;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: const Border(left: BorderSide(color: _teal, width: 3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _teal),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _teal,
                  ),
                ),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: cancelTooltip,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 18, color: palette.textMuted),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

/// The thread's pinned message, at the top of the conversation, with a
/// button to unpin it (either side may).
class ChatPinnedBanner extends StatelessWidget {
  const ChatPinnedBanner({
    super.key,
    required this.senderLabel,
    required this.text,
    required this.onUnpin,
  });

  final String senderLabel;
  final String text;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: Row(
          children: [
            const Icon(Icons.push_pin, size: 18, color: _teal),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Pinned · $senderLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _teal,
                    ),
                  ),
                  Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: palette.textPrimary),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onUnpin, child: const Text('Unpin')),
          ],
        ),
      ),
    );
  }
}

/// In place of an unsent (deleted) message: no bubble, menu or ticks, only
/// an outlined note ("You deleted a message" / "Message deleted").
class ChatUnsentPlaceholder extends StatelessWidget {
  const ChatUnsentPlaceholder({super.key, required this.mine});

  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.block, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              mine ? kChatDeletedMineText : kChatDeletedText,
              style: const TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
