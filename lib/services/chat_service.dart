import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';
import '../models/chat.dart';
import '../models/firestore_fields.dart';
import 'chat_actions.dart';
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
///   "Message edit|unsend queued" {thread, ...}; "Pin|Unpin queued" {thread};
///     each followed by its "synced / sync failed" event
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
  /// [replyTo] makes it a reply: the message stores a short quote of it
  /// (see [chatReplyQuote]).
  ///
  /// Text longer than [ChatMessage.maxTextLength] is clipped (the rules
  /// would reject the whole message otherwise). Throws [ArgumentError] for
  /// blank text and [StateError] when signed out.
  void send(ChatThread t, String text, {ChatMessage? replyTo}) {
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
        if (replyTo != null) 'replyTo': chatReplyQuote(replyTo),
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
      if (replyTo != null) 'reply': true,
    });
    logUnawaitedWrite(
      batch.commit(),
      tag: 'ChatService',
      operation: 'Message',
      data: {'thread': t.name},
    );
  }

  /// Replaces the text of the patient's own [msg] with [text]. [newest]:
  /// [msg] is the newest message, so the thread preview follows the edit;
  /// [pinned]: it is the pinned message, so the banner text does too.
  /// Returns false (and writes nothing) when the text is unchanged.
  ///
  /// Like [send], returns at once and logs the sync result. Throws
  /// [ArgumentError] for blank text or a message the patient can't edit
  /// (someone else's, unsent, or still uploading), [StateError] when signed
  /// out.
  bool editMessage(
    ChatThread t,
    ChatMessage msg,
    String text, {
    required bool newest,
    required bool pinned,
  }) {
    _checkOwnAction(msg, ChatMessageAction.edit);
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value('', 'text', 'Message is empty');
    }
    final body = clipText(trimmed, ChatMessage.maxTextLength);
    if (body == msg.text) return false; // no "Edited" label for nothing
    final thread = _thread(t);
    final batch = _db.batch()
      ..update(thread.collection('messages').doc(msg.id), chatEditFields(body))
      ..set(
        thread,
        chatThreadAfterEdit(newest: newest, pinned: pinned, text: body),
        SetOptions(merge: true),
      );
    _logger.info('ChatService', 'Message edit queued', {
      'thread': t.name,
      'length': body.length,
      'newest': newest,
    });
    logUnawaitedWrite(
      batch.commit(),
      tag: 'ChatService',
      operation: 'Message edit',
      data: {'thread': t.name},
    );
    return true;
  }

  /// Unsends (soft-deletes) the patient's own [msg]: its text is emptied and
  /// both sides see a placeholder. [newest] fixes the thread preview;
  /// [pinned] (it is the thread's pinned message) clears the pin, in the
  /// same batch. Throws like [editMessage].
  void unsendMessage(
    ChatThread t,
    ChatMessage msg, {
    required bool newest,
    required bool pinned,
  }) {
    _checkOwnAction(msg, ChatMessageAction.unsend);
    final thread = _thread(t);
    final batch = _db.batch()
      ..update(thread.collection('messages').doc(msg.id), chatUnsendFields())
      ..set(
        thread,
        chatThreadAfterUnsend(newest: newest, pinned: pinned),
        SetOptions(merge: true),
      );
    _logger.info('ChatService', 'Message unsend queued', {
      'thread': t.name,
      'newest': newest,
      'pinned': pinned,
    });
    logUnawaitedWrite(
      batch.commit(),
      tag: 'ChatService',
      operation: 'Message unsend',
      data: {'thread': t.name},
    );
  }

  /// Pins [msg] for both sides, replacing any earlier pin. Throws
  /// [ArgumentError] for an unsent or still-uploading message.
  void pin(ChatThread t, ChatMessage msg) {
    if (msg.unsent || msg.pending) {
      throw ArgumentError.value(msg.id, 'msg', 'Message cannot be pinned');
    }
    _logger.info('ChatService', 'Pin queued', {'thread': t.name});
    logUnawaitedWrite(
      _thread(t).set(chatPinFields(msg), SetOptions(merge: true)),
      tag: 'ChatService',
      operation: 'Pin',
      data: {'thread': t.name},
    );
  }

  /// Removes the thread's pin, whoever set it.
  void unpin(ChatThread t) {
    _logger.info('ChatService', 'Unpin queued', {'thread': t.name});
    logUnawaitedWrite(
      _thread(t).set(chatUnpinFields(), SetOptions(merge: true)),
      tag: 'ChatService',
      operation: 'Unpin',
      data: {'thread': t.name},
    );
  }

  /// Edit and Unsend are offered only where [chatMenuActions] offers them;
  /// this repeats the check so a stale screen can't write a change the
  /// rules would refuse anyway.
  void _checkOwnAction(ChatMessage msg, ChatMessageAction action) {
    if (!chatMenuActions(msg, pinnedMessageId: null).contains(action)) {
      throw ArgumentError.value(msg.id, 'msg', 'Not allowed: ${action.name}');
    }
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
