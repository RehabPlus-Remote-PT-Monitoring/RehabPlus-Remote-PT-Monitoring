import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../core/diagnostic_logger.dart';
import '../services/app_lock_service.dart';
import '../widgets/ios_list.dart';
import '../widgets/ios_page.dart';
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
    // No "PIN lock is on/off" snackbar: the switch itself shows it.
    if (on) {
      final saved = await _chooseNewPin(changing: false);
      _logger.info(_tag, 'PIN lock setup finished', {'saved': saved});
      return;
    }
    if (!await _confirmCurrentPin()) return;
    await _lock.disable();
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
        // The switch shows it's on; no snackbar needed.
        await _lock.setBiometricsEnabled(true);
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

  /// iOS inset grouped list, like the iPhone's "Face ID & Passcode" page:
  /// the PIN rows with the how-it-works note as their footnote, then the
  /// fingerprint shortcut in its own group.
  @override
  Widget build(BuildContext context) {
    final enabled = _lock.isEnabled;
    final bioAvailable = _biometricsAvailable == true;
    final canChangePin = enabled && !_busy;

    return IosPage(
      title: 'App Lock',
      previousPageTitle: 'Settings',
      children: [
        IosSection(
          header: 'PIN',
          footer:
              'RehabPlus asks for the PIN when you open the app and when you '
              'come back to it after a minute or more. The PIN is kept only '
              'on this phone.\n\n'
              'Forgot it? Choose "Forgot PIN" on the lock screen to sign in '
              'again with your password. After '
              '${AppLockService.maxAttempts} wrong PINs you are signed out '
              'for safety. Signing out also turns the lock off.',
          children: [
            IosSwitchRow(
              icon: CupertinoIcons.number_square_fill,
              iconColor: IosColors.gray,
              title: 'PIN lock',
              subtitle:
                  'Ask for a ${AppLockService.pinLength}-digit PIN before '
                  'showing your dashboard',
              value: enabled,
              onChanged: _busy ? null : _togglePin,
            ),
            // Greyed out (not hidden) while there is no PIN, so the patient
            // can see the option exists.
            Opacity(
              opacity: canChangePin ? 1 : 0.4,
              child: IosRow(
                icon: CupertinoIcons.lock_rotation,
                iconColor: IosColors.gray,
                title: 'Change PIN',
                showChevron: true,
                onTap: canChangePin ? _changePin : null,
              ),
            ),
          ],
        ),
        IosSection(
          header: 'Fingerprint',
          children: [
            IosSwitchRow(
              icon: Icons.fingerprint_rounded,
              iconColor: IosColors.green,
              title: 'Unlock with fingerprint',
              subtitle: switch (_biometricsAvailable) {
                null => 'Checking this phone…',
                false => 'Set up a fingerprint or face unlock in your '
                    'phone\'s settings to use this',
                true when !enabled => 'Turn on the PIN lock first',
                true => 'A quicker way in; the PIN still works',
              },
              value: _lock.biometricsEnabled,
              onChanged: (_busy || !enabled || !bioAvailable)
                  ? null
                  : _toggleBiometrics,
            ),
          ],
        ),
      ],
    );
  }
}
