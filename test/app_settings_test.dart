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
}
