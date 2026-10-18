import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/diagnostic_logger.dart';
import '../services/app_lock_service.dart';
import 'app_lock_screen.dart';
import 'dashboard_screen.dart';

/// Shown once after signing in (before the dashboard) when the app lock is
/// off, so patients find it without digging through Settings:
///   1. "Protect your health data": Set up PIN / Not now
///   2. after the PIN, if the phone has a fingerprint/face set up:
///      "Unlock with your fingerprint?": Use fingerprint / Skip
/// then on to the dashboard.
///
/// "Not now" is remembered per patient on this phone, so it doesn't come
/// back at every sign-in; the lock can still be turned on later in
/// Settings > App lock.
class AppLockOfferScreen extends StatefulWidget {
  const AppLockOfferScreen({
    super.key,
    required this.uid,
    this.service,
    this.next = _dashboard,
  });

  final String uid;
  final AppLockService? service;

  /// Where to go afterwards (tests replace the dashboard).
  final Widget Function() next;

  static Widget _dashboard() => const DashboardScreen();

  /// The screen to show right after sign-in and consent: this offer when it
  /// applies, otherwise the dashboard. Never throws.
  static Future<Widget> orDashboard() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const DashboardScreen();
    final offer = await AppLockService.I.shouldOfferSetup(uid);
    DiagnosticLogger.I.info('AppLock', 'Setup offer check', {'offer': offer});
    return offer ? AppLockOfferScreen(uid: uid) : const DashboardScreen();
  }

  @override
  State<AppLockOfferScreen> createState() => _AppLockOfferScreenState();
}

enum _Step { offerPin, offerBiometrics }

class _AppLockOfferScreenState extends State<AppLockOfferScreen> {
  static const Color darkTeal = Color(0xFF0D6E71);
  static const Color primaryTeal = Color(0xFF23A8AA);
  static const String _tag = 'AppLockOffer';

  final DiagnosticLogger _logger = DiagnosticLogger.I;
  late final AppLockService _lock = widget.service ?? AppLockService.I;

  _Step _step = _Step.offerPin;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _logger.info(_tag, 'Shown');
  }

  Future<void> _setUpPin() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => PinSetupScreen(service: widget.service)),
      );
      if (saved != true || !mounted) return;
      _logger.info(_tag, 'PIN set from the offer');
      if (await _lock.biometricsAvailable()) {
        if (mounted) setState(() => _step = _Step.offerBiometrics);
      } else {
        _finish('PIN lock is on. You can change it in Settings.');
      }
    } catch (e, st) {
      _logger.error(_tag, 'PIN setup from the offer failed', null, e, st);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useBiometrics() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _lock.authenticateWithBiometrics(
        reason: 'Confirm to use your fingerprint for RehabPlus',
        unlockOnSuccess: false,
      );
      if (result == BiometricResult.success) {
        await _lock.setBiometricsEnabled(true);
        _finish('PIN and fingerprint lock are on.');
      } else if (result == BiometricResult.cancelled ||
          result == BiometricResult.failed) {
        // Let them try again or skip.
      } else {
        _finish('Fingerprint isn\'t available right now; your PIN is on.');
      }
    } catch (e, st) {
      _logger.error(_tag, 'Turning on fingerprint failed', null, e, st);
      _finish('Fingerprint couldn\'t be turned on; your PIN is on.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _notNow() async {
    if (_busy) return;
    await _lock.dismissSetupOffer(widget.uid);
    _finish(null);
  }

  void _finish(String? message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => widget.next(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinStep = _step == _Step.offerPin;
    return PopScope(
      // The patient chooses with the buttons; back would leave the app.
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7F8),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: primaryTeal.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      pinStep
                          ? Icons.lock_outline_rounded
                          : Icons.fingerprint_rounded,
                      size: 48,
                      color: darkTeal,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  pinStep
                      ? 'Protect your health data'
                      : 'Unlock with your fingerprint?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: darkTeal,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  pinStep
                      ? 'RehabPlus keeps you signed in. Set a '
                            '${AppLockService.pinLength}-digit PIN so only '
                            'you can open your exercises, progress and '
                            'messages if someone else uses this phone.'
                      : 'Use your fingerprint or face instead of typing '
                            'the PIN. Your PIN still works too.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
                const Spacer(flex: 2),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : (pinStep ? _setUpPin : _useBiometrics),
                  icon: Icon(
                    pinStep ? Icons.pin_outlined : Icons.fingerprint_rounded,
                  ),
                  label: Text(pinStep ? 'Set up PIN' : 'Use fingerprint'),
                  style: FilledButton.styleFrom(
                    backgroundColor: darkTeal,
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : (pinStep
                            ? _notNow
                            : () => _finish(
                                'PIN lock is on. You can add your fingerprint '
                                'later in Settings.',
                              )),
                  style: TextButton.styleFrom(
                    foregroundColor: darkTeal,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(pinStep ? 'Not now' : 'Skip'),
                ),
                if (pinStep)
                  const Text(
                    'You can turn this on any time in Settings > App lock.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.black45),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
