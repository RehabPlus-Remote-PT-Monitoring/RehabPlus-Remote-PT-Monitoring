// lib/models/chat.dart
//
// Patient ↔ clinic messaging, stored at
// patients/{uid}/threads/{thread.name}/messages/{id} in Firestore.

/// Each patient has exactly two conversations.
enum ChatThread {
  /// The patient's assigned therapist.
  therapist,

  /// Clinic front desk: appointments, home visits, app problems.
  clinic,
}

class ChatMessage {
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
}

/// The thread document: what the conversation list shows.
class ChatThreadSummary {
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadForPatient;

  const ChatThreadSummary({
    this.lastMessage,
    this.lastMessageAt,
    this.unreadForPatient = 0,
  });

  static const empty = ChatThreadSummary();
}
