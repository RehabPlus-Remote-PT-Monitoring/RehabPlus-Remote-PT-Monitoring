import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../services/app_provider.dart';
import '../widgets/profile_avatar.dart';
import '../core/responsive.dart';
import 'edit_profile_screen.dart';

/// Privacy & Legal > Account Info: the patient's personal information, with a
/// button to update it (name, phone and date of birth; the email is the login
/// and is changed by the clinic).
///
/// Stateful only so "Screen opened" is logged once, not on every rebuild.
class AccountInfoScreen extends StatefulWidget {
  const AccountInfoScreen({super.key});

  static const Color primaryTeal = Color(0xFF23A8AA);
  static const Color darkTeal = Color(0xFF0D6E71);

  @override
  State<AccountInfoScreen> createState() => _AccountInfoScreenState();
}

class _AccountInfoScreenState extends State<AccountInfoScreen> {
  static const String _tag = 'AccountInfo';
  static const Color primaryTeal = AccountInfoScreen.primaryTeal;
  static const Color darkTeal = AccountInfoScreen.darkTeal;

  final DiagnosticLogger _logger = DiagnosticLogger.I;

  /// Stops a double tap from opening the edit page twice.
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _logger.info(_tag, 'Screen opened');
  }

  Future<void> _update(BuildContext context, ProfileData current) async {
    if (_editing) return;
    _editing = true;
    _logger.info(_tag, 'Opening edit profile');
    final ProfileData? result;
    try {
      result = await Navigator.push<ProfileData>(
        context,
        MaterialPageRoute(builder: (_) => EditProfileScreen(initial: current)),
      );
    } finally {
      _editing = false;
    }
    if (result == null || !context.mounted) return;
    context.read<AppProvider>().updateProfile(result);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Account information updated'),
          ],
        ),
        backgroundColor: primaryTeal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile =
        context.watch<AppProvider>().profile ??
        const ProfileData(name: '', email: '', phone: '', dob: '', condition: '');
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: ListView(
              padding: readablePadding(context, const EdgeInsets.fromLTRB(16, 20, 16, 24)),
              children: [
                Center(child: ProfileAvatar(photo: profile.photo, size: 88)),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
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
                    children: [
                      _row(Icons.person_outline, 'Full Name', profile.name),
                      _divider(),
                      _row(Icons.email_outlined, 'Email', profile.email),
                      _divider(),
                      _row(Icons.phone_outlined, 'Phone', profile.phone),
                      _divider(),
                      _row(Icons.cake_outlined, 'Date of Birth', profile.dob),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Your email is your login. To change it, contact the clinic '
                    'through Help & Support.',
                    style: TextStyle(fontSize: 12, color: palette.textMuted),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => _update(context, profile),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    label: const Text(
                      'Update account information',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryTeal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
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

  Widget _header(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [darkTeal, Color(0xFF1A8587), primaryTeal],
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
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account Info',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Your personal information',
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: primaryTeal),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: palette.textMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: context.palette.divider);
}
