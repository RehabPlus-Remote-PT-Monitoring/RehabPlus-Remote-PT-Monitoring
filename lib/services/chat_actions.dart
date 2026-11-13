// lib/services/chat_actions.dart
//
// What each chat action writes to Firestore, and which actions a message
// offers. Pure functions, so the payloads are unit-tested without Firebase
// (test/chat_actions_test.dart); ChatService commits them.
//
// The shapes follow the shared contract with the dashboard
// (docs/superpowers/specs/2026-11-13-chat-actions-design.md, API_CONTRACT.md)
// and what firestore.rules accepts from the app:
//   - reply:  a normal message plus `replyTo: {id, text, senderRole}`
//   - edit:   `{text, editedAt: <server time>}`, own message only
//   - unsend: a soft delete: `{text: '', unsent: true, unsentAt: <server
//             time>}` with `replyTo` and `session` removed; the document
//             stays, so the chat keeps a placeholder in its place
//   - pin:    four fields on the thread (one pin per thread, both sides)
// None of them bumps an unread counter.

import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;

import '../models/chat.dart';
import '../models/firestore_fields.dart';

/// Shown in place of the other side's unsent message, and as the thread
/// preview when the newest message was unsent (same text as the dashboard).
const String kChatDeletedText = 'Message deleted';

/// Shown in place of the patient's own unsent message.
const String kChatDeletedMineText = 'You deleted a message';

/// Longest reply quote / pinned snippet stored (dashboard: SNIPPET_LENGTH).
const int kChatSnippetLength = 200;

/// The thread fields that hold the pin; unpinning removes all four.
const List<String> kChatPinFields = [
  'pinnedMessageId',
  'pinnedText',
  'pinnedSenderRole',
  'pinnedAt',
];

/// The text stored for a reply quote or a pin: trimmed, and cut with "..."
/// when longer than [kChatSnippetLength] (the dashboard's
/// `MessagePresenter::snippet`).
String chatSnippet(String text) {
  final trimmed = text.trim();
  if (trimmed.length <= kChatSnippetLength) return trimmed;
  return '${clipText(trimmed, kChatSnippetLength - 3).trimRight()}...';
}

String _senderRole(ChatMessage msg) => msg.fromPatient ? 'patient' : 'staff';

/// The `replyTo` stored on a reply to [quoted].
Map<String, dynamic> chatReplyQuote(ChatMessage quoted) => {
  'id': quoted.id,
  'text': chatSnippet(quoted.text),
  'senderRole': _senderRole(quoted),
};

/// The message update for an edit.
Map<String, dynamic> chatEditFields(String text) => {
  'text': text,
  'editedAt': FieldValue.serverTimestamp(),
};

/// The message update for an unsend (soft delete).
Map<String, dynamic> chatUnsendFields() => {
  'text': '',
  'unsent': true,
  'unsentAt': FieldValue.serverTimestamp(),
  'replyTo': FieldValue.delete(),
  'session': FieldValue.delete(),
};

/// The thread fields that pin [msg].
Map<String, dynamic> chatPinFields(ChatMessage msg) => {
  'pinnedMessageId': msg.id,
  'pinnedText': chatSnippet(msg.text),
  'pinnedSenderRole': _senderRole(msg),
  'pinnedAt': FieldValue.serverTimestamp(),
};

/// The thread fields that remove the pin.
Map<String, dynamic> chatUnpinFields() => {
  for (final field in kChatPinFields) field: FieldValue.delete(),
};

/// The thread update after an edit: the preview follows the newest message
/// only (`lastMessageAt` stays, as on the dashboard). Empty: no write.
Map<String, dynamic> chatThreadAfterEdit({
  required bool newest,
  required String text,
}) => newest ? {'lastMessage': text} : const {};

/// The thread update after an unsend: the preview when it was the newest
/// message, and the pin when it pointed at this message. Empty: no write.
Map<String, dynamic> chatThreadAfterUnsend({
  required bool newest,
  required bool pinned,
}) => {
  if (newest) 'lastMessage': kChatDeletedText,
  if (pinned) ...chatUnpinFields(),
};

/// The entries of a message's "⋯" menu, in display order.
enum ChatMessageAction { copy, pin, unpin, edit, unsend }

/// What the "⋯" menu offers for [msg] (empty: no menu), following the
/// design's table. An unsent message offers nothing. A message still
/// waiting to upload (pending) can only be copied, because the other
/// actions update a document the server may not have yet. Edit and Unsend
/// are for the patient's own messages; staff messages are changed on the
/// dashboard. Unlike the dashboard there is no 15-minute edit window: the
/// app has no server to enforce one.
List<ChatMessageAction> chatMenuActions(
  ChatMessage msg, {
  required String? pinnedMessageId,
}) {
  if (msg.unsent) return const [];
  return [
    ChatMessageAction.copy,
    if (!msg.pending) ...[
      pinnedMessageId == msg.id
          ? ChatMessageAction.unpin
          : ChatMessageAction.pin,
      if (msg.fromPatient) ...[
        ChatMessageAction.edit,
        ChatMessageAction.unsend,
      ],
    ],
  ];
}

/// Whether [msg] can be replied to (anything that isn't unsent).
bool chatCanReply(ChatMessage msg) => !msg.unsent;

/// [msg] as it reads after the patient edited it to [text] at [at].
ChatMessage chatEdited(ChatMessage msg, String text, DateTime at) =>
    ChatMessage(
      id: msg.id,
      text: text,
      fromPatient: msg.fromPatient,
      sentAt: msg.sentAt,
      replyTo: msg.replyTo,
      editedAt: at,
      session: msg.session,
    );

/// [msg] as it reads after the patient unsent it at [at]: no text, quote or
/// session card (what [chatUnsendFields] writes).
ChatMessage chatUnsent(ChatMessage msg, DateTime at) => ChatMessage(
  id: msg.id,
  text: '',
  fromPatient: msg.fromPatient,
  sentAt: msg.sentAt,
  unsent: true,
  unsentAt: at,
);
