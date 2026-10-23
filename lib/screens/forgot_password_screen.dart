import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show PhoneAuthCredential;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        FilteringTextInputFormatter,
        LengthLimitingTextInputFormatter,
        TextInputFormatter;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../services/auth_service.dart';

// Reset by text message (see AuthService): the patient types their mobile
// number, then the 6-digit code Firebase texts them, then a new password.
// The code briefly signs them in; leaving before the end signs them out
// again, and finishing signs them out so they log in with the new password.
enum _ForgotStage { enterPhone, enterCode, newPassword, success }

/// Digits in the SMS code.
const int resetCodeLength = 6;

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with TickerProviderStateMixin {
  static const Color primaryTeal = Color(0xFF23A8AA);
  static const String _tag = 'ForgotPassword';
  static const Duration _resendWait = Duration(seconds: 30);
  final DiagnosticLogger _logger = DiagnosticLogger.I;

  _ForgotStage _stage = _ForgotStage.enterPhone;

  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isLoading = false;
  bool _showPassword = false;

  /// The number the code went to, in +63... form.
  String? _phoneE164;
  String? _verificationId;
  int? _resendToken;

  /// True once the code signed the patient in and until the password is
  /// changed: leaving the screen in between must sign them out again.
  bool _signedInForReset = false;

  /// Seconds before "Resend code" can be tapped again.
  int _resendIn = 0;
  Timer? _resendTimer;

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
    if (_signedInForReset) {
      // Left half-way: don't stay signed in without a known password.
      unawaited(AuthService.I.cancelPasswordReset());
    }
    _resendTimer?.cancel();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
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
      case _ForgotStage.enterPhone:
        final phone = toE164(_phoneCtrl.text);
        if (phone == null) {
          _showSnack('Enter a valid mobile number, e.g. 0917 123 4567.',
              isError: true);
          return;
        }
        _phoneE164 = phone;
        await _sendCode();
      case _ForgotStage.enterCode:
        final code = _codeCtrl.text.trim();
        final id = _verificationId;
        if (code.length != resetCodeLength || id == null) {
          _showSnack('Enter the $resetCodeLength-digit code from the text message.',
              isError: true);
          return;
        }
        await _checkCode(AuthService.I.credentialFor(id, code));
      case _ForgotStage.newPassword:
        await _savePassword();
      case _ForgotStage.success:
        Navigator.pop(context);
    }
  }

  /// Texts the code to [_phoneE164] (again, when [_resendToken] is set).
  Future<void> _sendCode() async {
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    // The number itself is never logged.
    _logger.info(_tag, 'Reset code requested', {'resend': _resendToken != null});
    final ResetCodeRequest request;
    try {
      request = await AuthService.I.sendResetCode(
        _phoneE164!,
        resendToken: _resendToken,
        // Android read the SMS by itself: no need to type the code.
        onAutoVerified: (credential) {
          if (mounted && _stage == _ForgotStage.enterCode && !_isLoading) {
            _checkCode(credential);
          }
        },
      );
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack(e.message, isError: true);
      return;
    }
    if (!mounted) return;
    final credential = request.credential;
    if (credential != null) {
      // Number verified instantly by Android.
      await _checkCode(credential);
      return;
    }
    _verificationId = request.verificationId;
    _resendToken = request.resendToken ?? _resendToken;
    _startResendCountdown();
    if (_stage == _ForgotStage.enterCode) {
      setState(() => _isLoading = false);
      _showSnack('A new code is on its way.');
    } else {
      _transitionTo(_ForgotStage.enterCode);
    }
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = _resendWait.inSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _checkCode(PhoneAuthCredential credential) async {
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      await AuthService.I.verifyResetCode(credential);
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack(e.message, isError: true);
      return;
    }
    _signedInForReset = true;
    if (!mounted) return;
    _logger.info(_tag, 'Code accepted');
    _transitionTo(_ForgotStage.newPassword);
  }

  Future<void> _savePassword() async {
    final password = _passwordCtrl.text;
    final problem = newPasswordProblem(password, _confirmCtrl.text);
    if (problem != null) {
      _showSnack(problem, isError: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      await AuthService.I.setNewPassword(password);
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack(e.message, isError: true);
      return;
    }
    _signedInForReset = false; // setNewPassword signed out
    _logger.info(_tag, 'Password reset finished');
    if (!mounted) return;
    _transitionTo(_ForgotStage.success);
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
        _ForgotStage.enterPhone => 'Forgot Password?',
        _ForgotStage.enterCode => 'Enter the Code',
        _ForgotStage.newPassword => 'New Password',
        _ForgotStage.success => 'Password Changed',
      };

  String get _stageSubtitle => switch (_stage) {
        _ForgotStage.enterPhone =>
          'Enter the mobile number on your account and we\'ll text you a code to reset your password.',
        _ForgotStage.enterCode =>
          'We sent a $resetCodeLength-digit code to ${_phoneCtrl.text.trim()}.',
        _ForgotStage.newPassword => 'Choose a new password for your account.',
        _ForgotStage.success => 'You can now sign in with your new password.',
      };

  String get _buttonLabel => switch (_stage) {
        _ForgotStage.enterPhone => 'Send Code',
        _ForgotStage.enterCode => 'Verify Code',
        _ForgotStage.newPassword => 'Save Password',
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
    final palette = context.palette;
    return SlideTransition(
      position: _stageSlide,
      child: FadeTransition(
        opacity: _stageFade,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: palette.shadow.withValues(alpha: 0.18),
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
                      color: palette.surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: palette.textSecondary),
                  ),
                ),

              Text(
                _stageTitle,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: palette.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                _stageSubtitle,
                style: TextStyle(fontSize: 13, color: palette.textMuted, height: 1.4),
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
      _ForgotStage.enterPhone => _buildEnterPhone(),
      _ForgotStage.enterCode => _buildEnterCode(),
      _ForgotStage.newPassword => _buildNewPassword(),
      _ForgotStage.success => _buildSuccess(),
    };
  }

  Widget _buildEnterPhone() {
    return _inputField(
      controller: _phoneCtrl,
      hint: 'Mobile number (e.g. 0917 123 4567)',
      icon: PhosphorIcons.phone(),
      keyboardType: TextInputType.phone,
      autofillHints: const [AutofillHints.telephoneNumber],
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-()]')),
        LengthLimitingTextInputFormatter(20),
      ],
    );
  }

  Widget _buildEnterCode() {
    return Column(
      children: [
        _inputField(
          controller: _codeCtrl,
          hint: '$resetCodeLength-digit code',
          icon: PhosphorIcons.chatCircleText(),
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(resetCodeLength),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      _codeCtrl.clear();
                      _resendTimer?.cancel();
                      setState(() {
                        _resendIn = 0;
                        _verificationId = null;
                        _resendToken = null;
                      });
                      _transitionTo(_ForgotStage.enterPhone);
                    },
              child: const Text('Change number'),
            ),
            TextButton(
              onPressed: _isLoading || _resendIn > 0 ? null : _sendCode,
              child: Text(_resendIn > 0 ? 'Resend in ${_resendIn}s' : 'Resend code'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNewPassword() {
    final toggle = IconButton(
      tooltip: _showPassword ? 'Hide password' : 'Show password',
      icon: Icon(
        _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 20,
        color: context.palette.textMuted,
      ),
      onPressed: () => setState(() => _showPassword = !_showPassword),
    );
    return Column(
      children: [
        _inputField(
          controller: _passwordCtrl,
          hint: 'New password',
          icon: PhosphorIcons.lockSimple(),
          obscureText: !_showPassword,
          suffix: toggle,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _inputField(
          controller: _confirmCtrl,
          hint: 'Confirm new password',
          icon: PhosphorIcons.lockSimple(),
          obscureText: !_showPassword,
          autofillHints: const [AutofillHints.newPassword],
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    final palette = context.palette;
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
          Text(
            'All Set!',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: palette.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Your password was changed. Sign in with your email and new password.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: palette.textMuted, height: 1.4),
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
    Iterable<String>? autofillHints,
    List<TextInputFormatter>? inputFormatters,
    TextInputAction textInputAction = TextInputAction.done,
  }) {
    final palette = context.palette;
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      // Numbers, codes and passwords must not be "corrected".
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onSubmitted: textInputAction == TextInputAction.done
          ? (_) => _onContinue()
          : null,
      inputFormatters: inputFormatters,
      style: TextStyle(fontSize: 14, color: palette.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14, color: palette.textFaint),
        prefixIcon: PhosphorIcon(icon, size: 20, color: palette.textFaint),
        suffixIcon: suffix,
        filled: true,
        fillColor: palette.inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2EA9AE), width: 1.8),
        ),
      ),
    );
  }}

/// Why [password] (typed twice, the second time as [confirm]) can't be the
/// new password, or null when it's fine.
String? newPasswordProblem(String password, String confirm) {
  if (password.length < minPasswordLength) {
    return 'Use at least $minPasswordLength characters.';
  }
  if (password.trim().isEmpty) return 'The password can\'t be only spaces.';
  if (password != confirm) return 'The passwords don\'t match.';
  return null;
}
