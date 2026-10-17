// lib/models/app_notification.dart
//
// An entry on the Notifications page, stored at
// patients/{uid}/notifications/{id}. Written by the server whenever it sends
// a push (so every push is also listed here), and by the app for its own
// events such as finishing an exercise.

class AppNotification {
  final String id;

  /// 'message', 'exercise_assigned', 'session_completed', 'reminder', or
  /// anything new the dashboard adds (shown with a generic icon).
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  /// Extra routing info, e.g. {'thread': 'therapist'} for messages.
  final Map<String, String> data;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
    this.data = const {},
  });
}
