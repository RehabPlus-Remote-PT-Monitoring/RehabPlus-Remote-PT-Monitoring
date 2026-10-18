import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';
import '../models/chat.dart';
import '../models/firestore_fields.dart';
import 'firestore_diagnostics.dart';

/// Messaging between the signed-in patient and clinic staff.
///
/// Patient messages are written here; staff replies are written by the
/// Laravel dashboard (see API_CONTRACT.md). Writes are not awaited past the
/// local cache, so sending works offline and syncs on reconnect.
///
/// Log events (tag 'ChatService'), never including message text:
///   "Thread summary/Messages stream started|first snapshot|error|stopped"
///     {thread, docs, fromCache, ms}
///   "Malformed message skipped" {thread, id, reason}
///   "Message queued" {thread, length, clipped}; "Message synced / sync
///     failed" {thread, code, ms}
///   "Mark read synced / sync failed" {thread}
///   "Clinic phone loaded" {configured, fromCache}
class ChatService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  final _logger = DiagnosticLogger.I;

  /// How many of the newest messages a conversation shows.
  static const int messageLimit = 200;

  DocumentReference<Map<String, dynamic>> _thread(ChatThread t) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    return _db
        .collection('patients')
        .doc(uid)
        .collection('threads')
        .doc(t.name);
  }

  /// Live thread summary (last message preview and unread badge).
  /// Throws [StateError] when signed out.
  Stream<ChatThreadSummary> summary(ChatThread t) => observeStream(
    _thread(t).snapshots(),
    tag: 'ChatService',
    name: 'Thread summary',
    data: {'thread': t.name},
    describe: describeDoc,
  ).map((doc) => ChatThreadSummary.fromMap(doc.data()));

  /// Newest first (for a reversed ListView). A malformed message is left
  /// out (and logged) instead of breaking the whole conversation.
  /// Throws [StateError] when signed out.
  Stream<List<ChatMessage>> messages(ChatThread t) => observeStream(
    _thread(t)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(messageLimit)
        .snapshots(),
    tag: 'ChatService',
    name: 'Messages',
    data: {'thread': t.name},
    describe: describeQuery,
  ).map((snap) => _parseMessages(t, snap));

  List<ChatMessage> _parseMessages(
    ChatThread t,
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final messages = <ChatMessage>[];
    for (final doc in snap.docs) {
      final parsed = ChatMessage.parse(
        doc.id,
        doc.data(),
        pending: doc.metadata.hasPendingWrites,
      );
      if (parsed.isOk) {
        messages.add(parsed.value!);
      } else {
        _logger.warn('ChatService', 'Malformed message skipped', {
          'thread': t.name,
          'id': doc.id,
          'reason': parsed.error,
        });
      }
    }
    return messages;
  }

  /// Sends [text] as the patient. Returns at once; the message shows as
  /// pending until it reaches the server.
  ///
  /// Text longer than [ChatMessage.maxTextLength] is clipped (the rules
  /// would reject the whole message otherwise). Throws [ArgumentError] for
  /// blank text and [StateError] when signed out.
  void send(ChatThread t, String text) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    if (text.trim().isEmpty) {
      throw ArgumentError.value('', 'text', 'Message is empty');
    }
    final body = clipText(text, ChatMessage.maxTextLength);
    final clipped = body.length != text.length;

    final thread = _thread(t);
    final now = Timestamp.now();
    // One batch, so the message and the thread preview/unread counter are
    // applied together or not at all.
    final batch = _db.batch()
      ..set(thread.collection('messages').doc(), {
        'text': body,
        'senderId': uid,
        'senderRole': 'patient',
        'sentAt': now,
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..set(thread, {
        'lastMessage': body,
        'lastMessageAt': now,
        'lastSenderRole': 'patient',
        'unreadForStaff': FieldValue.increment(1),
      }, SetOptions(merge: true));

    _logger.info('ChatService', 'Message queued', {
      'thread': t.name,
      'length': body.length,
      if (clipped) 'clipped': true,
    });
    logUnawaitedWrite(
      batch.commit(),
      tag: 'ChatService',
      operation: 'Message',
      data: {'thread': t.name},
    );
  }

  /// Clears the patient's unread badge for [t].
  void markRead(ChatThread t) {
    logUnawaitedWrite(
      _thread(t).set({'unreadForPatient': 0}, SetOptions(merge: true)),
      tag: 'ChatService',
      operation: 'Mark read',
      data: {'thread': t.name},
    );
  }

  /// Clinic phone number from settings/clinic, or null if not configured.
  /// Throws when it can't be read (offline with nothing cached).
  Future<String?> clinicPhone() async {
    final doc = await _logger.timed(
      'ChatService',
      'Load clinic phone',
      () => _db.collection('settings').doc('clinic').get(),
    );
    final raw = doc.data()?['phone'];
    final phone = raw is String ? raw.trim() : null;
    final configured = phone != null && phone.isNotEmpty;
    _logger.info('ChatService', 'Clinic phone loaded', {
      'configured': configured,
      'fromCache': doc.metadata.isFromCache,
    });
    return configured ? phone : null;
  }
}
