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
///
/// Log events (tag 'ReminderService'): "Initialized" {zone, fallbackZone},
/// "Daily reminder scheduled" {minutes, exact, nextInMinutes}, "Reminder
/// permission refused", "Daily reminder cancelled", "Schedule/Cancel
/// failed" + error.
class ReminderService {
  ReminderService._();
  static final ReminderService I = ReminderService._();

  static const int _id = 7001;

  /// Used when the phone reports a zone the timezone database doesn't know.
  static const String _fallbackZone = 'Asia/Manila';

  final _plugin = FlutterLocalNotificationsPlugin();
  final _logger = DiagnosticLogger.I;

  /// Shared by concurrent callers (e.g. a quick toggle off/on in Settings),
  /// so the plugin and time zone are set up exactly once. Cleared on
  /// failure so the next call can retry.
  Future<void>? _initFuture;

  Future<void> _init() {
    return _initFuture ??= _initOnce().catchError((Object e, StackTrace st) {
      _initFuture = null;
      _logger.error('ReminderService', 'Init failed', null, e, st);
      Error.throwWithStackTrace(e, st);
    });
  }

  Future<void> _initOnce() async {
    // Parses the bundled time-zone database (pure Dart, ~tens of ms). Kept on
    // the main isolate: the `timezone` package stores it in a global that
    // the scheduling code below reads, so building it elsewhere wouldn't help.
    tzdata.initializeTimeZones();
    var usedFallback = false;
    String zoneName;
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      zoneName = zone.identifier;
      tz.setLocalLocation(tz.getLocation(zoneName));
    } catch (e, st) {
      // Unknown zone name: fall back to the clinic's.
      _logger.warn('ReminderService', 'Phone time zone unknown; using clinic',
          {'fallbackZone': _fallbackZone}, e, st);
      usedFallback = true;
      zoneName = _fallbackZone;
      tz.setLocalLocation(tz.getLocation(_fallbackZone));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _logger.info('ReminderService', 'Initialized', {
      'zone': zoneName,
      'fallbackZone': usedFallback,
    });
  }

  /// Asks for notification permission (Android 13+) and schedules the daily
  /// reminder at [minutes] after midnight (0–1439). Returns false if
  /// permission was refused. Throws [ArgumentError] for an invalid time and
  /// re-throws plugin errors after logging them.
  Future<bool> schedule(int minutes) async {
    if (minutes < 0 || minutes >= 24 * 60) {
      throw ArgumentError.value(minutes, 'minutes', 'Not a time of day');
    }
    try {
      await _init();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final allowed = await android?.requestNotificationsPermission() ?? true;
      if (!allowed) {
        _logger.info('ReminderService', 'Reminder permission refused');
        return false;
      }
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
        'nextInMinutes': at.difference(now).inMinutes,
      });
      return true;
    } catch (e, st) {
      _logger.error('ReminderService', 'Schedule failed', {
        'minutes': minutes,
      }, e, st);
      rethrow;
    }
  }

  /// Cancels the daily reminder. Re-throws plugin errors after logging.
  Future<void> cancel() async {
    try {
      await _init();
      await _plugin.cancel(id: _id);
      _logger.info('ReminderService', 'Daily reminder cancelled');
    } catch (e, st) {
      _logger.error('ReminderService', 'Cancel failed', null, e, st);
      rethrow;
    }
  }
}
