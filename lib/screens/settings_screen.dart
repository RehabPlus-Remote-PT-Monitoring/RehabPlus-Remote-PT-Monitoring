import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart' hide DiagnosticLevel;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../widgets/ios_list.dart';
import '../widgets/ios_page.dart';
import '../widgets/ios_segmented_control.dart';
import '../widgets/app_dialogs.dart';
import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../models/chat.dart';
import '../services/app_lock_service.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/notification_prefs_service.dart';
import '../services/reminder_service.dart';
import '../core/responsive.dart';
import 'app_lock_settings_screen.dart';
import 'messages_screen.dart';

/// Firestore rules limit a chat message to 1000 characters.
const int maxProblemReportLength = 1000;

/// How many recent warnings/errors a problem report includes.
const int problemReportErrorCount = 5;

/// Builds the text sent to the clinic chat by Settings > Report a problem.
///
/// Layout: `Problem report: <what the patient wrote>` then a bracketed
/// diagnostics block with the app version, this launch's run id (to find
/// the matching log file) and the newest warn/error events as
/// `tag: message`. Only tags and constant messages are included, never the
/// events' data maps, so no personal data can leak into the report.
///
/// Never longer than [maxProblemReportLength]: the patient's text is
/// shortened first so the diagnostics always fit.
@visibleForTesting
String buildProblemReport({
  required String userText,
  required String appVersion,
  required String runId,
  required List<DiagnosticEvent> recentEvents,
}) {
  String clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max - 1)}…';

  final problems = recentEvents
      .where((e) => e.level.index >= DiagnosticLevel.warn.index)
      .toList()
      .reversed // newest first
      .take(problemReportErrorCount)
      .map((e) => clip('${e.tag}: ${e.message}', 80))
      .join('; ');

  final version = appVersion.isEmpty ? 'unknown' : appVersion;
  final diagnostics =
      '[App $version; run $runId'
      '${problems.isEmpty ? '' : '; recent errors: $problems'}]';

  const prefix = 'Problem report: ';
  const separator = '\n\n';
  final roomForText =
      maxProblemReportLength - prefix.length - separator.length - diagnostics.length;
  if (roomForText < 20) {
    // Only if the diagnostics are oddly long: keep the patient's words and
    // cut the diagnostics instead.
    return clip('$prefix$userText$separator$diagnostics', maxProblemReportLength);
  }
  return '$prefix${clip(userText, roomForText)}$separator$diagnostics';
}

