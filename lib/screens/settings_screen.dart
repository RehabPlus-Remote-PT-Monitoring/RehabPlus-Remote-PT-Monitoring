import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide DiagnosticLevel;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/diagnostic_logger.dart';
import '../models/chat.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/notification_prefs_service.dart';
import '../services/reminder_service.dart';
import 'messages_screen.dart';

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

  final _settings = AppSettings.I;

  NotificationPrefs? _notif; // null while loading
  bool _savingNotif = false;
  PermissionStatus? _camera;
  String _version = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settings.addListener(_rebuild);
    NotificationPrefsService.I.load().then((p) {
      if (mounted) setState(() => _notif = p);
    });
    _checkCamera();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = '${info.version} (${info.buildNumber})');
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  // Back from the phone's settings app: the camera permission may have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkCamera();
  }

  Future<void> _checkCamera() async {
    final status = await Permission.camera.status;
    if (mounted) setState(() => _camera = status);
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  Future<void> _toggleReminder(bool on) async {
    if (on) {
      final ok = await ReminderService.I.schedule(_settings.reminderMinutes);
      if (!ok) {
        _snack('Allow notifications for RehabPlus to get reminders.');
        return;
      }
    } else {
      await ReminderService.I.cancel();
    }
    await _settings.setReminderEnabled(on);
  }

  Future<void> _pickReminderTime() async {
    final current = TimeOfDay(
      hour: _settings.reminderMinutes ~/ 60,
      minute: _settings.reminderMinutes % 60,
    );
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    await _settings.setReminderMinutes(minutes);
    if (_settings.reminderEnabled) await ReminderService.I.schedule(minutes);
  }

  Future<void> _setNotif(NotificationPrefs next) async {
    final previous = _notif;
    setState(() {
      _notif = next;
      _savingNotif = true;
    });
    try {
      await NotificationPrefsService.I.save(next);
    } catch (e) {
      DiagnosticLogger.I.warn('Settings', 'Notification prefs save failed', {
        'error': e.toString(),
      });
      if (mounted) {
        setState(() => _notif = previous);
        _snack('Could not save. Check your internet connection.');
      }
    } finally {
      if (mounted) setState(() => _savingNotif = false);
    }
  }

  Future<void> _changePassword() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
    try {
      await AuthService.I.sendPasswordReset(email);
      _snack('Password link sent to $email.');
    } catch (_) {
      _snack('Could not send the link. Please try again.');
    }
  }

  Future<void> _cameraAccess() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) await openAppSettings();
    await _checkCamera();
  }

  Future<void> _reportProblem() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report a problem'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              maxLines: 4,
              maxLength: 500,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'What happened?',
                border: OutlineInputBorder(),
              ),
            ),
            const Text(
              'Sent to the clinic with the app version and recent error '
              'messages, to help fix it.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty) return;

    final errors = DiagnosticLogger.I
        .recent(limit: 100)
        .where((e) => e.level.index >= DiagnosticLevel.warn.index)
        .map((e) => '${e.tag}: ${e.message}')
        .toList()
        .reversed
        .take(5)
        .join('; ');
    var message =
        'Problem report: $text\n\n[App $_version'
        '${errors.isEmpty ? '' : '; recent errors: $errors'}]';
    // Messages are limited to 1000 characters (Firestore rules).
    if (message.length > 1000) message = '${message.substring(0, 997)}...]';
    try {
      ChatService().send(ChatThread.clinic, message);
      _snack('Thanks. Your report was sent to the clinic.');
    } catch (_) {
      _snack('Could not send the report. Please try again.');
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

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F4),
      body: Column(
        children: [
          _header(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _section('Exercise feedback', Icons.fitness_center_rounded, [
                  _switch(
                    Icons.volume_up_outlined,
                    'Sound on each rep',
                    s.repSound,
                    s.setRepSound,
                  ),
                  _switch(
                    Icons.vibration_rounded,
                    'Vibrate on each rep',
                    s.repVibration,
                    s.setRepVibration,
                    subtitle: 'Also a double buzz when a rep isn\'t counted',
                  ),
                  _switch(
                    Icons.record_voice_over_outlined,
                    'Spoken cues',
                    s.voiceCues,
                    s.setVoiceCues,
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
                    s.setCountdownSeconds,
                  ),
                ]),
                _section('Camera', Icons.videocam_outlined, [
                  _choice<bool>(
                    Icons.cameraswitch_outlined,
                    'Start with',
                    s.useBackCamera,
                    const {false: 'Front', true: 'Back'},
                    s.setUseBackCamera,
                  ),
                  _switch(
                    Icons.accessibility_new_rounded,
                    'Show skeleton',
                    s.showSkeleton,
                    s.setShowSkeleton,
                    subtitle: 'The lines drawn over your body',
                  ),
                  _switch(
                    Icons.flip_rounded,
                    'Flip skeleton',
                    s.flipSkeleton,
                    s.setFlipSkeleton,
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
                        color: s.reminderEnabled ? darkTeal : Colors.black38,
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
                          : (v) => _setNotif(
                              NotificationPrefs(
                                messages: v,
                                exercises: notif.exercises,
                              ),
                            ),
                    ),
                    _switch(
                      Icons.assignment_outlined,
                      'New exercises',
                      notif.exercises,
                      _savingNotif
                          ? null
                          : (v) => _setNotif(
                              NotificationPrefs(
                                messages: notif.messages,
                                exercises: v,
                              ),
                            ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        'Turning these off stops the phone alerts only. Everything '
                        'still appears on the Notifications page.',
                        style: TextStyle(fontSize: 12, color: Colors.black45),
                      ),
                    ),
                  ],
                ]),
                _section('Appearance', Icons.text_fields_rounded, [
                  _choice<double>(
                    Icons.format_size_rounded,
                    'Text size',
                    s.textScale,
                    {1.0: 'Normal', 1.15: 'Large', 1.3: 'Larger'},
                    s.setTextScale,
                  ),
                ]),
                _section('Account', Icons.person_outline_rounded, [
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
                            ? darkTeal
                            : Colors.red[700],
                      ),
                    ),
                    onTap: _camera == PermissionStatus.granted
                        ? openAppSettings
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
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [darkTeal, Color(0xFF1A8587), primaryTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 24),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black87,
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

  static const _titleStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: Colors.black87,
  );
  static const _subtitleStyle = TextStyle(fontSize: 12, color: Colors.black45);

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
              : const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.black26,
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
              Text(title, style: _titleStyle),
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
                foregroundColor: darkTeal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
