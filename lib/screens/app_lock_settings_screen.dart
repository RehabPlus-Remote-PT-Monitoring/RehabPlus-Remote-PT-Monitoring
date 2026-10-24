import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../services/app_lock_service.dart';
import '../core/responsive.dart';
import 'app_lock_screen.dart';

/// Settings > App lock: turn the PIN on/off, fingerprint/face shortcut,
/// change PIN. Turning the lock off or changing the PIN first asks for the
/// current PIN, so someone holding an unlocked phone can't just switch it
/// off.
class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key, this.service});

  /// Injectable for tests; defaults to [AppLockService.I].
  final AppLockService? service;

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  static const Color primaryTeal = Color(0xFF23A8AA);
  static const Color darkTeal = Color(0xFF0D6E71);
  static const String _tag = 'AppLockSettings';

  final DiagnosticLogger _logger = DiagnosticLogger.I;
  late final AppLockService _lock = widget.service ?? AppLockService.I;

  /// Null while checking whether the phone has fingerprint/face set up.
  bool? _biometricsAvailable;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _logger.info(_tag, 'Screen opened');
    _lock.addListener(_rebuild);
    _checkBiometrics();
  }

  @override
  void dispose() {
    _lock.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _checkBiometrics() async {
    final available = await _lock.biometricsAvailable();
    if (mounted) setState(() => _biometricsAvailable = available);
  }

  /// Runs [action] unless another one is still running (double taps).
  Future<void> _guarded(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e, st) {
      _logger.error(_tag, 'App lock action failed', null, e, st);
      _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmCurrentPin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AppLockScreen.confirm(service: widget.service),
      ),
    );
    return ok == true;
  }

  Future<bool> _chooseNewPin({required bool changing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            PinSetupScreen(changing: changing, service: widget.service),
      ),
    );
    return saved == true;
  }

  Future<void> _togglePin(bool on) => _guarded(() async {
    if (on) {
      if (await _chooseNewPin(changing: false)) {
        _snack('PIN lock is on.');
      }
      return;
    }
    if (!await _confirmCurrentPin()) return;
    await _lock.disable();
    _snack('PIN lock is off.');
  });

  Future<void> _changePin() => _guarded(() async {
    if (!await _confirmCurrentPin()) return;
    if (await _chooseNewPin(changing: true)) _snack('PIN changed.');
  });

  Future<void> _toggleBiometrics(bool on) => _guarded(() async {
    if (!on) {
      await _lock.setBiometricsEnabled(false);
      return;
    }
    // Check the finger once, so it's known to work before relying on it.
    final result = await _lock.authenticateWithBiometrics(
      reason: 'Confirm to use your fingerprint for RehabPlus',
      unlockOnSuccess: false,
    );
    switch (result) {
      case BiometricResult.success:
        await _lock.setBiometricsEnabled(true);
        _snack('Fingerprint unlock is on.');
      case BiometricResult.unavailable:
        _snack('Set up a fingerprint in your phone\'s settings first.');
      case BiometricResult.lockedOut:
        _snack('Fingerprint is blocked for now. Try again later.');
      case BiometricResult.error:
        _snack('Fingerprint didn\'t work. Please try again.');
      case BiometricResult.failed:
      case BiometricResult.cancelled:
        break;
    }
  });

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _lock.isEnabled;
    final bioAvailable = _biometricsAvailable == true;
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(title: const Text('App lock'), backgroundColor: darkTeal),
      body: ListView(
        padding: readablePadding(context, const EdgeInsets.all(16)),
        children: [
          _card([
            SwitchListTile(
              value: enabled,
              onChanged: _busy ? null : _togglePin,
              activeThumbColor: Colors.white,
              activeTrackColor: primaryTeal,
              secondary: _leading(Icons.pin_outlined),
              title: Text('PIN lock', style: _titleStyle),
              subtitle: Text(
                'Ask for a ${AppLockService.pinLength}-digit PIN before '
                'showing your dashboard',
                style: _subtitleStyle,
              ),
            ),
            SwitchListTile(
              value: _lock.biometricsEnabled,
              onChanged: (_busy || !enabled || !bioAvailable)
                  ? null
                  : _toggleBiometrics,
              activeThumbColor: Colors.white,
              activeTrackColor: primaryTeal,
              secondary: _leading(Icons.fingerprint_rounded),
              title: Text('Unlock with fingerprint', style: _titleStyle),
              subtitle: Text(
                switch (_biometricsAvailable) {
                  null => 'Checking this phone…',
                  false => 'Set up a fingerprint or face unlock in your '
                      'phone\'s settings to use this',
                  true when !enabled => 'Turn on the PIN lock first',
                  true => 'A quicker way in; the PIN still works',
                },
                style: _subtitleStyle,
              ),
            ),
            ListTile(
              enabled: enabled && !_busy,
              onTap: _changePin,
              leading: _leading(Icons.lock_reset_rounded),
              title: Text('Change PIN', style: _titleStyle),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: palette.textFaint,
                size: 20,
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Text(
              'RehabPlus asks for the PIN when you open the app and when you '
              'come back to it after a minute or more. The PIN is kept only '
              'on this phone.\n\n'
              'Forgot it? Choose "Forgot PIN" on the lock screen to sign in '
              'again with your password. After '
              '${AppLockService.maxAttempts} wrong PINs you are signed out '
              'for safety. Signing out also turns the lock off.',
              style: TextStyle(
                fontSize: 12,
                color: palette.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Getters (not consts) so they follow the light/dark palette.
  TextStyle get _titleStyle => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: context.palette.textPrimary,
  );
  TextStyle get _subtitleStyle =>
      TextStyle(fontSize: 12, color: context.palette.textMuted);

  Widget _card(List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: context.palette.shadow.withValues(alpha: 0.05),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(children: children),
  );

  Widget _leading(IconData icon) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: primaryTeal.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 18, color: primaryTeal),
  );
}