/// Profile > Settings: exercise feedback, camera, reminders, notifications,
/// text size, account, support and app version.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  static const String _tag = 'Settings';

  final _settings = AppSettings.I;
  final DiagnosticLogger _logger = DiagnosticLogger.I;

  NotificationPrefs? _notif; // null while loading
  bool _savingNotif = false;
  PermissionStatus? _camera;
  String _version = '';

  // Double-tap guards for actions that await something.
  bool _busyReminder = false;
  bool _sendingPasswordLink = false;
  bool _reporting = false;

  @override
  void initState() {
    super.initState();
    _logger.info(_tag, 'Screen opened');
    WidgetsBinding.instance.addObserver(this);
    _settings.addListener(_rebuild);
    // The App lock tile shows On/Off.
    AppLockService.I.addListener(_rebuild);
    _loadNotificationPrefs();
    _checkCamera();
    _loadVersion();
  }

  Future<void> _loadNotificationPrefs() async {
    NotificationPrefs prefs;
    try {
      prefs = await NotificationPrefsService.I.load();
    } catch (e, st) {
      // load() handles Firestore errors itself; this is anything else.
      // Show the defaults rather than a spinner forever.
      _logger.warn(_tag, 'Notification prefs load failed', null, e, st);
      prefs = const NotificationPrefs();
    }
    if (mounted) setState(() => _notif = prefs);
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = '${info.version} (${info.buildNumber})');
      }
    } catch (e, st) {
      _logger.warn(_tag, 'Could not read the app version', null, e, st);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_rebuild);
    AppLockService.I.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  // Back from the phone's settings app: the camera permission may have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkCamera();
  }

  Future<void> _checkCamera() async {
    try {
      final status = await Permission.camera.status;
      if (_camera != status) {
        _logger.info(_tag, 'Camera permission', {'status': status.name});
      }
      if (mounted) setState(() => _camera = status);
    } catch (e, st) {
      _logger.warn(_tag, 'Camera permission check failed', null, e, st);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  /// Wraps a phone-only setting's setter: logs the change (these values are
  /// not personal: switches, seconds, a text scale) and catches save errors,
  /// which would otherwise be uncaught async errors.
  ValueChanged<T> _logged<T>(String key, Future<void> Function(T) save) {
    return (T value) {
      _logger.info(_tag, 'Setting changed', {'key': key, 'value': value});
      unawaited(
        save(value).then(
          (_) {},
          onError: (Object e, StackTrace st) {
            _logger.warn(_tag, 'Saving a setting failed', {'key': key}, e, st);
            _snack('Could not save that setting. Please try again.');
          },
        ),
      );
    };
  }

  Future<void> _toggleReminder(bool on) async {
    if (_busyReminder) return;
    _busyReminder = true;
    _logger.info(_tag, 'Setting changed', {'key': 'reminderEnabled', 'value': on});
    try {
      if (on) {
        final ok = await ReminderService.I.schedule(_settings.reminderMinutes);
        if (!ok) {
          _logger.warn(_tag, 'Reminder not scheduled (permission refused)');
          _snack('Allow notifications for RehabPlus to get reminders.');
          return;
        }
      } else {
        await ReminderService.I.cancel();
      }
      await _settings.setReminderEnabled(on);
    } catch (e, st) {
      _logger.error(_tag, 'Changing the reminder failed', {'on': on}, e, st);
      _snack('Could not change the reminder. Please try again.');
    } finally {
      _busyReminder = false;
    }
  }

  Future<void> _pickReminderTime() async {
    if (_busyReminder) return;
    final current = TimeOfDay(
      hour: _settings.reminderMinutes ~/ 60,
      minute: _settings.reminderMinutes % 60,
    );
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    _logger.info(_tag, 'Setting changed', {'key': 'reminderMinutes', 'value': minutes});
    _busyReminder = true;
    try {
      await _settings.setReminderMinutes(minutes);
      if (_settings.reminderEnabled) await ReminderService.I.schedule(minutes);
    } catch (e, st) {
      _logger.error(_tag, 'Changing the reminder time failed', null, e, st);
      _snack('Could not change the reminder. Please try again.');
    } finally {
      _busyReminder = false;
    }
  }

  Future<void> _setNotif(NotificationPrefs next) async {
    final previous = _notif;
    _logger.info(_tag, 'Setting changed', {
      'key': 'pushPreferences',
      'messages': next.messages,
      'exercises': next.exercises,
      'reminders': next.reminders,
    });
    setState(() {
      _notif = next;
      _savingNotif = true;
    });
    try {
      await NotificationPrefsService.I.save(next);
      _logger.info(_tag, 'Push preferences saved');
    } catch (e, st) {
      _logger.warn(_tag, 'Notification prefs save failed', null, e, st);
      if (mounted) {
        setState(() => _notif = previous);
        _snack('Could not save. Check your internet connection.');
      }
    } finally {
      if (mounted) setState(() => _savingNotif = false);
    }
  }

  Future<void> _changePassword() async {
    if (_sendingPasswordLink) return;
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) {
      _logger.warn(_tag, 'Change password: no signed-in e-mail');
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: 'Change password',
      message: 'We\'ll email a link to $email. Open it to choose a new password.',
      confirmLabel: 'Send link',
    );
    if (ok != true) return;
    _sendingPasswordLink = true;
    _logger.info(_tag, 'Password change link requested');
    try {
      await AuthService.I.sendPasswordReset(email);
      _logger.info(_tag, 'Password change link sent');
      _snack('Password link sent to $email.');
    } on FirebaseAuthException catch (e, st) {
      _logger.warn(_tag, 'Password change link failed', {'code': e.code}, e, st);
      _snack('Could not send the link. Please try again.');
    } catch (e, st) {
      _logger.error(_tag, 'Password change link crashed', null, e, st);
      _snack('Could not send the link. Please try again.');
    } finally {
      _sendingPasswordLink = false;
    }
  }

  Future<void> _cameraAccess() async {
    try {
      final status = await Permission.camera.request();
      _logger.info(_tag, 'Camera permission requested', {'status': status.name});
      if (!status.isGranted) await openAppSettings();
    } catch (e, st) {
      _logger.warn(_tag, 'Camera permission request failed', null, e, st);
    }
    await _checkCamera();
  }

  Future<void> _openAppSettings() async {
    _logger.info(_tag, 'Opening phone app settings');
    try {
      await openAppSettings();
    } catch (e, st) {
      _logger.warn(_tag, 'Opening phone app settings failed', null, e, st);
    }
  }

  Future<void> _reportProblem() async {
    if (_reporting) return;
    _reporting = true;
    try {
      _logger.info(_tag, 'Report a problem opened');
      // The dialog owns (and disposes) its text controller. Disposing it
      // here right after showDialog returned was a bug: the dialog's closing
      // animation still rebuilds the TextField, which then used a disposed
      // controller.
      final text = await showDialog<String>(
        context: context,
        builder: (ctx) => const _ReportProblemDialog(),
      );
      if (text == null || text.isEmpty) {
        _logger.info(_tag, 'Report a problem cancelled');
        return;
      }

      // Fetch the version if the About row hasn't loaded it yet.
      var version = _version;
      if (version.isEmpty) {
        try {
          final info = await PackageInfo.fromPlatform();
          version = '${info.version} (${info.buildNumber})';
        } catch (_) {
          version = 'unknown'; // already logged by _loadVersion
        }
      }

      final message = buildProblemReport(
        userText: text,
        appVersion: version,
        runId: _logger.runId,
        recentEvents: _logger.recent(limit: 200),
      );
      try {
        ChatService().send(ChatThread.clinic, message);
      } catch (e, st) {
        _logger.error(_tag, 'Problem report not sent', null, e, st);
        _snack('Could not send the report. Please try again.');
        return;
      }
      // Lengths only: the report text itself is never logged.
      _logger.info(_tag, 'Problem report sent', {
        'userTextLength': text.length,
        'reportLength': message.length,
      });
      // Make sure everything up to the report is on disk, so the log file
      // matching the run id in the report is complete.
      unawaited(_logger.flush());
      _snack('Thanks. Your report was sent to the clinic.');
    } finally {
      _reporting = false;
    }
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  /// An iOS inset grouped list, like the iPhone Settings app. On a phone the
  /// sections stay in one column in their usual order. On a wide tablet they
  /// split into two columns (exercise and camera things on the left,
  /// notifications, appearance, account and support on the right), so the
  /// page uses the screen instead of one long narrow strip.
  @override
  Widget build(BuildContext context) {
    return IosPage(
      title: 'Settings',
      previousPageTitle: 'Profile',
      maxWidth: adaptiveMaxWidth(context),
      children: [
        AdaptiveColumns(
          left: [
            _exerciseFeedbackSection(),
            _cameraSection(),
            _remindersSection(),
          ],
          right: [
            _notificationsSection(),
            _appearanceSection(),
            _accountSection(),
            _supportSection(),
            _aboutSection(),
          ],
        ),
      ],
    );
  }

  Widget _exerciseFeedbackSection() {
    final s = _settings;
    return IosSection(
      header: 'Exercise feedback',
      footer:
          'The countdown gives you time to get into position before your '
          'reps are counted.',
      children: [
        IosSwitchRow(
          icon: CupertinoIcons.speaker_2_fill,
          iconColor: IosColors.pink,
          title: 'Sound on each rep',
          value: s.repSound,
          onChanged: _logged('repSound', s.setRepSound),
        ),
        IosSwitchRow(
          icon: CupertinoIcons.device_phone_portrait,
          iconColor: IosColors.purple,
          title: 'Vibrate on each rep',
          subtitle: 'Also a double buzz when a rep isn\'t counted',
          value: s.repVibration,
          onChanged: _logged('repVibration', s.setRepVibration),
        ),
        IosSwitchRow(
          icon: CupertinoIcons.waveform,
          iconColor: IosColors.orange,
          title: 'Spoken cues',
          subtitle: 'Reads your rep count and form tips aloud',
          value: s.voiceCues,
          onChanged: _logged('voiceCues', s.setVoiceCues),
        ),
        IosControlRow(
          icon: CupertinoIcons.timer,
          iconColor: IosColors.orange,
          // Short title (explained in the footer): the control row's title
          // is on one line and "Countdown before counting" overflowed a
          // phone at the Larger text size.
          title: 'Countdown',
          child: IosSegmentedControl<int>(
            options: {
              for (final c in AppSettings.countdownChoices)
                c: c == 0 ? 'Off' : '$c s',
            },
            value: s.countdownSeconds,
            onChanged: _logged('countdownSeconds', s.setCountdownSeconds),
          ),
        ),
      ],
    );
  }

  Widget _cameraSection() {
    final s = _settings;
    return IosSection(
      header: 'Camera',
      children: [
        IosControlRow(
          icon: CupertinoIcons.camera_rotate,
          iconColor: IosColors.gray,
          title: 'Start with',
          child: IosSegmentedControl<bool>(
            options: const {false: 'Front', true: 'Back'},
            value: s.useBackCamera,
            onChanged: _logged('useBackCamera', s.setUseBackCamera),
          ),
        ),
        IosSwitchRow(
          icon: Icons.accessibility_new_rounded,
          iconColor: IosColors.teal,
          title: 'Show skeleton',
          subtitle: 'The lines drawn over your body',
          value: s.showSkeleton,
          onChanged: _logged('showSkeleton', s.setShowSkeleton),
        ),
        IosSwitchRow(
          icon: CupertinoIcons.arrow_right_arrow_left,
          iconColor: IosColors.teal,
          title: 'Flip skeleton',
          subtitle: 'Turn on if it moves opposite to you',
          value: s.flipSkeleton,
          onChanged: _logged('flipSkeleton', s.setFlipSkeleton),
        ),
      ],
    );
  }

  Widget _remindersSection() {
    final s = _settings;
    final reminderTime = TimeOfDay(
      hour: s.reminderMinutes ~/ 60,
      minute: s.reminderMinutes % 60,
    ).format(context);
    return IosSection(
      header: 'Reminders',
      children: [
        IosSwitchRow(
          icon: CupertinoIcons.bell_fill,
          iconColor: IosColors.red,
          title: 'Daily exercise reminder',
          value: s.reminderEnabled,
          onChanged: _toggleReminder,
        ),
        IosRow(
          icon: CupertinoIcons.clock_fill,
          iconColor: IosColors.orange,
          title: 'Reminder time',
          value: reminderTime,
          onTap: _pickReminderTime,
        ),
      ],
    );
  }

  Widget _notificationsSection() {
    final notif = _notif;

    // Still loading the saved choices: a spinner where the rows will be.
    if (notif == null) {
      return const IosSection(
        header: 'Notifications',
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2.5),
              ),
            ),
          ),
        ],
      );
    }

    // Switches are disabled while a change is being saved, so two quick
    // taps can't race each other to Firestore.
    ValueChanged<bool>? whenIdle(ValueChanged<bool> change) =>
        _savingNotif ? null : change;

    return IosSection(
      header: 'Notifications',
      footer:
          'Turning these off stops the phone alerts only. Everything '
          'still appears on the Notifications page.',
      children: [
        IosSwitchRow(
          icon: CupertinoIcons.chat_bubble_fill,
          iconColor: IosColors.green,
          title: 'New messages',
          value: notif.messages,
          onChanged: whenIdle((v) => _setNotif(notif.copyWith(messages: v))),
        ),
        IosSwitchRow(
          icon: CupertinoIcons.doc_text_fill,
          iconColor: IosColors.blue,
          title: 'New exercises',
          value: notif.exercises,
          onChanged: whenIdle((v) => _setNotif(notif.copyWith(exercises: v))),
        ),
        IosSwitchRow(
          icon: CupertinoIcons.alarm_fill,
          iconColor: IosColors.red,
          title: 'Clinic reminders',
          subtitle: "6 PM, if today's exercises aren't done yet",
          value: notif.reminders,
          onChanged: whenIdle((v) => _setNotif(notif.copyWith(reminders: v))),
        ),
      ],
    );
  }

  Widget _appearanceSection() {
    final s = _settings;
    return IosSection(
      header: 'Appearance',
      children: [
        IosControlRow(
          icon: CupertinoIcons.moon_fill,
          iconColor: IosColors.indigo,
          title: 'Theme',
          child: IosSegmentedControl<ThemeMode>(
            options: const {
              ThemeMode.system: 'Phone setting',
              ThemeMode.light: 'Light',
              ThemeMode.dark: 'Dark',
            },
            value: s.themeMode,
            onChanged: _logged('themeMode', s.setThemeMode),
          ),
        ),
        IosControlRow(
          icon: CupertinoIcons.textformat_size,
          iconColor: IosColors.blue,
          title: 'Text size',
          child: IosSegmentedControl<double>(
            // Not const: Dart doesn't allow double keys in a const map.
            options: {1.0: 'Normal', 1.15: 'Large', 1.3: 'Larger'},
            value: s.textScale,
            onChanged: _logged('textScale', s.setTextScale),
          ),
        ),
      ],
    );
  }

  Widget _accountSection() {
    final lock = AppLockService.I;
    final cameraAllowed = _camera == PermissionStatus.granted;
    return IosSection(
      header: 'Account',
      children: [
        IosRow(
          icon: CupertinoIcons.lock_fill,
          iconColor: IosColors.gray,
          title: 'App lock',
          // Says what kind of lock, so the patient knows if the fingerprint
          // is set up without opening the page.
          subtitle: !lock.isEnabled
              ? null
              : lock.biometricsEnabled
              ? 'PIN and fingerprint'
              : 'PIN',
          value: lock.isEnabled ? 'On' : 'Off',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AppLockSettingsScreen()),
          ),
        ),
        IosRow(
          icon: CupertinoIcons.lock_rotation,
          iconColor: IosColors.gray,
          title: 'Change password',
          onTap: _changePassword,
        ),
        IosRow(
          icon: CupertinoIcons.camera_fill,
          iconColor: IosColors.gray,
          title: 'Camera access',
          // Empty while the permission is still being checked.
          value: switch (_camera) {
            null => null,
            PermissionStatus.granted => 'Allowed',
            _ => 'Not allowed',
          },
          onTap: cameraAllowed ? _openAppSettings : _cameraAccess,
        ),
      ],
    );
  }

  Widget _supportSection() {
    return IosSection(
      header: 'Support',
      children: [
        IosRow(
          icon: CupertinoIcons.question_circle_fill,
          iconColor: IosColors.green,
          title: 'Help & Support',
          subtitle: 'Message the clinic',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ChatDetailScreen(thread: ChatThread.clinic),
            ),
          ),
        ),
        IosRow(
          icon: CupertinoIcons.phone_fill,
          iconColor: IosColors.green,
          title: 'Call the clinic',
          onTap: () => callClinic(context),
        ),
        IosRow(
          icon: CupertinoIcons.ant_fill,
          iconColor: IosColors.orange,
          title: 'Report a problem',
          onTap: _reportProblem,
        ),
      ],
    );
  }

  Widget _aboutSection() {
    return IosSection(
      header: 'About',
      children: [
        IosRow(
          icon: CupertinoIcons.info_circle_fill,
          iconColor: IosColors.gray,
          title: 'App version',
          value: _version,
        ),
      ],
    );
  }
}

/// Settings > Report a problem. Pops with the trimmed text, or null when
/// cancelled. Owns its TextEditingController so it is disposed only after
/// the dialog has fully closed.
class _ReportProblemDialog extends StatefulWidget {
  const _ReportProblemDialog();

  @override
  State<_ReportProblemDialog> createState() => _ReportProblemDialogState();
}

class _ReportProblemDialogState extends State<_ReportProblemDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      backgroundColor: palette.surface,
      title: const Text('Report a problem'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            maxLines: 4,
            maxLength: 500,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'What happened?',
              border: OutlineInputBorder(),
            ),
          ),
          Text(
            'Sent to the clinic with the app version and recent error '
            'messages, to help fix it.',
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Send'),
        ),
      ],
    );
  }
}
