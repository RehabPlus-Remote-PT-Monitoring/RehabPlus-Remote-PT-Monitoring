import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/diagnostic_logger.dart';

/// Settings that live on this phone (SharedPreferences): exercise feedback,
/// camera, reminder time and text size. Notification choices that the clinic
/// must respect are stored with the account instead (NotificationPrefsService).
///
/// Every stored value is type- and range-checked when loaded: a value of the
/// wrong type (e.g. left by an older app version) or outside the allowed
/// choices falls back to the default instead of crashing or reaching the
/// exercise screen.
///
/// Log events (tag 'AppSettings'): "Loaded" {all values, invalid: [keys]},
/// "Setting changed" {key, value}, "Saving setting failed" {key}.
/// Nothing here is personal data.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings I = AppSettings._();

  final _logger = DiagnosticLogger.I;
  SharedPreferences? _prefs;

  // Defaults (also what an invalid stored value falls back to).
  static const bool defaultRepSound = true;
  static const bool defaultRepVibration = true;
  static const bool defaultVoiceCues = false;
  static const int defaultCountdownSeconds = 3;
  static const bool defaultUseBackCamera = false;
  static const bool defaultShowSkeleton = true;
  static const bool defaultFlipSkeleton = false;
  static const bool defaultReminderEnabled = false;
  static const int defaultReminderMinutes = 18 * 60;
  static const double defaultTextScale = 1.0;

  /// Last valid reminder time: 23:59.
  static const int maxReminderMinutes = 24 * 60 - 1;

  // Exercise feedback
  bool repSound = defaultRepSound;
  bool repVibration = defaultRepVibration;
  bool voiceCues = defaultVoiceCues;

  /// Seconds of "get ready" before reps are counted (0 = start at once).
  int countdownSeconds = defaultCountdownSeconds;

  // Camera
  bool useBackCamera = defaultUseBackCamera;
  bool showSkeleton = defaultShowSkeleton;

  /// Flip the skeleton the other way from the default for this camera (the
  /// same as the exercise screen's flip button, but remembered).
  bool flipSkeleton = defaultFlipSkeleton;

  // Reminder (scheduled on the phone by ReminderService)
  bool reminderEnabled = defaultReminderEnabled;

  /// Minutes after midnight, local time. Default 6:00 PM.
  int reminderMinutes = defaultReminderMinutes;

  // Appearance
  /// Multiplies the phone's own text size: 1.0, 1.15 or 1.3.
  double textScale = defaultTextScale;

  static const countdownChoices = [0, 3, 5];
  static const textScaleChoices = [1.0, 1.15, 1.3];

  /// Loads every setting from the phone. Never throws: if storage can't be
  /// opened, the defaults are used for this run.
  Future<void> load() async {
    final SharedPreferences p;
    try {
      p = _prefs = await SharedPreferences.getInstance();
    } catch (e, st) {
      _logger.error('AppSettings', 'Phone storage unavailable; using defaults',
          null, e, st);
      return;
    }

    final invalid = <String>[];
    bool readBool(String key, bool fallback) {
      final value = p.get(key);
      if (value == null) return fallback;
      if (value is bool) return value;
      invalid.add(key);
      return fallback;
    }

    repSound = readBool('s_repSound', defaultRepSound);
    repVibration = readBool('s_repVibration', defaultRepVibration);
    voiceCues = readBool('s_voiceCues', defaultVoiceCues);
    useBackCamera = readBool('s_backCamera', defaultUseBackCamera);
    showSkeleton = readBool('s_showSkeleton', defaultShowSkeleton);
    flipSkeleton = readBool('s_flipSkeleton', defaultFlipSkeleton);
    reminderEnabled = readBool('s_reminder', defaultReminderEnabled);

    final countdown = p.get('s_countdown');
    if (countdown is int && countdownChoices.contains(countdown)) {
      countdownSeconds = countdown;
    } else {
      if (countdown != null) invalid.add('s_countdown');
      countdownSeconds = defaultCountdownSeconds;
    }

    final minutes = p.get('s_reminderMinutes');
    if (minutes is int && isValidReminderMinutes(minutes)) {
      reminderMinutes = minutes;
    } else {
      if (minutes != null) invalid.add('s_reminderMinutes');
      reminderMinutes = defaultReminderMinutes;
    }

    final scale = p.get('s_textScale');
    if (scale is double && textScaleChoices.contains(scale)) {
      textScale = scale;
    } else {
      if (scale != null) invalid.add('s_textScale');
      textScale = defaultTextScale;
    }

    _logger.info('AppSettings', 'Loaded', {
      'repSound': repSound,
      'repVibration': repVibration,
      'voiceCues': voiceCues,
      'countdownSeconds': countdownSeconds,
      'useBackCamera': useBackCamera,
      'showSkeleton': showSkeleton,
      'flipSkeleton': flipSkeleton,
      'reminderEnabled': reminderEnabled,
      'reminderMinutes': reminderMinutes,
      'textScale': textScale,
      if (invalid.isNotEmpty) 'invalid': invalid,
    });
    notifyListeners();
  }

  /// Whether [minutes] is a time of day (0 = midnight … 1439 = 23:59).
  static bool isValidReminderMinutes(int minutes) =>
      minutes >= 0 && minutes <= maxReminderMinutes;

  /// Notifies listeners at once (the UI updates immediately), then writes.
  /// A failed write is logged, not thrown: the new value still applies for
  /// this run, it just won't survive a restart.
  Future<void> _save(String key, Object value) async {
    notifyListeners();
    _logger.info('AppSettings', 'Setting changed', {
      'key': key,
      'value': value,
    });
    try {
      final p = _prefs ??= await SharedPreferences.getInstance();
      switch (value) {
        case bool v:
          await p.setBool(key, v);
        case int v:
          await p.setInt(key, v);
        case double v:
          await p.setDouble(key, v);
      }
    } catch (e, st) {
      _logger.warn('AppSettings', 'Saving setting failed', {'key': key}, e, st);
    }
  }

  Future<void> setRepSound(bool v) => _save('s_repSound', repSound = v);
  Future<void> setRepVibration(bool v) =>
      _save('s_repVibration', repVibration = v);
  Future<void> setVoiceCues(bool v) => _save('s_voiceCues', voiceCues = v);

  /// [v] must be one of [countdownChoices]; throws [ArgumentError] otherwise.
  Future<void> setCountdownSeconds(int v) {
    if (!countdownChoices.contains(v)) {
      throw ArgumentError.value(v, 'v', 'Not one of $countdownChoices');
    }
    return _save('s_countdown', countdownSeconds = v);
  }

  Future<void> setUseBackCamera(bool v) =>
      _save('s_backCamera', useBackCamera = v);
  Future<void> setShowSkeleton(bool v) =>
      _save('s_showSkeleton', showSkeleton = v);
  Future<void> setFlipSkeleton(bool v) =>
      _save('s_flipSkeleton', flipSkeleton = v);
  Future<void> setReminderEnabled(bool v) =>
      _save('s_reminder', reminderEnabled = v);

  /// [v] is minutes after midnight, 0–1439; throws [ArgumentError] otherwise.
  Future<void> setReminderMinutes(int v) {
    if (!isValidReminderMinutes(v)) {
      throw ArgumentError.value(v, 'v', 'Not a time of day in minutes');
    }
    return _save('s_reminderMinutes', reminderMinutes = v);
  }

  /// [v] must be one of [textScaleChoices]; throws [ArgumentError] otherwise.
  Future<void> setTextScale(double v) {
    if (!textScaleChoices.contains(v)) {
      throw ArgumentError.value(v, 'v', 'Not one of $textScaleChoices');
    }
    return _save('s_textScale', textScale = v);
  }
}
