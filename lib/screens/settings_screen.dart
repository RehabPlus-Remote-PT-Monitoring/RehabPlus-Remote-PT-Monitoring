import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide DiagnosticLevel;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

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
  static const Color primaryTeal = Color(0xFF23A8AA);
  static const Color darkTeal = Color(0xFF0D6E71);
  static const String _tag = 'Settings';

  /// Teal for values and unselected segment labels. Dark teal is too dim on
  /// a dark card, so dark mode uses the brighter brand teal.
  Color get _valueTeal => context.isDarkMode ? primaryTeal : darkTeal;

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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.surface,
        title: const Text('Change password'),
        content: Text(
          'We\'ll email a link to $email. Open it to choose a new password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send link'),
          ),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    final notif = _notif;
    final reminderTime = TimeOfDay(
      hour: s.reminderMinutes ~/ 60,
      minute: s.reminderMinutes % 60,
    ).format(context);
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          _header(),
          Expanded(
            child: ListView(
              // Full width so the empty sides still scroll; the padding
              // centres the cards (two columns' worth on wide screens).
              padding: readablePadding(
                context,
                const EdgeInsets.fromLTRB(16, 16, 16, 32),
                adaptiveMaxWidth(context),
              ),
              children: [
                // Phone: one column in the usual order. Wide screens:
                // exercise and alert settings on the left; appearance,
                // account and help on the right.
                AdaptiveColumns(
                  left: [
                    _section('Exercise feedback', Icons.fitness_center_rounded, [
                      _switch(
                        Icons.volume_up_outlined,
                        'Sound on each rep',
                        s.repSound,
                        _logged('repSound', s.setRepSound),
                      ),
                      _switch(
                        Icons.vibration_rounded,
                        'Vibrate on each rep',
                        s.repVibration,
                        _logged('repVibration', s.setRepVibration),
                        subtitle: 'Also a double buzz when a rep isn\'t counted',
                      ),
                      _switch(
                        Icons.record_voice_over_outlined,
                        'Spoken cues',
                        s.voiceCues,
                        _logged('voiceCues', s.setVoiceCues),
                        subtitle: 'Reads your rep count and form tips aloud',
                      ),
                      _choice<int>(
                        Icons.timer_outlined,
                        'Countdown before counting',
                        s.countdownSeconds,
                        {
                          for (final c in AppSettings.countdownChoices)
                            c: c == 0 ? 'Off' : '$c s',
                        },
                        _logged('countdownSeconds', s.setCountdownSeconds),
                      ),
                    ]),
                    _section('Camera', Icons.videocam_outlined, [
                      _choice<bool>(
                        Icons.cameraswitch_outlined,
                        'Start with',
                        s.useBackCamera,
                        const {false: 'Front', true: 'Back'},
                        _logged('useBackCamera', s.setUseBackCamera),
                      ),
                      _switch(
                        Icons.accessibility_new_rounded,
                        'Show skeleton',
                        s.showSkeleton,
                        _logged('showSkeleton', s.setShowSkeleton),
                        subtitle: 'The lines drawn over your body',
                      ),
                      _switch(
                        Icons.flip_rounded,
                        'Flip skeleton',
                        s.flipSkeleton,
                        _logged('flipSkeleton', s.setFlipSkeleton),
                        subtitle: 'Turn on if it moves opposite to you',
                      ),
                    ]),
                    _section('Reminders', Icons.alarm_rounded, [
                      _switch(
                        Icons.notifications_active_outlined,
                        'Daily exercise reminder',
                        s.reminderEnabled,
                        _toggleReminder,
                      ),
                      _tile(
                        Icons.schedule_rounded,
                        'Reminder time',
                        trailing: Text(
                          reminderTime,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: s.reminderEnabled ? _valueTeal : palette.textMuted,
                          ),
                        ),
                        onTap: _pickReminderTime,
                      ),
                    ]),
                    _section('Notifications', Icons.notifications_none_rounded, [
                      if (notif == null)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          ),
                        )
                      else ...[
                        _switch(
                          Icons.chat_bubble_outline_rounded,
                          'New messages',
                          notif.messages,
                          _savingNotif
                              ? null
                              : (v) => _setNotif(notif.copyWith(messages: v)),
                        ),
                        _switch(
                          Icons.assignment_outlined,
                          'New exercises',
                          notif.exercises,
                          _savingNotif
                              ? null
                              : (v) => _setNotif(notif.copyWith(exercises: v)),
                        ),
                        _switch(
                          Icons.alarm_rounded,
                          'Clinic reminders',
                          notif.reminders,
                          _savingNotif
                              ? null
                              : (v) => _setNotif(notif.copyWith(reminders: v)),
                          subtitle: "6 PM, if today's exercises aren't done yet",
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Text(
                            'Turning these off stops the phone alerts only. Everything '
                            'still appears on the Notifications page.',
                            style: TextStyle(fontSize: 12, color: palette.textMuted),
                          ),
                        ),
                      ],
                    ]),
                  ],
                  right: [
                    _section('Appearance', Icons.text_fields_rounded, [
                      _choice<ThemeMode>(
                        Icons.dark_mode_outlined,
                        'Theme',
                        s.themeMode,
                        {
                          ThemeMode.system: 'Phone setting',
                          ThemeMode.light: 'Light',
                          ThemeMode.dark: 'Dark',
                        },
                        _logged('themeMode', s.setThemeMode),
                      ),
                      _choice<double>(
                        Icons.format_size_rounded,
                        'Text size',
                        s.textScale,
                        {1.0: 'Normal', 1.15: 'Large', 1.3: 'Larger'},
                        _logged('textScale', s.setTextScale),
                      ),
                    ]),
                    _section('Account', Icons.person_outline_rounded, [
                      _tile(
                        Icons.lock_outline_rounded,
                        'App lock',
                        subtitle: !AppLockService.I.isEnabled
                            ? 'Off'
                            : AppLockService.I.biometricsEnabled
                            ? 'On: PIN and fingerprint'
                            : 'On: PIN',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AppLockSettingsScreen(),
                          ),
                        ),
                      ),
                      _tile(
                        Icons.lock_reset_rounded,
                        'Change password',
                        onTap: _changePassword,
                      ),
                      _tile(
                        Icons.photo_camera_outlined,
                        'Camera access',
                        trailing: Text(
                          switch (_camera) {
                            null => '',
                            PermissionStatus.granted => 'Allowed',
                            _ => 'Not allowed',
                          },
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _camera == PermissionStatus.granted
                                ? _valueTeal
                                : Colors.red[700],
                          ),
                        ),
                        onTap: _camera == PermissionStatus.granted
                            ? _openAppSettings
                            : _cameraAccess,
                      ),
                    ]),
                    _section('Support', Icons.support_agent_rounded, [
                      _tile(
                        Icons.help_outline_rounded,
                        'Help & Support',
                        subtitle: 'Message the clinic',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const ChatDetailScreen(thread: ChatThread.clinic),
                          ),
                        ),
                      ),
                      _tile(
                        Icons.call_outlined,
                        'Call the clinic',
                        onTap: () => callClinic(context),
                      ),
                      _tile(
                        Icons.bug_report_outlined,
                        'Report a problem',
                        onTap: _reportProblem,
                      ),
                    ]),
                    _section('About', Icons.info_outline_rounded, [
                      _tile(
                        Icons.apps_rounded,
                        'App version',
                        trailing: Text(
                          _version,
                          style: TextStyle(color: palette.textSecondary),
                        ),
                      ),
                    ]),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The teal bar spans the whole width; its back button and title are
  /// inset to line up with the cards below (no inset on phones).
  Widget _header() {
    final inset = readableInset(context, adaptiveMaxWidth(context));
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: AppPalette.headerGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(8 + inset, 8, 20 + inset, 24),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.settings_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Settings',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Icon(icon, size: 16, color: primaryTeal),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _leading(IconData icon) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: primaryTeal.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 18, color: primaryTeal),
  );

  // Getters (not consts) so they follow the light/dark palette.
  TextStyle get _titleStyle => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: context.palette.textPrimary,
  );
  TextStyle get _subtitleStyle =>
      TextStyle(fontSize: 12, color: context.palette.textMuted);

  Widget _switch(
    IconData icon,
    String title,
    bool value,
    ValueChanged<bool>? onChanged, {
    String? subtitle,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.white,
      activeTrackColor: primaryTeal,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      secondary: _leading(icon),
      title: Text(title, style: _titleStyle),
      subtitle: subtitle == null ? null : Text(subtitle, style: _subtitleStyle),
    );
  }

  Widget _tile(
    IconData icon,
    String title, {
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: _leading(icon),
      title: Text(title, style: _titleStyle),
      subtitle: subtitle == null ? null : Text(subtitle, style: _subtitleStyle),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : Icon(
                  Icons.chevron_right_rounded,
                  color: context.palette.textFaint,
                  size: 20,
                )),
    );
  }

  /// A title with a row of options underneath (one selected).
  Widget _choice<T>(
    IconData icon,
    String title,
    T value,
    Map<T, String> options,
    ValueChanged<T> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _leading(icon),
              const SizedBox(width: 16),
              // Flexible: a long title wraps instead of overflowing on a
              // narrow phone with large text.
              Flexible(child: Text(title, style: _titleStyle)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              segments: [
                for (final e in options.entries)
                  ButtonSegment(value: e.key, label: Text(e.value)),
              ],
              selected: {value},
              showSelectedIcon: false,
              onSelectionChanged: (sel) => onChanged(sel.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: primaryTeal,
                selectedForegroundColor: Colors.white,
                foregroundColor: _valueTeal,
                side: BorderSide(color: context.palette.divider),
              ),
            ),
          ),
        ],
      ),
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
