import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_keys.dart';
import '../core/diagnostic_logger.dart';
import '../services/app_lock_service.dart';
import '../services/app_provider.dart';
import 'login_page.dart';

/// The PIN / fingerprint screens of the optional app lock
/// (see AppLockService for the rules).
///
/// - [AppLockScreen] asks for the PIN: at startup (before the dashboard),
///   when coming back after a minute away, and in Settings to confirm the
///   current PIN before turning the lock off or changing it.
/// - [PinSetupScreen] chooses a new PIN (typed twice).
/// - [AppLockRouter] pushes the lock screen when the app comes back from the
///   background.
const String _tag = 'AppLock';

const Color _darkTeal = Color(0xFF0D6E71);
const Color _midTeal = Color(0xFF1E8E92);
const Color _lightTeal = Color(0xFF2FB8BD);

/// Pushes [AppLockScreen] over whatever is open when AppLockService locks
/// the app on resume. The screen underneath (even a running exercise) stays
/// as it was and is shown again once unlocked.
class AppLockRouter {
  AppLockRouter._();

  static bool _attached = false;
  static bool _pushPending = false;

  /// Call once at startup.
  static void attach([AppLockService? service]) {
    if (_attached) return;
    _attached = true;
    final lock = service ?? AppLockService.I;
    lock.addListener(() => _onLockChanged(lock));
  }

  static void _onLockChanged(AppLockService lock) {
    if (!lock.needsLockScreen || _pushPending) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      DiagnosticLogger.I.warn(_tag, 'Lock needed but no navigator yet');
      return;
    }
    _pushPending = true;
    // No transition: the app's content must not be visible, even briefly.
    navigator.push(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: 'app-lock'),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => const AppLockScreen.resume(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    // By the next frame the screen has registered itself as showing.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushPending = false);
  }
}

enum _LockMode { startup, resume, confirm }

/// Asks for the PIN (or fingerprint/face).
class AppLockScreen extends StatefulWidget {
  /// At startup, before the dashboard: [next] builds the screen to show
  /// once unlocked (the consent gate, then the dashboard).
  const AppLockScreen.startup({
    super.key,
    required Future<Widget> Function() this.next,
    this.service,
  }) : _mode = _LockMode.startup;

  /// Over the open screen after time away; pops itself once unlocked.
  const AppLockScreen.resume({super.key, this.service})
    : _mode = _LockMode.resume,
      next = null;

  /// From Settings: confirms the current PIN, pops `true` when correct.
  const AppLockScreen.confirm({super.key, this.service})
    : _mode = _LockMode.confirm,
      next = null;

  final _LockMode _mode;
  final Future<Widget> Function()? next;

  /// Injectable for tests; defaults to [AppLockService.I].
  final AppLockService? service;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final DiagnosticLogger _logger = DiagnosticLogger.I;
  late final AppLockService _lock = widget.service ?? AppLockService.I;

  bool _leaving = false;
  bool _biometricRunning = false;

  bool get _isConfirm => widget._mode == _LockMode.confirm;

  @override
  void initState() {
    super.initState();
    _lock.lockViewShown();
    _logger.info(_tag, 'Lock screen shown', {'mode': widget._mode.name});
    // Offer the fingerprint straight away when unlocking the app.
    if (!_isConfirm && _lock.biometricsEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
    }
  }

  @override
  void dispose() {
    _lock.lockViewHidden();
    super.dispose();
  }

  Future<String?> _onPin(String pin) async {
    final result = await _lock.verifyPin(pin);
    switch (result) {
      case PinCheck.correct:
        _onUnlocked();
        return null;
      case PinCheck.wrong:
        final left = _lock.attemptsLeft;
        return 'Wrong PIN. $left ${left == 1 ? 'try' : 'tries'} left.';
      case PinCheck.tooManyAttempts:
        unawaited(
          _signOutToLogin(
            'Too many wrong PINs. Please sign in again with your password.',
          ),
        );
        return 'Too many wrong PINs.';
    }
  }

  Future<void> _tryBiometrics() async {
    if (_biometricRunning || _leaving || !mounted) return;
    _biometricRunning = true;
    try {
      final result = await _lock.authenticateWithBiometrics(
        reason: _isConfirm
            ? 'Confirm it\'s you'
            : 'Unlock RehabPlus',
        unlockOnSuccess: !_isConfirm,
      );
      if (!mounted) return;
      switch (result) {
        case BiometricResult.success:
          _onUnlocked();
        case BiometricResult.lockedOut:
          _snack('Fingerprint is blocked for now. Use your PIN.');
        case BiometricResult.unavailable:
          _snack('Fingerprint isn\'t available. Use your PIN.');
        case BiometricResult.error:
          _snack('Fingerprint didn\'t work. Use your PIN.');
        case BiometricResult.failed:
        case BiometricResult.cancelled:
          break; // The PIN pad is right there.
      }
    } finally {
      _biometricRunning = false;
    }
  }

