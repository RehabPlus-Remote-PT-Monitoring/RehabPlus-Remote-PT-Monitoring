// lib/models/chat.dart
//
// Patient ↔ clinic messaging, stored at
// patients/{uid}/threads/{thread.name}/messages/{id} in Firestore.

import 'firestore_fields.dart';

/// Each patient has exactly two conversations.
enum ChatThread {
  /// The patient's assigned therapist.
  therapist,

  /// Clinic front desk: appointments, home visits, app problems.
  clinic;

  /// The thread called [name] ('therapist' / 'clinic'), or null for anything
  /// else (e.g. an unexpected value in a push payload).
  static ChatThread? tryParse(Object? name) =>
      values.where((t) => t.name == name).firstOrNull;
}

class ChatMessage {
  /// Message length limit (firestore.rules: validMessage, 1–1000 chars).
  static const int maxTextLength = 1000;

  final String id;
  final String text;
  final bool fromPatient;
  final DateTime sentAt;

  /// Still waiting to reach the server (e.g. sent while offline).
  final bool pending;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.fromPatient,
    required this.sentAt,
    this.pending = false,
  });

  /// Builds a message from its Firestore document. Throws [FormatException]
  /// when `text` is missing (there is nothing to show). A missing `sentAt`
  /// falls back to now; the query orders by `sentAt`, so in practice only
  /// a malformed document lacks it.
  factory ChatMessage.fromFirestore(
    String id,
    Map<String, dynamic> d, {
    bool pending = false,
  }) => _fromReader(id, FieldReader(d), pending);

  /// Like [ChatMessage.fromFirestore], but never throws.
  static Parsed<ChatMessage> parse(
    String id,
    Map<String, dynamic> d, {
    bool pending = false,
  }) => Parsed.guard((reader) => _fromReader(id, reader, pending), d);

  static ChatMessage _fromReader(String id, FieldReader r, bool pending) {
    final text = r.requireString('text');
    var sentAt = r.dateTime('sentAt');
    if (sentAt == null) {
      r.markRepaired('sentAt');
      sentAt = DateTime.now();
    }
    // Staff messages are written by the dashboard (no rules apply), so clip
    // anything absurdly long rather than render megabytes of text.
    const displayLimit = maxTextLength * 2;
    if (text.length > displayLimit) r.markRepaired('text');
    return ChatMessage(
      id: id,
      text: clipText(text, displayLimit),
      fromPatient: r.data['senderRole'] == 'patient',
      sentAt: sentAt,
      pending: pending,
    );
  }
}

/// The thread document: what the conversation list shows.
class ChatThreadSummary {
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadForPatient;

  /// Patient messages clinic staff haven't opened yet. The app adds 1 per
  /// message it sends and the dashboard resets it to 0 when staff open the
  /// conversation, so the newest [unreadForStaff] patient messages are unseen
  /// (see [seenByStaff]).
  final int unreadForStaff;

  const ChatThreadSummary({
    this.lastMessage,
    this.lastMessageAt,
    this.unreadForPatient = 0,
    this.unreadForStaff = 0,
  });

  static const empty = ChatThreadSummary();

  /// Builds the summary from the thread document; null data gives [empty].
  /// Never throws. A negative unread count (corrupt counter) shows as 0.
  factory ChatThreadSummary.fromMap(Map<String, dynamic>? d) {
    if (d == null) return empty;
    final r = FieldReader(d);
    return ChatThreadSummary(
      lastMessage: r.string(
        'lastMessage',
        maxLength: ChatMessage.maxTextLength,
      ),
      lastMessageAt: r.dateTime('lastMessageAt'),
      unreadForPatient: r.integer('unreadForPatient', min: 0) ?? 0,
      unreadForStaff: r.integer('unreadForStaff', min: 0) ?? 0,
    );
  }
}

/// Read receipts for the patient's own messages: the ids staff have seen.
///
/// Messages have no per-message read flag. The thread's `unreadForStaff`
/// counter goes up by one per patient message and the dashboard resets it to
/// 0 when staff open the chat, so the newest [unreadForStaff] patient messages
/// are unseen and every older one has been seen.
///
/// [newestFirst] is the list as the chat screen shows it (newest first).
/// Staff messages are never in the result. Pass a null [unreadForStaff] while
/// the summary hasn't loaded: nothing counts as seen then, so a message never
/// shows two ticks it hasn't earned.
Set<String> seenByStaff(List<ChatMessage> newestFirst, int? unreadForStaff) {
  if (unreadForStaff == null) return const {};
  final seen = <String>{};
  var unseenLeft = unreadForStaff;
  for (final msg in newestFirst) {
    if (!msg.fromPatient) continue;
    if (unseenLeft > 0) {
      unseenLeft--;
    } else {
      seen.add(msg.id);
    }
  }
  return seen;
}
