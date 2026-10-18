import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/diagnostic_logger.dart';

/// Daily "time for your exercises" reminder, scheduled on the phone (no
/// server involved). Android keeps it across reboots via the receivers in
/// AndroidManifest.xml. It's exact when the phone allows exact alarms
/// ("Alarms & reminders" permission); otherwise Android may deliver it up to
/// about an hour late to save battery. The app doesn't push patients into
/// that system setting.
class ReminderService {
  ReminderService._();
  static final ReminderService I = ReminderService._();

  static const int _id = 7001;

  final _plugin = FlutterLocalNotificationsPlugin();
  final _logger = DiagnosticLogger.I;
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (e) {
      // Unknown zone name: fall back to the clinic's.
      tz.setLocalLocation(tz.getLocation('Asia/Manila'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  /// Asks for notification permission (Android 13+) and schedules the daily
  /// reminder at [minutes] after midnight. Returns false if permission was
  /// refused.
  Future<bool> schedule(int minutes) async {
    await _init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final allowed = await android?.requestNotificationsPermission() ?? true;
    if (!allowed) return false;
    final exact = await android?.canScheduleExactNotifications() ?? false;

    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      minutes ~/ 60,
      minutes % 60,
    );
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      id: _id,
      scheduledDate: at,
      title: 'Time for your exercises',
      body: "Open RehabPlus to do today's exercises.",
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'exercise_reminders',
          'Exercise reminders',
          channelDescription: 'Your daily reminder to do your exercises',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // every day
    );
    _logger.info('ReminderService', 'Daily reminder scheduled', {
      'minutes': minutes,
      'exact': exact,
    });
    return true;
  }

  Future<void> cancel() async {
    await _init();
    await _plugin.cancel(id: _id);
    _logger.info('ReminderService', 'Daily reminder cancelled');
  }
}