  void _onUnlocked() {
    if (_leaving || !mounted) return;
    _leaving = true;
    switch (widget._mode) {
      case _LockMode.confirm:
        Navigator.of(context).pop(true);
      case _LockMode.resume:
        Navigator.of(context).pop();
      case _LockMode.startup:
        unawaited(_continueToApp());
    }
  }

  /// Startup: build the next screen (consent check), then fade into it.
  Future<void> _continueToApp() async {
    Widget next;
    try {
      next = await widget.next!();
    } catch (e, st) {
      _logger.error(_tag, 'Next screen failed after unlock', null, e, st);
      next = const LoginPage();
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) => next,
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  /// "Forgot PIN?" and too many wrong PINs: sign out (which also removes
  /// the lock) and go to the login page.
  Future<void> _signOutToLogin(String message) async {
    if (_leaving) return;
    _leaving = true;
    _logger.info(_tag, 'Signing out from the lock screen');
    try {
      await context.read<AppProvider>().signOut();
    } catch (e, st) {
      _logger.error(_tag, 'Sign-out from lock screen failed', null, e, st);
      _leaving = false;
      _snack('Could not sign out. Check your connection and try again.');
      return;
    }
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (_) => false,
    );
    messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _forgotPin() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: ThemeData.light(useMaterial3: true),
        child: AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Forgot your PIN?'),
          content: const Text(
            'You\'ll be signed out. Sign in again with your email and '
            'password, then you can set a new PIN in Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _signOutToLogin('Signed out. Sign in with your password.');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final body = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_darkTeal, _midTeal, _lightTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (_isConfirm)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
            Expanded(
              child: PinEntry(
                onDark: true,
                icon: Icons.lock_outline_rounded,
                title: _isConfirm ? 'Enter your current PIN' : 'Enter your PIN',
                subtitle: _isConfirm ? null : 'RehabPlus is locked',
                onComplete: _onPin,
                onBiometric: _lock.biometricsEnabled ? _tryBiometrics : null,
              ),
            ),
            TextButton(
              onPressed: _forgotPin,
              child: const Text(
                'Forgot PIN? Sign in with password',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    return PopScope(
      // Back can't skip the lock; in Settings it just cancels.
      canPop: _isConfirm,
      child: Scaffold(body: body),
    );
  }
}

/// Settings: choose a new PIN by typing it twice. Pops `true` once saved.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key, this.changing = false, this.service});

  /// Wording for "Change PIN" instead of turning the lock on.
  final bool changing;
  final AppLockService? service;

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final DiagnosticLogger _logger = DiagnosticLogger.I;
  late final AppLockService _lock = widget.service ?? AppLockService.I;

  /// The PIN typed in step 1; null while on step 1.
  String? _first;

  /// Shown on step 1 after the two PINs didn't match.
  String? _restartMessage;

  Future<String?> _onPin(String pin) async {
    final first = _first;
    if (first == null) {
      final problem = AppLockService.weakPinReason(pin);
      if (problem != null) return problem;
      setState(() {
        _first = pin;
        _restartMessage = null;
      });
      return null;
    }
    if (pin != first) {
      _logger.info(_tag, 'PIN setup: confirmation did not match');
      setState(() {
        _first = null;
        _restartMessage = 'The PINs didn\'t match. Please start again.';
      });
      return null;
    }
    try {
      await _lock.setPin(pin);
    } catch (e, st) {
      _logger.error(_tag, 'Saving the PIN failed', null, e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the PIN. Try again.')),
        );
        setState(() => _first = null);
      }
      return null;
    }
    if (mounted) Navigator.of(context).pop(true);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final confirming = _first != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F8),
      appBar: AppBar(
        title: Text(widget.changing ? 'Change PIN' : 'Set a PIN'),
        backgroundColor: _darkTeal,
      ),
      body: SafeArea(
        child: PinEntry(
          // A new key resets the dots when moving between the two steps.
          key: ValueKey(confirming),
          icon: Icons.pin_outlined,
          title: confirming
              ? 'Enter the same PIN again'
              : 'Choose a ${AppLockService.pinLength}-digit PIN',
          subtitle: confirming
              ? null
              : 'You\'ll enter it when you open RehabPlus.',
          initialError: _restartMessage,
          onComplete: _onPin,
        ),
      ),
    );
  }
}

