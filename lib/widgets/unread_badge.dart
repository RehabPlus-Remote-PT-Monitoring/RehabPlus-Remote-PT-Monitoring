import 'dart:async';

import 'package:flutter/material.dart';

import '../core/diagnostic_logger.dart';
import '../models/chat.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';

/// Rebuilds [builder] with the live unread-notification count.
///
/// The Firestore listener is opened once per widget (not per build), and
/// NotificationService logs its errors. On an error the badge keeps its last
/// value (0 at first): a badge is not worth an error message.
class UnreadNotifications extends StatefulWidget {
  final Widget Function(BuildContext context, int unread) builder;

  const UnreadNotifications({super.key, required this.builder});

  @override
  State<UnreadNotifications> createState() => _UnreadNotificationsState();
}

class _UnreadNotificationsState extends State<UnreadNotifications> {
  late final Stream<int> _count = NotificationService().unreadCount();

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
    stream: _count,
    builder: (context, snap) => widget.builder(context, snap.data ?? 0),
  );
}

/// Rebuilds [builder] with the number of staff messages the patient hasn't
/// read yet, summed over every conversation (therapist + clinic). Drives the
/// badge on the Messages tab.
///
/// One listener per thread, opened once per widget. ChatService logs each
/// stream's errors; on an error the count keeps its last value, like the
/// notification badge above. Signed out (e.g. mid sign-out) counts as 0.
class UnreadMessages extends StatefulWidget {
  final Widget Function(BuildContext context, int unread) builder;

  const UnreadMessages({super.key, required this.builder});

  @override
  State<UnreadMessages> createState() => _UnreadMessagesState();
}

class _UnreadMessagesState extends State<UnreadMessages> {
  static const String _tag = 'UnreadMessages';

  /// Latest unread count per thread; the badge shows their sum.
  final Map<ChatThread, int> _unreadByThread = {};
  final List<StreamSubscription<ChatThreadSummary>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    for (final thread in ChatThread.values) {
      _listenTo(thread);
    }
  }

  void _listenTo(ChatThread thread) {
    final Stream<ChatThreadSummary> summary;
    try {
      summary = ChatService().summary(thread);
    } catch (e, st) {
      // Thrown synchronously when nobody is signed in: no badge then.
      DiagnosticLogger.I.warn(_tag, 'Thread summary unavailable', {
        'thread': thread.name,
      }, e, st);
      return;
    }
    _subscriptions.add(
      summary.listen(
        (s) {
          if (!mounted || _unreadByThread[thread] == s.unreadForPatient) {
            return;
          }
          setState(() => _unreadByThread[thread] = s.unreadForPatient);
        },
        onError: (Object e, StackTrace st) {
          // ChatService has already logged this error with its details;
          // note it here only so it is visible that the badge kept its
          // last value.
          DiagnosticLogger.I.verbose(_tag, 'Badge kept last value', {
            'thread': thread.name,
            'errorType': e.runtimeType.toString(),
          });
        },
      ),
    );
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var total = 0;
    for (final count in _unreadByThread.values) {
      total += count;
    }
    return widget.builder(context, total);
  }
}

/// The red iOS badge with a number (e.g. on the Messages tab).
///
/// Screen readers hear "[count] unread"; the tab merges it into its own
/// label so it reads "Messages, 2 unread".
class UnreadCountBadge extends StatelessWidget {
  const UnreadCountBadge({super.key, required this.count});

  final int count;

  /// iOS system red.
  static const Color _red = Color(0xFFFF3B30);

  @override
  Widget build(BuildContext context) {
    // "99+" keeps the badge small; the exact number is in the inbox.
    final text = count > 99 ? '99+' : '$count';
    return Semantics(
      label: '$count unread',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minWidth: 18),
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _red,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            text,
            // The badge has a fixed height, so it must not grow with the
            // text size setting.
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}
