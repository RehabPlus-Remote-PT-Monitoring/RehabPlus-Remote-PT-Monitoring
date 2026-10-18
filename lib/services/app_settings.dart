import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings that live on this phone (SharedPreferences): exercise feedback,
/// camera, reminder time and text size. Notification choices that the clinic
/// must respect are stored with the account instead (NotificationPrefsService).
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings I = AppSettings._();

  SharedPreferences? _prefs;

  // Exercise feedback
  bool repSound = true;
  bool repVibration = true;
  bool voiceCues = false;

  /// Seconds of "get ready" before reps are counted (0 = start at once).
  int countdownSeconds = 3;

  // Camera
  bool useBackCamera = false;
  bool showSkeleton = true;

  /// Flip the skeleton the other way from the default for this camera (the
  /// same as the exercise screen's flip button, but remembered).
  bool flipSkeleton = false;

  // Reminder (scheduled on the phone by ReminderService)
  bool reminderEnabled = false;

  /// Minutes after midnight, local time. Default 6:00 PM.
  int reminderMinutes = 18 * 60;

  // Appearance
  /// Multiplies the phone's own text size: 1.0, 1.15 or 1.3.
  double textScale = 1.0;

  static const countdownChoices = [0, 3, 5];
  static const textScaleChoices = [1.0, 1.15, 1.3];

  Future<void> load() async {
    final p = _prefs = await SharedPreferences.getInstance();
    repSound = p.getBool('s_repSound') ?? repSound;
    repVibration = p.getBool('s_repVibration') ?? repVibration;
    voiceCues = p.getBool('s_voiceCues') ?? voiceCues;
    countdownSeconds = p.getInt('s_countdown') ?? countdownSeconds;
    useBackCamera = p.getBool('s_backCamera') ?? useBackCamera;
    showSkeleton = p.getBool('s_showSkeleton') ?? showSkeleton;
    flipSkeleton = p.getBool('s_flipSkeleton') ?? flipSkeleton;
    reminderEnabled = p.getBool('s_reminder') ?? reminderEnabled;
    reminderMinutes = p.getInt('s_reminderMinutes') ?? reminderMinutes;
    textScale = p.getDouble('s_textScale') ?? textScale;
    if (!countdownChoices.contains(countdownSeconds)) countdownSeconds = 3;
    if (!textScaleChoices.contains(textScale)) textScale = 1.0;
    notifyListeners();
  }

  Future<void> _save(String key, Object value) async {
    notifyListeners();
    final p = _prefs ??= await SharedPreferences.getInstance();
    switch (value) {
      case bool v:
        await p.setBool(key, v);
      case int v:
        await p.setInt(key, v);
      case double v:
        await p.setDouble(key, v);
    }
  }

  Future<void> setRepSound(bool v) => _save('s_repSound', repSound = v);
  Future<void> setRepVibration(bool v) =>
      _save('s_repVibration', repVibration = v);
  Future<void> setVoiceCues(bool v) => _save('s_voiceCues', voiceCues = v);
  Future<void> setCountdownSeconds(int v) =>
      _save('s_countdown', countdownSeconds = v);
  Future<void> setUseBackCamera(bool v) =>
      _save('s_backCamera', useBackCamera = v);
  Future<void> setShowSkeleton(bool v) =>
      _save('s_showSkeleton', showSkeleton = v);
  Future<void> setFlipSkeleton(bool v) =>
      _save('s_flipSkeleton', flipSkeleton = v);
  Future<void> setReminderEnabled(bool v) =>
      _save('s_reminder', reminderEnabled = v);
  Future<void> setReminderMinutes(int v) =>
      _save('s_reminderMinutes', reminderMinutes = v);
  Future<void> setTextScale(double v) => _save('s_textScale', textScale = v);
}