/// Dots for the digits typed so far and a number pad. Calls [onComplete]
/// once [AppLockService.pinLength] digits are in; it returns an error to
/// show (the dots shake and clear) or null when the PIN was accepted.
class PinEntry extends StatefulWidget {
  const PinEntry({
    super.key,
    required this.title,
    required this.onComplete,
    this.subtitle,
    this.icon,
    this.onBiometric,
    this.initialError,
    this.onDark = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Future<String?> Function(String pin) onComplete;

  /// Shows a fingerprint key when set.
  final VoidCallback? onBiometric;
  final String? initialError;

  /// White text for the teal lock screen; dark text for light pages.
  final bool onDark;

  @override
  State<PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends State<PinEntry>
    with SingleTickerProviderStateMixin {
  String _digits = '';
  String? _error;
  bool _busy = false;

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Color get _fg => widget.onDark ? Colors.white : _darkTeal;

  void _press(String digit) {
    if (_busy || _digits.length >= AppLockService.pinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _digits += digit;
      _error = null;
    });
    if (_digits.length == AppLockService.pinLength) _submit();
  }

  void _backspace() {
    if (_busy || _digits.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    String? error;
    try {
      error = await widget.onComplete(_digits);
    } catch (e, st) {
      DiagnosticLogger.I.error(_tag, 'PIN check crashed', null, e, st);
      error = 'Something went wrong. Please try again.';
    }
    if (!mounted) return;
    if (error != null) {
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
    }
    setState(() {
      _busy = false;
      _error = error;
      // Keep the dots full after success while the screen leaves.
      if (error != null) _digits = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final muted = widget.onDark ? Colors.white70 : Colors.black54;
    final errorColor = widget.onDark ? const Color(0xFFFFE082) : Colors.red[700];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Keys shrink on small screens / large text so nothing overflows.
        final keySize = math
            .min(
              72.0,
              math.min(
                (constraints.maxWidth - 80) / 3,
                (constraints.maxHeight * 0.55 - 36) / 4,
              ),
            )
            .clamp(44.0, 72.0);

        return Column(
          children: [
            const Spacer(),
            if (widget.icon != null) Icon(widget.icon, size: 40, color: _fg),
            const SizedBox(height: 12),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _fg,
              ),
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: muted),
              ),
            ],
            const SizedBox(height: 24),
            AnimatedBuilder(
              animation: _shake,
              builder: (context, child) => Transform.translate(
                offset: Offset(
                  math.sin(_shake.value * math.pi * 6) * 10 * (1 - _shake.value),
                  0,
                ),
                child: child,
              ),
              child: _dots(),
            ),
            SizedBox(
              height: 40,
              child: Center(
                child: Text(
                  _error ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: errorColor,
                  ),
                ),
              ),
            ),
            const Spacer(),
            _keypad(keySize),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  Widget _dots() {
    return Semantics(
      label:
          '${_digits.length} of ${AppLockService.pinLength} digits entered',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < AppLockService.pinLength; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _digits.length ? _fg : Colors.transparent,
                border: Border.all(color: _fg, width: 2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _keypad(double size) {
    Widget key({
      required Widget child,
      required String label,
      VoidCallback? onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Semantics(
          button: true,
          label: label,
          child: Material(
            color: onTap == null
                ? Colors.transparent
                : _fg.withValues(alpha: widget.onDark ? 0.12 : 0.08),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: size,
                height: size,
                child: Center(child: child),
              ),
            ),
          ),
        ),
      );
    }

    Widget digit(String d) => key(
      label: d,
      onTap: () => _press(d),
      child: Text(
        d,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w600,
          color: _fg,
        ),
      ),
    );

    final bio = widget.onBiometric;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final d in row) digit(d)],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            bio == null
                ? key(label: '', child: const SizedBox.shrink())
                : key(
                    label: 'Use fingerprint',
                    onTap: bio,
                    child: Icon(
                      Icons.fingerprint_rounded,
                      size: size * 0.45,
                      color: _fg,
                    ),
                  ),
            digit('0'),
            key(
              label: 'Delete',
              onTap: _backspace,
              child: Icon(
                Icons.backspace_outlined,
                size: size * 0.34,
                color: _fg,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
