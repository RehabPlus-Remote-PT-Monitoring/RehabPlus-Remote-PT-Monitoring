// Chat message actions (reply, edit, unsend, pin): what each one writes,
// which actions a message offers, the pinned-message summary, applying the
// and the action widgets. Pure logic
// and widgets, no Firebase (ChatService commits these payloads).

import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/models/chat.dart';
import 'package:rehabplus/services/chat_actions.dart';
import 'package:rehabplus/widgets/chat_action_widgets.dart';

final _at = DateTime(2026, 11, 13, 9, 0);

ChatMessage _msg(
  String id, {
  String? text,
  bool mine = true,
  bool pending = false,
  bool unsent = false,
  DateTime? sentAt,
}) => ChatMessage(
  id: id,
  text: text ?? (unsent ? '' : 'text of $id'),
  fromPatient: mine,
  sentAt: sentAt ?? _at,
  pending: pending,
  unsent: unsent,
);

void main() {
  group('chatSnippet (reply quote / pin text)', () {
    test('short text is trimmed and kept whole', () {
      expect(chatSnippet('  Do 10 squats.  '), 'Do 10 squats.');
      expect(chatSnippet('x' * kChatSnippetLength), 'x' * kChatSnippetLength);
    });

    test('long text is cut to the limit with "..." like the dashboard', () {
      final s = chatSnippet('y' * 500);
      expect(s.length, kChatSnippetLength);
      expect(s, endsWith('...'));
    });

    test('an emoji at the cut is not split in half', () {
      final s = chatSnippet('${'a' * 196}😀😀😀😀');
      expect(s, '${'a' * 196}...');
    });
  });

  group('payloads match the shared contract and firestore.rules', () {
    test('reply quote: id, snippet and sender role only', () {
      expect(chatReplyQuote(_msg('m1', text: ' hi ', mine: false)), {
        'id': 'm1',
        'text': 'hi',
        'senderRole': 'staff',
      });
      expect(chatReplyQuote(_msg('m2'))['senderRole'], 'patient');
    });

    test('edit writes the text and a server editedAt, nothing else', () {
      final f = chatEditFields('fixed');
      expect(f.keys, unorderedEquals(['text', 'editedAt']));
      expect(f['text'], 'fixed');
      expect(f['editedAt'], FieldValue.serverTimestamp());
    });

    test('unsend empties the text, flags it and removes quote and session', () {
      final f = chatUnsendFields();
      expect(
        f.keys,
        unorderedEquals(['text', 'unsent', 'unsentAt', 'replyTo', 'session']),
      );
      expect(f['text'], '');
      expect(f['unsent'], true);
      expect(f['unsentAt'], FieldValue.serverTimestamp());
      expect(f['replyTo'], FieldValue.delete());
      expect(f['session'], FieldValue.delete());
    });

    test(
      'pin stores id, snippet, role and server time; unpin removes all four',
      () {
        final pin = chatPinFields(
          _msg('m1', text: 'Remember ice', mine: false),
        );
        expect(pin.keys, unorderedEquals(kChatPinFields));
        expect(pin['pinnedMessageId'], 'm1');
        expect(pin['pinnedText'], 'Remember ice');
        expect(pin['pinnedSenderRole'], 'staff');
        expect(pin['pinnedAt'], FieldValue.serverTimestamp());
        final unpin = chatUnpinFields();
        expect(unpin.keys, unorderedEquals(kChatPinFields));
        expect(unpin.values, everyElement(FieldValue.delete()));
      },
    );

    test(
      'every edit and unsend marks the thread; the preview follows only the newest',
      () {
        final stamp = {kChatActionAtField: FieldValue.serverTimestamp()};
        expect(chatThreadAfterEdit(newest: true, pinned: false, text: 'new'), {
          ...stamp,
          'lastMessage': 'new',
        });
        expect(
          chatThreadAfterEdit(newest: false, pinned: false, text: 'new'),
          stamp,
        );
        expect(chatThreadAfterUnsend(newest: true, pinned: false), {
          ...stamp,
          'lastMessage': kChatDeletedText,
        });
        expect(chatThreadAfterUnsend(newest: false, pinned: false), stamp);
      },
    );

    test('editing the pinned message refreshes the banner text', () {
      final f = chatThreadAfterEdit(
        newest: false,
        pinned: true,
        text: '  Ice it  ',
      );
      expect(f['pinnedText'], 'Ice it');
      expect(f.containsKey('pinnedMessageId'), isFalse);
    });

    test('unsending the pinned message clears the pin in the same write', () {
      final f = chatThreadAfterUnsend(newest: false, pinned: true);
      expect(f.keys, unorderedEquals([...kChatPinFields, kChatActionAtField]));
      final both = chatThreadAfterUnsend(newest: true, pinned: true);
      expect(
        both.keys,
        unorderedEquals([...kChatPinFields, kChatActionAtField, 'lastMessage']),
      );
    });

    test('nothing touches an unread counter (no badge for an edit or pin)', () {
      final all = {
        ...chatEditFields('x'),
        ...chatUnsendFields(),
        ...chatPinFields(_msg('m')),
        ...chatThreadAfterUnsend(newest: true, pinned: true),
        ...chatThreadAfterEdit(newest: true, pinned: true, text: 'x'),
      };
      expect(all.keys.where((k) => k.startsWith('unread')), isEmpty);
    });
  });

  group('chatMenuActions (the "⋯" menu)', () {
    test("own message: copy, pin, edit, unsend; other side's: copy, pin", () {
      expect(chatMenuActions(_msg('m'), pinnedMessageId: null), [
        ChatMessageAction.copy,
        ChatMessageAction.pin,
        ChatMessageAction.edit,
        ChatMessageAction.unsend,
      ]);
      expect(chatMenuActions(_msg('m', mine: false), pinnedMessageId: null), [
        ChatMessageAction.copy,
        ChatMessageAction.pin,
      ]);
    });

    test('the pinned message offers Unpin instead of Pin', () {
      expect(chatMenuActions(_msg('m', mine: false), pinnedMessageId: 'm'), [
        ChatMessageAction.copy,
        ChatMessageAction.unpin,
      ]);
    });

    test('an unsent message offers nothing and cannot be replied to', () {
      final gone = _msg('m', unsent: true);
      expect(chatMenuActions(gone, pinnedMessageId: null), isEmpty);
      expect(chatCanReply(gone), isFalse);
      expect(chatCanReply(_msg('m', mine: false)), isTrue);
    });

    test('a message still uploading can only be copied', () {
      expect(chatMenuActions(_msg('m', pending: true), pinnedMessageId: null), [
        ChatMessageAction.copy,
      ]);
    });
  });

  group('local copies after the patient acts', () {
    final original = ChatMessage(
      id: 'm',
      text: 'old',
      fromPatient: true,
      sentAt: _at,
      replyTo: const {'id': 'q', 'text': 'quoted', 'senderRole': 'staff'},
    );

    test('edited: new text and "Edited", same id, time and quote', () {
      final e = chatEdited(original, 'new', _at);
      expect(e.text, 'new');
      expect(e.editedLabel, 'Edited');
      expect(e.sentAt, original.sentAt);
      expect(e.replyTo, original.replyTo);
    });

    test('unsent: no text, quote or label; keeps its place', () {
      final u = chatUnsent(original, _at);
      expect(u.unsent, isTrue);
      expect(u.text, '');
      expect(u.replyTo, isNull);
      expect(u.sentAt, original.sentAt);
    });
  });

  group('ChatThreadSummary pin', () {
    test('reads the pin the dashboard or the app stored', () {
      final s = ChatThreadSummary.fromMap({
        'pinnedMessageId': 'm1',
        'pinnedText': 'Remember ice',
        'pinnedSenderRole': 'patient',
      });
      expect(s.pin?.messageId, 'm1');
      expect(s.pin?.text, 'Remember ice');
      expect(s.pin?.fromPatient, isTrue);
    });

    test('no pin, a blank id or a wrong type means no banner', () {
      expect(ChatThreadSummary.fromMap({'lastMessage': 'hi'}).pin, isNull);
      expect(ChatThreadSummary.fromMap({'pinnedMessageId': ' '}).pin, isNull);
      expect(ChatThreadSummary.fromMap({'pinnedMessageId': 7}).pin, isNull);
    });
  });

  group('action widgets', () {
    Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

    testWidgets("own message: '⋯' left of Reply (Reply nearest the bubble)", (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          ChatMessageActionBar(
            mine: true,
            actions: const [ChatMessageAction.copy],
            onReply: () {},
            onAction: (_) {},
          ),
        ),
      );
      final more = tester.getCenter(find.byIcon(Icons.more_horiz)).dx;
      final reply = tester.getCenter(find.byIcon(Icons.reply_rounded)).dx;
      expect(more, lessThan(reply));
    });

    testWidgets("other side's message: mirrored, Reply first", (tester) async {
      await tester.pumpWidget(
        host(
          ChatMessageActionBar(
            mine: false,
            actions: const [ChatMessageAction.copy],
            onReply: () {},
            onAction: (_) {},
          ),
        ),
      );
      final more = tester.getCenter(find.byIcon(Icons.more_horiz)).dx;
      final reply = tester.getCenter(find.byIcon(Icons.reply_rounded)).dx;
      expect(reply, lessThan(more));
    });

    testWidgets('the menu lists its entries and reports the chosen one', (
      tester,
    ) async {
      ChatMessageAction? chosen;
      var replied = false;
      await tester.pumpWidget(
        host(
          ChatMessageActionBar(
            mine: true,
            actions: chatMenuActions(_msg('m'), pinnedMessageId: null),
            onReply: () => replied = true,
            onAction: (a) => chosen = a,
          ),
        ),
      );
      await tester.tap(find.byTooltip('Reply'));
      expect(replied, isTrue);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      for (final label in ['Copy', 'Pin', 'Edit', 'Unsend']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Unsend'));
      await tester.pumpAndSettle();
      expect(chosen, ChatMessageAction.unsend);
    });

    testWidgets('no menu entries and no reply: nothing is shown', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          ChatMessageActionBar(mine: true, actions: const [], onAction: (_) {}),
        ),
      );
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      expect(find.byIcon(Icons.reply_rounded), findsNothing);
    });

    testWidgets('unsent placeholder reads like the dashboard', (tester) async {
      await tester.pumpWidget(host(const ChatUnsentPlaceholder(mine: true)));
      expect(find.text('You deleted a message'), findsOneWidget);
      await tester.pumpWidget(host(const ChatUnsentPlaceholder(mine: false)));
      expect(find.text('Message deleted'), findsOneWidget);
    });

    testWidgets('pinned banner shows who and what, and unpins', (tester) async {
      var unpinned = false;
      await tester.pumpWidget(
        host(
          ChatPinnedBanner(
            senderLabel: 'Dr. Cruz',
            text: 'Ice after exercise',
            onUnpin: () => unpinned = true,
          ),
        ),
      );
      expect(find.text('Pinned · Dr. Cruz'), findsOneWidget);
      expect(find.text('Ice after exercise'), findsOneWidget);
      await tester.tap(find.text('Unpin'));
      expect(unpinned, isTrue);
    });

    testWidgets('composer bar shows the reply target and cancels', (
      tester,
    ) async {
      var cancelled = false;
      await tester.pumpWidget(
        host(
          ChatComposerContextBar(
            icon: Icons.reply_rounded,
            title: 'Replying to Dr. Cruz',
            text: 'Do 10 squats.',
            cancelTooltip: 'Cancel reply',
            onCancel: () => cancelled = true,
          ),
        ),
      );
      expect(find.text('Replying to Dr. Cruz'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel reply'));
      expect(cancelled, isTrue);
    });
  });
}
