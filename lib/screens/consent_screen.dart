import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/diagnostic_logger.dart';
import '../legal/legal_info.dart';
import '../services/app_provider.dart';
import '../services/consent_service.dart';
import '../services/push_service.dart';
import 'app_lock_offer_screen.dart';
import 'legal_document_screen.dart';
import 'login_page.dart';

/// Shown after sign-in until the patient accepts the current Terms and
/// Conditions and Privacy Policy (and again whenever [LegalInfo.version]
/// changes). The patient can't use the app without accepting; declining
/// signs them out.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  static const String _tag = 'ConsentScreen';

  /// The screen to show a signed-in patient: the dashboard if they have
  /// accepted the current version, otherwise this screen.
  ///
  /// Never throws. If the check itself fails it fails closed (asks again),
  /// so nobody gets in without a consent record.
  static Future<Widget> gate() async {
    final logger = DiagnosticLogger.I;
    bool accepted;
    try {
      accepted = await ConsentService.I.hasAcceptedCurrent();
    } catch (e, st) {
      logger.error(_tag, 'Consent check failed; asking again', null, e, st);
      accepted = false;
    }
    logger.info(_tag, 'Consent gate', {
      'version': LegalInfo.version,
      'accepted': accepted,
    });
    if (accepted) {
      // Not awaited: it may show the notification-permission prompt.
      unawaited(PushService.I.registerForCurrentUser());
      // The dashboard, or first the offer to set up the PIN/fingerprint
      // lock when it's off (so patients find it without Settings).
      return AppLockOfferScreen.orDashboard();
    }
    return const ConsentScreen();
  }

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  static const Color primaryTeal = Color(0xFF23A8AA);
  static const Color darkTeal = Color(0xFF0D6E71);

  bool _terms = false;
  bool _health = false;
  bool _camera = false;
  /// True while accepting or signing out: every button is disabled so a
  /// double tap can't send two requests.
  bool _saving = false;

  final DiagnosticLogger _logger = DiagnosticLogger.I;
  static const String _tag = ConsentScreen._tag;

  bool get _allChecked => _terms && _health && _camera;

  @override
  void initState() {
    super.initState();
    _logger.info(_tag, 'Screen opened', {'version': LegalInfo.version});
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red[700]),
    );
  }

  Future<void> _accept() async {
    if (_saving || !_allChecked) return;
    setState(() => _saving = true);
    _logger.info(_tag, 'Consent accept tapped', {'version': LegalInfo.version});
    try {
      await ConsentService.I.accept();
    } on ConsentFailure catch (e) {
      _logger.warn(_tag, 'Consent not saved', {'version': LegalInfo.version});
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(e.message);
      return;
    } catch (e, st) {
      // ConsentService wraps Firestore errors; this is anything else (e.g.
      // the phone's preferences store failing).
      _logger.error(_tag, 'Consent accept crashed', null, e, st);
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Could not save your acceptance. Please try again.');
      return;
    }
    _logger.info(_tag, 'Consent accepted', {'version': LegalInfo.version});
    if (!mounted) return;
    // Not awaited: it may show the notification-permission prompt.
    unawaited(PushService.I.registerForCurrentUser());
    // The dashboard, or first the offer to set up the PIN/fingerprint lock.
    final next = await AppLockOfferScreen.orDashboard();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => next,
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _decline() async {
    if (_saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline and sign out?'),
        content: const Text(
          'You need to accept the Terms and Conditions and Privacy Policy to '
          'use RehabPlus. If you have questions, contact the clinic before '
          'deciding.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _logger.info(_tag, 'Consent declined', {'version': LegalInfo.version});
    setState(() => _saving = true);
    try {
      await context.read<AppProvider>().signOut();
    } catch (e, st) {
      // Stay here (the patient still can't use the app) and let them retry.
      _logger.error(_tag, 'Sign-out after decline failed', null, e, st);
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Could not sign out. Please try again.');
      return;
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  void _open(Widget screen) {
    _logger.info(_tag, 'Opened legal document', {
      'screen': screen.runtimeType.toString(),
    });
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4F4),
        body: Column(
          children: [
            _header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                children: [
                  _card(
                    children: [
                      const Text(
                        'Before you start',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _point(
                        Icons.health_and_safety_outlined,
                        'RehabPlus supports your therapist\'s care; it doesn\'t '
                        'replace it. Stop if an exercise hurts, and call 911 '
                        'in an emergency. Messages aren\'t monitored 24/7.',
                      ),
                      _point(
                        Icons.videocam_outlined,
                        'The camera tracks your movements on your phone only. '
                        'Video is never recorded or uploaded.',
                      ),
                      _point(
                        Icons.monitor_heart_outlined,
                        'Your exercise results, pain levels and messages are '
                        'shared with your care team at ${LegalInfo.clinicName} '
                        'and stored securely with Google Firebase.',
                      ),
                      _point(
                        Icons.verified_user_outlined,
                        'Under the Data Privacy Act you can access, correct or '
                        'request deletion of your information and withdraw '
                        'consent at any time.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _card(
                    padding: EdgeInsets.zero,
                    children: [
                      _docLink(
                        Icons.description_outlined,
                        'Read the Terms and Conditions',
                        () => _open(const LegalDocumentScreen.terms()),
                      ),
                      const Divider(height: 1, indent: 56),
                      _docLink(
                        Icons.privacy_tip_outlined,
                        'Read the Privacy Policy',
                        () => _open(const LegalDocumentScreen.privacy()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _card(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      _check(
                        _terms,
                        (v) => setState(() => _terms = v),
                        'I have read and agree to the Terms and Conditions. I '
                        'am 18 or older, or my parent or guardian agrees on my '
                        'behalf.',
                      ),
                      _check(
                        _health,
                        (v) => setState(() => _health = v),
                        'I have read the Privacy Policy and consent to '
                        '${LegalInfo.clinicName} collecting and processing my '
                        'personal and health information for my therapy, as it '
                        'describes.',
                      ),
                      _check(
                        _camera,
                        (v) => setState(() => _camera = v),
                        'I understand the app uses my camera during exercises '
                        'to track my movements on my phone, without recording '
                        'or uploading video.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Version ${LegalInfo.version} · effective ${LegalInfo.effectiveDate}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: Colors.black38),
                  ),
                ],
              ),
            ),
            _buttons(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [darkTeal, Color(0xFF1A8587), primaryTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: const SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, color: Colors.white, size: 30),
              SizedBox(height: 10),
              Text(
                'Terms & Privacy',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Please review and accept to continue',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({
    required List<Widget> children,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _point(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: primaryTeal),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _docLink(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: primaryTeal),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: darkTeal,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.black26),
    );
  }

  Widget _check(bool value, ValueChanged<bool> onChanged, String label) {
    return CheckboxListTile(
      value: value,
      onChanged: _saving ? null : (v) => onChanged(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: primaryTeal,
      dense: true,
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          height: 1.4,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buttons() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _allChecked && !_saving ? _accept : null,
                style: FilledButton.styleFrom(
                  backgroundColor: primaryTeal,
                  disabledBackgroundColor: Colors.black12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Accept and continue',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            TextButton(
              onPressed: _saving ? null : _decline,
              child: const Text(
                'Decline and sign out',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
