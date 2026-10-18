import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults when nothing is saved', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings.I;
    await s.load();
    expect(s.repSound, isTrue);
    expect(s.repVibration, isTrue);
    expect(s.voiceCues, isFalse);
    expect(s.countdownSeconds, 3);
    expect(s.useBackCamera, isFalse);
    expect(s.showSkeleton, isTrue);
    expect(s.reminderEnabled, isFalse);
    expect(s.reminderMinutes, 18 * 60);
    expect(s.textScale, 1.0);
  });

  test('changes are saved and survive a reload', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings.I;
    await s.load();
    var notified = 0;
    void listener() => notified++;
    s.addListener(listener);

    await s.setRepSound(false);
    await s.setCountdownSeconds(5);
    await s.setUseBackCamera(true);
    await s.setReminderMinutes(7 * 60 + 30);
    await s.setTextScale(1.3);
    s.removeListener(listener);
    expect(notified, 5);

    // Overwrite the in-memory values only, then reload from storage.
    s
      ..repSound = true
      ..countdownSeconds = 0
      ..useBackCamera = false
      ..reminderMinutes = 0
      ..textScale = 1.0;
    await s.load();
    expect(s.repSound, isFalse);
    expect(s.countdownSeconds, 5);
    expect(s.useBackCamera, isTrue);
    expect(s.reminderMinutes, 7 * 60 + 30);
    expect(s.textScale, 1.3);
  });

  test('unknown saved values fall back to defaults', () async {
    SharedPreferences.setMockInitialValues({
      's_countdown': 7,
      's_textScale': 2.0,
    });
    final s = AppSettings.I;
    await s.load();
    expect(s.countdownSeconds, 3);
    expect(s.textScale, 1.0);
  });

  test('values of the wrong type or out of range fall back to defaults',
      () async {
    // E.g. left behind by an older app version; getBool() on a string
    // would throw, so load() must check types itself.
    SharedPreferences.setMockInitialValues({
      's_repSound': 'yes',
      's_countdown': '5',
      's_reminderMinutes': 24 * 60 + 5,
      's_textScale': 1, // an int, not a double
      's_backCamera': true,
    });
    final s = AppSettings.I;
    await s.load();
    expect(s.repSound, AppSettings.defaultRepSound);
    expect(s.countdownSeconds, AppSettings.defaultCountdownSeconds);
    expect(s.reminderMinutes, AppSettings.defaultReminderMinutes);
    expect(s.textScale, AppSettings.defaultTextScale);
    expect(s.useBackCamera, isTrue); // valid values are still loaded
  });

  test('a negative reminder time falls back to the default', () async {
    SharedPreferences.setMockInitialValues({'s_reminderMinutes': -1});
    await AppSettings.I.load();
    expect(AppSettings.I.reminderMinutes, AppSettings.defaultReminderMinutes);
  });

  test('setters reject values outside the allowed choices', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings.I;
    await s.load();
    expect(() => s.setCountdownSeconds(4), throwsArgumentError);
    expect(() => s.setTextScale(2.0), throwsArgumentError);
    expect(() => s.setReminderMinutes(24 * 60), throwsArgumentError);
    expect(s.countdownSeconds, AppSettings.defaultCountdownSeconds);
    await s.setReminderMinutes(23 * 60 + 59);
    expect(s.reminderMinutes, 23 * 60 + 59);
  });
}
