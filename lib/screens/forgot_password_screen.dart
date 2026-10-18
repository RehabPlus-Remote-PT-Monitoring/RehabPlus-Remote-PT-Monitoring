import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/diagnostic_logger.dart';
import '../services/auth_service.dart';
import 'login_page.dart' show looksLikeEmail, maxEmailLength;

// Firebase emails the user a reset link; the new password is chosen on
// Firebase's page, so the app only needs to collect the email.
enum _ForgotStage { enterEmail, success }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with TickerProviderStateMixin {
  static const Color primaryTeal = Color(0xFF23A8AA);
  static const String _tag = 'ForgotPassword';
  final DiagnosticLogger _logger = DiagnosticLogger.I;

  _ForgotStage _stage = _ForgotStage.enterEmail;

  final _emailCtrl = TextEditingController();
  bool _isLoading = false;

  // Stage transition animation
  late final AnimationController _stageCtrl;
  late final Animation<double> _stageFade;
  late final Animation<Offset> _stageSlide;

  // Logo entrance animation
  late final AnimationController _logoCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;

  // Success pulse animation
  late final AnimationController _successCtrl;
  late final Animation<double> _successScale;

  @override
  void initState() {
    super.initState();

    _stageCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _stageFade = CurvedAnimation(parent: _stageCtrl, curve: Curves.easeOut);
    _stageSlide = Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _stageCtrl, curve: Curves.easeOutCubic));

    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _logoScale = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoFade = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut);

    _successCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _successScale = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut));

    // Skip if the screen was closed during the delay (disposed controllers
    // throw when started).
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      _logoCtrl.forward();
      _stageCtrl.forward();
    });

    _logger.info(_tag, 'Screen opened');
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _stageCtrl.dispose();
    _logoCtrl.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  Future<void> _transitionTo(_ForgotStage next) async {
    await _stageCtrl.reverse();
    if (!mounted) return;
    setState(() {
      _stage = next;
      _isLoading = false;
    });
    _stageCtrl.forward();
    if (next == _ForgotStage.success) _successCtrl.forward();
  }

  Future<void> _onContinue() async {
    // The keyboard's "done" key can call this while a request is running.
    if (_isLoading) return;
    switch (_stage) {
      case _ForgotStage.enterEmail:
        final email = _emailCtrl.text.trim();
        if (!looksLikeEmail(email)) {
          _showSnack('Enter a valid email address.', isError: true);
          return;
        }
        FocusScope.of(context).unfocus();
        setState(() => _isLoading = true);
        // The address itself is never logged.
        _logger.info(_tag, 'Password reset requested');
        try {
          await AuthService.I.sendPasswordReset(email);
        } on FirebaseAuthException catch (e) {
          // Unknown emails are not reported (Firebase hides which accounts
          // exist), so only input and network problems land here.
          _logger.warn(_tag, 'Password reset failed', {'code': e.code});
          if (!mounted) return;
          setState(() => _isLoading = false);
          _showSnack(
            switch (e.code) {
              'invalid-email' => 'Enter a valid email address.',
              'network-request-failed' => 'No internet connection.',
              'too-many-requests' => 'Too many attempts. Try again later.',
              _ => 'Could not send the reset email. Please try again.',
            },
            isError: true,
          );
          return;
        } catch (e, st) {
          // Not a Firebase error (e.g. plugin missing): don't spin forever.
          _logger.error(_tag, 'Password reset crashed', null, e, st);
          if (!mounted) return;
          setState(() => _isLoading = false);
          _showSnack(
            'Could not send the reset email. Please try again.',
            isError: true,
          );
          return;
        }
        _logger.info(_tag, 'Password reset email sent');
        if (!mounted) return;
        _transitionTo(_ForgotStage.success);
      case _ForgotStage.success:
        Navigator.pop(context);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(0xFFE53935) : primaryTeal,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ── Stage metadata ────────────────────────────────────────────────────────
  String get _stageTitle => switch (_stage) {
        _ForgotStage.enterEmail => 'Forgot Password?',
        _ForgotStage.success => 'Check Your Email',
      };

  String get _stageSubtitle => switch (_stage) {
        _ForgotStage.enterEmail => 'Enter your email and we\'ll send you a link to reset your password.',
        _ForgotStage.success =>
          'If an account exists for ${_emailCtrl.text.trim()}, a reset link is on its way.',
      };

  String get _buttonLabel => switch (_stage) {
        _ForgotStage.enterEmail => 'Send Reset Link',
        _ForgotStage.success => 'Back to Login',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D6E71), Color(0xFF1E8E92), Color(0xFF2FB8BD)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Decorative circles
            Positioned(top: -80, right: -80, child: _circle(260, 0.07)),
            Positioned(top: 60, right: -30, child: _circle(120, 0.05)),
            Positioned(bottom: -100, left: -60, child: _circle(300, 0.06)),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      _buildBrandingHeader(),
                      const SizedBox(height: 28),
                      _buildCard(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circle(double size, double opacity) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: opacity),
          shape: BoxShape.circle,
        ),
      );

  // ── Branding header (shared across all stages) ────────────────────────────
  Widget _buildBrandingHeader() {
    return FadeTransition(
      opacity: _logoFade,
      child: Column(
        children: [
          ScaleTransition(
            scale: _logoScale,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PhosphorIcon(PhosphorIcons.shieldPlus(), color: Colors.white, size: 42),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Rehab +',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          const Text(
            'Physiotherapy',
            style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 2),
          ),
        ],
      ),
    );
  }

  // ── Card wrapper ──────────────────────────────────────────────────────────
  Widget _buildCard() {
    return SlideTransition(
      position: _stageSlide,
      child: FadeTransition(
        opacity: _stageFade,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button (not on success)
              if (_stage != _ForgotStage.success)
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36, height: 36,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Colors.black54),
                  ),
                ),

              Text(
                _stageTitle,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
              ),
              const SizedBox(height: 6),
              Text(
                _stageSubtitle,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.4),
              ),
              const SizedBox(height: 28),

              // Stage content
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_stage),
                  child: _buildStageContent(),
                ),
              ),

              const SizedBox(height: 24),

              // CTA button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E8E92),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : Text(
                            _buttonLabel,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Stage content ─────────────────────────────────────────────────────────
  Widget _buildStageContent() {
    return switch (_stage) {
      _ForgotStage.enterEmail => _buildEnterEmail(),
      _ForgotStage.success => _buildSuccess(),
    };
  }

  Widget _buildEnterEmail() {
    return _inputField(
      controller: _emailCtrl,
      hint: 'Email address',
      icon: PhosphorIcons.envelopeSimple(),
      keyboardType: TextInputType.emailAddress,
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: Column(
        children: [
          ScaleTransition(
            scale: _successScale,
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF23A8AA), Color(0xFF0D6E71)]),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: const Color(0xFF23A8AA).withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8)),
                ],
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Reset Link Sent!',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          Text(
            'Open the link in your email to choose a new password, then sign in here.\nCheck your spam folder if you don\'t see it.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required PhosphorIconData icon,
    bool obscureText = false,
    Widget? suffix,
    TextInputType? keyboardType,
  }) {
    final isEmail = keyboardType == TextInputType.emailAddress;
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      // E-mail addresses (and passwords) must not be "corrected".
      autocorrect: !(isEmail || obscureText),
      enableSuggestions: !(isEmail || obscureText),
      autofillHints: isEmail ? const [AutofillHints.email] : null,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _onContinue(),
      inputFormatters: [
        if (isEmail) LengthLimitingTextInputFormatter(maxEmailLength),
      ],
      style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
        prefixIcon: PhosphorIcon(icon, size: 20, color: Colors.grey.shade400),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2EA9AE), width: 1.8),
        ),
      ),
    );
  }}
