// Defensive parsing of ChatMessage with the new optional action fields
// (replyTo, editedAt, unsent, unsentAt, session).
//
// Firestore has no schema and the dashboard writes with a service account
// that bypasses the rules, so the parser must tolerate any shape and never
// throw. Old documents (five core fields only) keep working, and a message
// that was never sent must still be recoverable even when its text is empty.

import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/models/chat.dart';

void main() {
  /// The five core fields an old document carries: id, text, senderRole,
  /// sentAt, and the optional pending flag.
  final core = {
    'id': 'm1',
    'text': 'hello',
    'senderRole': 'patient',
    'sentAt': DateTime(2026, 10, 1, 9, 0),
  };

  group('ChatMessage.parse', () {
    test('five core fields only: optional fields come back null', () {
      final parsed = ChatMessage.parse('m1', core);
      expect(parsed.isOk, isTrue);
      final msg = parsed.value!;
      expect(msg.id, 'm1');
      expect(msg.replyTo, isNull);
      expect(msg.editedAt, isNull);
      expect(msg.unsent, isFalse);
      expect(msg.unsentAt, isNull);
      expect(msg.session, isNull);
    });

    test('unsent, editedAt, replyTo and session are read', () {
      final doc = {
        ...core,
        'unsent': true,
        'unsentAt': '2026-10-01T09:00:05',
        'editedAt': '2026-10-01T09:05:00',
        'replyTo': {'id': 'm0', 'text': 'quoted', 'senderRole': 'staff'},
        'session': {'id': 's1', 'name': 'therapist'},
      };
      final parsed = ChatMessage.parse('m1', doc);
      expect(parsed.isOk, isTrue);
      final msg = parsed.value!;
      expect(msg.unsent, isTrue);
      expect(msg.unsentAt, DateTime(2026, 10, 1, 9, 0, 5));
      expect(msg.editedAt, DateTime(2026, 10, 1, 9, 5));
      expect(msg.replyTo, {
        'id': 'm0',
        'text': 'quoted',
        'senderRole': 'staff',
      });
      expect(msg.session, {'id': 's1', 'name': 'therapist'});
    });

    test('an unsent message with empty text is kept, not dropped', () {
      // Before the fix, requireString threw on text='' so an unsent message
      // encoded solely as text='' could never be parsed.
      final doc = {...core, 'text': '', 'unsent': true};
      final parsed = ChatMessage.parse('m1', doc);
      expect(parsed.isOk, isTrue);
      expect(parsed.value!.text, '');
      expect(parsed.value!.unsent, isTrue);
    });

    test('a non-unsent message with empty text is still rejected', () {
      // The safety net: only unsent messages may carry empty text.
      final doc = {...core, 'text': ''};
      expect(ChatMessage.parse('m1', doc).isOk, isFalse);
    });
  });

  group('ChatMessage.editedLabel (UI only)', () {
    test('is "Edited" whenever editedAt is present', () {
      final withEdit = ChatMessage(
        id: 'm1',
        text: 'hi',
        fromPatient: false,
        sentAt: DateTime(2026, 10, 1, 9, 0),
        editedAt: DateTime(2026, 10, 1, 9, 5),
      );
      expect(withEdit.editedLabel, 'Edited');
    });

    test('is null when editedAt is absent', () {
      final withoutEdit = ChatMessage(
        id: 'm1',
        text: 'hi',
        fromPatient: false,
        sentAt: DateTime(2026, 10, 1, 9, 0),
      );
      expect(withoutEdit.editedLabel, isNull);
    });
  });
}
