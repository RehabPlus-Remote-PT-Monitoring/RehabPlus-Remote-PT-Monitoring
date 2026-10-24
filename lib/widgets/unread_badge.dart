import 'package:flutter/material.dart';

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
