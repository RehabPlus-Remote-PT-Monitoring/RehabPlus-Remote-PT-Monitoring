import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../core/responsive.dart';
import '../services/auth_service.dart';
import 'forgot_password_screen.dart';

/// Settings > Change password, in the style of Facebook's: the current
/// password, the new one twice, a strength bar, and a link for people who
/// have forgotten the current one. Pops with `true` once the password is
/// changed. The patient stays signed in.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const String _tag = 'ChangePassword';
  final DiagnosticLogger _logger = DiagnosticLogger.I;

  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _showPasswords = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    DiagnosticLogger.I.info(_tag, 'Screen opened');
    // The strength bar and the Save button follow what is typed.
    _newCtrl.addListener(_changed);
    _currentCtrl.addListener(_changed);
    _confirmCtrl.addListener(_changed);
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() => _error = null);
  }

  /// 0 (nothing yet) to 4 (strong), from length and character variety.
  /// Only a rough guide: the real minimum is checked by [newPasswordProblem].
  static int strengthOf(String password) {
    if (password.isEmpty) return 0;
    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[a-zA-Z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password) ||
        RegExp(r'[A-Z]').hasMatch(password)) {
      score++;
    }
    return score.clamp(1, 4);
  }

  /// What to show the patient instead of a Save, or null when it's valid.
  String? _problem() {
    if (_currentCtrl.text.isEmpty) return 'Enter your current password.';
    final problem = newPasswordProblem(_newCtrl.text, _confirmCtrl.text);
    if (problem != null) return problem;
    if (_newCtrl.text == _currentCtrl.text) {
      return 'Choose a password you haven\'t used before.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final problem = _problem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await AuthService.I.changePassword(
        currentPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
      );
      _logger.info(_tag, 'Password changed');
      if (!mounted) return;
      Navigator.pop(context, true);
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  void _openForgot() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final canSave = !_saving && _problem() == null;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: ListView(
              padding: readablePadding(
                context,
                const EdgeInsets.fromLTRB(16, 20, 16, 24),
              ),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: palette.shadow.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field(
                        controller: _currentCtrl,
                        label: 'Current password',
                        textInputAction: TextInputAction.next,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _saving ? null : _openForgot,
                          child: const Text('Forgot your current password?'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _field(
                        controller: _newCtrl,
                        label: 'New password',
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      _StrengthBar(strength: strengthOf(_newCtrl.text)),
                      const SizedBox(height: 4),
                      Text(
                        'At least $minPasswordLength characters. Mix letters, '
                        'numbers and symbols for a stronger one.',
                        style: TextStyle(fontSize: 12, color: palette.textMuted),
                      ),
                      const SizedBox(height: 14),
                      _field(
                        controller: _confirmCtrl,
                        label: 'Re-type new password',
                        textInputAction: TextInputAction.done,
                        onSubmitted: canSave ? (_) => _save() : null,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Checkbox(
                            value: _showPasswords,
                            onChanged: (v) =>
                                setState(() => _showPasswords = v ?? false),
                            activeColor: AppPalette.teal,
                          ),
                          Text(
                            'Show passwords',
                            style: TextStyle(fontSize: 13, color: palette.textSecondary),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFE53935),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: canSave ? _save : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.teal,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: palette.surfaceMuted,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Save changes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required TextInputAction textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    final palette = context.palette;
    return TextField(
      controller: controller,
      obscureText: !_showPasswords,
      autocorrect: false,
      enableSuggestions: false,
      enabled: !_saving,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: TextStyle(fontSize: 14, color: palette.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 14, color: palette.textMuted),
        prefixIcon: PhosphorIcon(
          PhosphorIcons.lockSimple(),
          size: 20,
          color: palette.textFaint,
        ),
        filled: true,
        fillColor: palette.inputFill,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppPalette.teal, width: 1.8),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: AppPalette.headerGradient,
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
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                onPressed: _saving ? null : () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
              const Text(
                'Change Password',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four-segment bar under the new password: grey when empty, then red,
/// amber, teal and green as the password gets stronger.
class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.strength});

  /// 0 to 4, see [_ChangePasswordScreenState.strengthOf].
  final int strength;

  static const _labels = ['', 'Weak', 'Fair', 'Good', 'Strong'];
  static const _colors = [
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFF23A8AA),
    Color(0xFF2E7D32),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = strength == 0 ? palette.divider : _colors[strength - 1];
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i < strength ? color : palette.surfaceMuted,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
        const SizedBox(width: 10),
        SizedBox(
          width: 44,
          child: Text(
            _labels[strength],
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ),
      ],
    );
  }
}
