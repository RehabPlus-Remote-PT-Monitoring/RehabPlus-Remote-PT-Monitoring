import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/diagnostic_logger.dart';
import '../models/chat.dart';

/// Messaging between the signed-in patient and clinic staff.
///
/// Patient messages are written here; staff replies are written by the
/// Laravel dashboard (see API_CONTRACT.md). Writes are not awaited past the
/// local cache, so sending works offline and syncs on reconnect.
class ChatService {
  final _db = FirebaseFirestore.instance;
  final _logger = DiagnosticLogger.I;

  DocumentReference<Map<String, dynamic>> _thread(ChatThread t) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    return _db
        .collection('patients')
        .doc(uid)
        .collection('threads')
        .doc(t.name);
  }

  Stream<ChatThreadSummary> summary(ChatThread t) =>
      _thread(t).snapshots().map((doc) {
        final d = doc.data();
        if (d == null) return ChatThreadSummary.empty;
        return ChatThreadSummary(
          lastMessage: d['lastMessage'] as String?,
          lastMessageAt: (d['lastMessageAt'] as Timestamp?)?.toDate(),
          unreadForPatient: (d['unreadForPatient'] as num?)?.toInt() ?? 0,
        );
      });

  /// Newest first (for a reversed ListView).
  Stream<List<ChatMessage>> messages(ChatThread t) => _thread(t)
      .collection('messages')
      .orderBy('sentAt', descending: true)
      .limit(200)
      .snapshots()
      .map(
        (snap) => snap.docs.map((doc) {
          final d = doc.data();
          return ChatMessage(
            id: doc.id,
            text: d['text'] as String? ?? '',
            fromPatient: d['senderRole'] == 'patient',
            sentAt: (d['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            pending: doc.metadata.hasPendingWrites,
          );
        }).toList(),
      );

  void send(ChatThread t, String text) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final thread = _thread(t);
    final now = Timestamp.now();
    final batch = _db.batch()
      ..set(thread.collection('messages').doc(), {
        'text': text,
        'senderId': uid,
        'senderRole': 'patient',
        'sentAt': now,
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..set(thread, {
        'lastMessage': text,
        'lastMessageAt': now,
        'lastSenderRole': 'patient',
        'unreadForStaff': FieldValue.increment(1),
      }, SetOptions(merge: true));

    unawaited(
      batch.commit().then(
        (_) =>
            _logger.info('ChatService', 'Message synced', {'thread': t.name}),
        onError: (Object e, StackTrace _) => _logger.error(
          'ChatService',
          'Message sync failed',
          {'thread': t.name, 'error': e.toString()},
        ),
      ),
    );
  }

  void markRead(ChatThread t) {
    unawaited(
      _thread(t)
          .set({'unreadForPatient': 0}, SetOptions(merge: true))
          .catchError(
            (Object e) => _logger.warn('ChatService', 'markRead failed', {
              'thread': t.name,
              'error': e.toString(),
            }),
          ),
    );
  }

  /// Clinic phone number from settings/clinic, or null if not configured.
  Future<String?> clinicPhone() async {
    final doc = await _db.collection('settings').doc('clinic').get();
    final phone = (doc.data()?['phone'] as String?)?.trim();
    return (phone == null || phone.isEmpty) ? null : phone;
  }
}
