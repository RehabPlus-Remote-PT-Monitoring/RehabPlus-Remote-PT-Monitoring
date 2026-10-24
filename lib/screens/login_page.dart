import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show LengthLimitingTextInputFormatter, TextInput;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../services/app_provider.dart';
import '../services/auth_service.dart';
import '../core/responsive.dart';
import 'consent_screen.dart';
import 'forgot_password_screen.dart';

/// Longest e-mail address allowed by the standards (RFC 5321).
const int maxEmailLength = 254;

/// A cheap "is this shaped like an e-mail address" check, run before any
/// network call: something@something.tld, no spaces. Firebase does the real
/// validation; this only catches obvious typos early.
bool looksLikeEmail(String value) {
  if (value.isEmpty || value.length > maxEmailLength) return false;
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  static const String _tag = 'LoginPage';
  final DiagnosticLogger _logger = DiagnosticLogger.I;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool showPassword = false;
  bool _isLoading = false;

  late final AnimationController _fadeCtrl;
  late final AnimationController _slideCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _logoScaleAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _slideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _logoScaleAnim = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.elasticOut));

    // The page may already be gone after the delay (e.g. a fast sign-in from
    // a test or a push tap); a disposed controller throws if started.
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      _fadeCtrl.forward();
      _slideCtrl.forward();
    });

    _logger.info(_tag, 'Screen opened');
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  Future<void> login() async {
    // The button is disabled while loading, but the keyboard's "done" key
    // can still call this: never run two sign-ins at once.
    if (_isLoading) return;

    final email = emailController.text.trim();
    // The password is used exactly as typed: spaces can be part of it, and
    // trimming would silently sign in with a different password.
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showSnack('Please enter your email and password.', isError: true);
      return;
    }
    if (!looksLikeEmail(email)) {
      _showSnack('Enter a valid email address.', isError: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    final stopwatch = Stopwatch()..start();
    // Never log the e-mail or password; AuthService logs the Firebase code.
    _logger.info(_tag, 'Sign-in attempt');
    try {
      await AuthService.I.signIn(email, password);
    } on AuthFailure catch (e) {
      _logger.warn(_tag, 'Sign-in rejected', {
        'ms': stopwatch.elapsedMilliseconds,
      });
      if (!mounted) return;
      setState(() => _isLoading = false);
      // AuthFailure.message is written for the patient and is deliberately
      // generic ("Invalid email or password.") so accounts can't be probed.
      _showSnack(e.message, isError: true);
      return;
    } catch (e, st) {
      // Anything unexpected (plugin error, no Firebase): never leave the
      // button spinning forever.
      _logger.error(_tag, 'Sign-in crashed', null, e, st);
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack('Sign-in failed. Please try again.', isError: true);
      return;
    }
    _logger.info(_tag, 'Sign-in succeeded', {
      'ms': stopwatch.elapsedMilliseconds,
    });
    // Lets the phone's password manager offer to save the login.
    TextInput.finishAutofillContext();

    if (!mounted) return;
    try {
      await context.read<AppProvider>().loadUserData();
    } catch (e, st) {
      // Not fatal: the dashboard shows empty data and reloads later.
      _logger.warn(_tag, 'Loading patient data after sign-in failed', null, e, st);
    }

    // The dashboard, or the Terms & Privacy screen if not accepted yet.
    Widget next;
    try {
      next = await ConsentScreen.gate();
    } catch (e, st) {
      // Fail closed: if we can't tell whether they accepted, ask again.
      _logger.error(_tag, 'Consent check after sign-in failed', null, e, st);
      next = const ConsentScreen();
    }
    if (!mounted) return;
    _logger.info(_tag, 'Leaving login', {'next': next.runtimeType.toString()});
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, _, _) => next,
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: child,
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? const Color(0xFFE53935) : const Color(0xFF23A8AA),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
            Positioned(
              top: -80,
              right: -80,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              top: 60,
              right: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              left: -60,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
              ),
            ),

            SafeArea(
              child: ReadableWidth(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),

                        // Logo with scale animation
                        ScaleTransition(
                          scale: _logoScaleAnim,
                          child: FadeTransition(
                            opacity: _fadeAnim,
                            child: const _RehabLogo(),
                          ),
                        ),

                        const SizedBox(height: 18),

                        FadeTransition(
                          opacity: _fadeAnim,
                          child: const Column(
                            children: [
                              Text(
                                'Rehab +',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                              Text(
                                'Physiotherapy',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 2,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Your Journey Starts Here',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 36),

                        // Login card with slide animation
                        SlideTransition(
                          position: _slideAnim,
                          child: FadeTransition(
                            opacity: _fadeAnim,
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
                                  Text(
                                    'Welcome',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Sign in to continue your recovery',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: palette.textMuted,
                                    ),
                                  ),

                                  const SizedBox(height: 28),

                                  // One autofill group, so password managers
                                  // fill (and later save) both fields together.
                                  AutofillGroup(
                                    child: Column(
                                      children: [
                                        _RehabTextField(
                                          controller: emailController,
                                          hint: 'Email address',
                                          icon: PhosphorIcons.envelopeSimple(),
                                          keyboardType: TextInputType.emailAddress,
                                          autofillHints: const [AutofillHints.email, AutofillHints.username],
                                          textInputAction: TextInputAction.next,
                                          maxLength: maxEmailLength,
                                        ),

                                        const SizedBox(height: 14),

                                        _RehabTextField(
                                          controller: passwordController,
                                          hint: 'Password',
                                          icon: PhosphorIcons.lockSimple(),
                                          obscureText: !showPassword,
                                          isPassword: true,
                                          autofillHints: const [AutofillHints.password],
                                          textInputAction: TextInputAction.done,
                                          onSubmitted: (_) => login(),
                                          suffix: IconButton(
                                            tooltip: showPassword ? 'Hide password' : 'Show password',
                                            onPressed: () => setState(() => showPassword = !showPassword),
                                            icon: PhosphorIcon(
                                              showPassword ? PhosphorIcons.eyeSlash() : PhosphorIcons.eye(),
                                              size: 20,
                                              color: palette.textFaint,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        'Forgot Password?',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF2EA9AE),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 22),

                                  // Sign In button
                                  SizedBox(
                                    width: double.infinity,
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : login,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF1E8E92),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 300),
                                        child: _isLoading
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child: CircularProgressIndicator(
                                                  color: Colors.white,
                                                  strokeWidth: 2.5,
                                                ),
                                              )
                                            : const Text(
                                                'Sign In',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 22),

                                  Divider(color: palette.divider, thickness: 1.5),

                                  const SizedBox(height: 16),

                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      PhosphorIcon(
                                        PhosphorIcons.shieldCheck(),
                                        size: 14,
                                        color: palette.textFaint,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Secured Access · Patients Only',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: palette.textFaint,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RehabLogo extends StatelessWidget {
  const _RehabLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          PhosphorIcon(PhosphorIcons.shieldPlus(), color: Colors.white, size: 46),
        ],
      ),
    );
  }
}

class _RehabTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final PhosphorIconData icon;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;

  /// A password field: never autocorrected, never learnt by the keyboard's
  /// suggestion dictionary (even while "show password" is on).
  final bool isPassword;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  /// Hard input limit (no counter is shown); null for no limit.
  final int? maxLength;

  const _RehabTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffix,
    this.keyboardType,
    this.isPassword = false,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    // E-mail addresses and passwords must not be "corrected" by the keyboard.
    final noAutocorrect =
        isPassword || keyboardType == TextInputType.emailAddress;
    final palette = context.palette;
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autocorrect: !noAutocorrect,
      enableSuggestions: !noAutocorrect,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      inputFormatters: [
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
      ],
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
  }
}
