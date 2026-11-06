import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../core/responsive.dart';
import '../services/auth_service.dart';

// Reset with the temporary password the therapist gives the patient: the
// patient types their email, that temporary password and a new password.
enum _Stage { form, success }

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

  _Stage _stage = _Stage.form;

  final _emailCtrl = TextEditingController();
  final _tempCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isLoading = false;
  bool _showPassword = false;

  // Entrance animation for the card
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  // Success pulse animation
  late final AnimationController _successCtrl;
  late final Animation<double> _successScale;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _entryCtrl.forward();

    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _successScale = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut));

    _logger.info(_tag, 'Screen opened');
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _tempCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _entryCtrl.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    // The keyboard's "done" key can call this while a request is running.
    if (_isLoading) return;
    if (_stage == _Stage.success) {
      Navigator.pop(context);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final temporary = _tempCtrl.text;
    final password = _passwordCtrl.text;

    if (!_looksLikeEmail(email)) {
      _showSnack('Enter the email address on your account.', isError: true);
      return;
    }
    if (temporary.isEmpty) {
      _showSnack('Enter the temporary password from your therapist.',
          isError: true);
      return;
    }
    final problem = newPasswordProblem(password, _confirmCtrl.text);
    if (problem != null) {
      _showSnack(problem, isError: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    // The email and passwords are never logged.
    _logger.info(_tag, 'Password reset requested');
    try {
      await AuthService.I.resetWithTemporaryPassword(
        email: email,
        temporaryPassword: temporary,
        newPassword: password,
      );
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack(e.message, isError: true);
      return;
    }
    if (!mounted) return;
    _logger.info(_tag, 'Password reset finished');
    setState(() {
      _stage = _Stage.success;
      _isLoading = false;
    });
    _successCtrl.forward();
  }

  static bool _looksLikeEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

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
        _Stage.form => 'Forgot Password?',
        _Stage.success => 'Password Changed',
      };

  String get _stageSubtitle => switch (_stage) {
        _Stage.form =>
          'Ask your therapist for a temporary password. Enter it with your email, then choose your new password.',
        _Stage.success => 'You can now sign in with your new password.',
      };

  String get _buttonLabel => switch (_stage) {
        _Stage.form => 'Set New Password',
        _Stage.success => 'Back to Login',
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
                  padding: readablePadding(
                      context, const EdgeInsets.symmetric(horizontal: 28)),
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
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: opacity),
          shape: BoxShape.circle,
        ),
      );

  // ── Branding header ───────────────────────────────────────────────────────
  Widget _buildBrandingHeader() {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.3), width: 2),
          ),
          child: Center(
            child: PhosphorIcon(PhosphorIcons.shieldPlus(),
                color: Colors.white, size: 42),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Rehab +',
          style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 1),
        ),
        const Text(
          'Physiotherapy',
          style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 2),
        ),
      ],
    );
  }

  // ── Card wrapper ──────────────────────────────────────────────────────────
  Widget _buildCard() {
    final palette = context.palette;
    return SlideTransition(
      position: _entrySlide,
      child: FadeTransition(
        opacity: _entryFade,
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
              if (_stage == _Stage.form)
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: palette.surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.arrow_back_ios_new_rounded,
                        size: 16, color: palette.textSecondary),
                  ),
                ),

              Text(
                _stageTitle,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: palette.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                _stageSubtitle,
                style: TextStyle(
                    fontSize: 13, color: palette.textMuted, height: 1.4),
              ),
              const SizedBox(height: 28),

              if (_stage == _Stage.form) _buildForm() else _buildSuccess(),

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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : Text(
                            _buttonLabel,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5),
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

  Widget _buildForm() {
    final toggle = IconButton(
      tooltip: _showPassword ? 'Hide passwords' : 'Show passwords',
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
          controller: _emailCtrl,
          hint: 'Email',
          icon: PhosphorIcons.envelopeSimple(),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _inputField(
          controller: _tempCtrl,
          hint: 'Temporary password',
          icon: PhosphorIcons.key(),
          obscureText: !_showPassword,
          suffix: toggle,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _inputField(
          controller: _passwordCtrl,
          hint: 'New password',
          icon: PhosphorIcons.lockSimple(),
          obscureText: !_showPassword,
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
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF23A8AA), Color(0xFF0D6E71)]),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF23A8AA).withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 40),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'All Set!',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Your password was changed. Sign in with your email and new password.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, color: palette.textMuted, height: 1.4),
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
      // Passwords and codes must not be "corrected".
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
  }
}

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
