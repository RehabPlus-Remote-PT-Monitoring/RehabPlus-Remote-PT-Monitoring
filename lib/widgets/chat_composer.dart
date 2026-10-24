// lib/widgets/chat_composer.dart
//
// The bottom of a conversation, iMessage style:
//
//   * [ChatQuickReplies]: a row of capsule buttons with message starters
//     ("Book clinic visit"); tapping one fills the text box.
//   * [ChatComposer]: a rounded pill text field and a round teal send
//     button with an up arrow, greyed out and disabled while the box is
//     empty.
//
// Both only draw and report taps; the conversation screen sends.

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../core/responsive.dart';
import 'pressable.dart';

/// One quick-reply capsule.
class ChatQuickReply {
  const ChatQuickReply({
    required this.label,
    required this.text,
    required this.icon,
    this.iconColor,
  });

  /// What the capsule says.
  final String label;

  /// What it puts in the text box (the patient finishes the sentence).
  final String text;

  final IconData icon;

  /// Defaults to the teal accent.
  final Color? iconColor;
}

/// Capsule buttons with message starters, wrapped onto more lines when
/// they don't fit (so all of them stay visible and reachable).
class ChatQuickReplies extends StatelessWidget {
  const ChatQuickReplies({
    super.key,
    required this.replies,
    required this.onSelected,
  });

  final List<ChatQuickReply> replies;
  final ValueChanged<ChatQuickReply> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: palette.textPrimary,
      fontWeight: FontWeight.w600,
    );
    final capsuleColor = context.isDarkMode
        ? palette.surfaceMuted
        : palette.surface;

    return ReadableWidth(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            children: [
              for (final reply in replies)
                Pressable(
                  onTap: () => onSelected(reply),
                  semanticLabel: reply.label,
                  child: Padding(
                    // The capsule is 34 high; the padding makes the touch
                    // target 44 without making the capsule look chunky.
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 34),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: ShapeDecoration(
                        color: capsuleColor,
                        shape: StadiumBorder(
                          side: BorderSide(color: palette.divider, width: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            reply.icon,
                            size: 16,
                            color: reply.iconColor ?? AppPalette.teal,
                          ),
                          const SizedBox(width: 6),
                          // ExcludeSemantics: Pressable already reads the
                          // label, so it isn't announced twice.
                          ExcludeSemantics(
                            child: Text(reply.label, style: labelStyle),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill text field plus round send button. Sits at the very bottom of the
/// conversation and keeps clear of the home indicator / tab bar through the
/// SafeArea.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    this.maxLength,
    this.hintText = 'Message',
  });

  final TextEditingController controller;

  /// Called when the send button is tapped with some text in the box.
  final VoidCallback onSend;

  /// Hard cap on characters typed (no visible counter).
  final int? maxLength;

  final String hintText;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;

    // Every border is set explicitly: the app's InputDecorationTheme would
    // otherwise draw its own outline inside the pill.
    const noBorder = InputBorder.none;
    final field = TextField(
      controller: controller,
      minLines: 1,
      maxLines: 5,
      maxLength: maxLength,
      textCapitalization: TextCapitalization.sentences,
      style: textTheme.bodyLarge?.copyWith(color: palette.textPrimary),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: textTheme.bodyLarge?.copyWith(color: palette.textFaint),
        filled: false,
        border: noBorder,
        enabledBorder: noBorder,
        focusedBorder: noBorder,
        disabledBorder: noBorder,
        errorBorder: noBorder,
        focusedErrorBorder: noBorder,
        counterText: '',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 9),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: ReadableWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: palette.inputFill,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: field,
                  ),
                ),
                // Rebuilds only the button as the text changes.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => _SendButton(
                    onPressed: value.text.trim().isEmpty ? null : onSend,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 32 dp teal circle with an up arrow, inside a 44 dp touch target.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.onPressed});

  /// Null while there is nothing to send: the button greys out.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final palette = context.palette;
    return Tooltip(
      message: 'Send',
      child: Pressable(
        onTap: onPressed,
        pressedScale: 0.9,
        semanticLabel: 'Send',
        child: SizedBox(
          width: 44,
          height: 40,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: enabled ? AppPalette.teal : palette.textFaint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.arrow_up,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
