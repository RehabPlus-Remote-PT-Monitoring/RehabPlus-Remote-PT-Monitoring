// lib/models/app_notification.dart
//
// An entry on the Notifications page, stored at
// patients/{uid}/notifications/{id}. Written by the server whenever it sends
// a push (so every push is also listed here), and by the app for its own
// events such as finishing an exercise.

import 'firestore_fields.dart';

class AppNotification {
  /// Type used when a document has none (shown with a generic icon).
  static const String fallbackType = 'general';

  /// Title/body limits for entries the APP writes (firestore.rules: ≤ 100 /
  /// ≤ 300). Server-written entries aren't checked by the rules; when read
  /// they are clipped at a more generous [_displayFactor] times these, only
  /// to keep a corrupt document from flooding the screen.
  static const int maxTitleLength = 100;
  static const int maxBodyLength = 300;
  static const int _displayFactor = 4;

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

  /// Builds an entry from its Firestore document. Every field has a
  /// fallback, so this doesn't throw on bad data. `createdAt` is null only
  /// for a local write the server hasn't stamped yet; it is shown as "now".
  factory AppNotification.fromFirestore(String id, Map<String, dynamic> d) =>
      _fromReader(id, FieldReader(d));

  /// Like [AppNotification.fromFirestore], also returning repaired fields.
  static Parsed<AppNotification> parse(String id, Map<String, dynamic> d) =>
      Parsed.guard((reader) => _fromReader(id, reader), d);

  static AppNotification _fromReader(String id, FieldReader r) {
    // `data` holds routing hints such as the chat thread: only flat values
    // are kept; nested maps/lists are dropped.
    final data = <String, String>{};
    final raw = r.map('data') ?? const <String, dynamic>{};
    raw.forEach((key, value) {
      if (value is String || value is num || value is bool) {
        data[key] = '$value';
      } else if (value != null) {
        r.markRepaired('data.$key');
      }
    });

    return AppNotification(
      id: id,
      type: r.string('type') ?? fallbackType,
      title:
          r.string('title', maxLength: maxTitleLength * _displayFactor) ?? '',
      body: r.string('body', maxLength: maxBodyLength * _displayFactor) ?? '',
      createdAt: r.dateTime('createdAt') ?? DateTime.now(),
      read: r.boolean('read'),
      data: data,
    );
  }
}
