import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../legal/legal_info.dart';
import '../core/responsive.dart';
import 'account_info_screen.dart';
import 'legal_document_screen.dart';

/// Profile > Privacy & Legal: the patient's account information, the Terms
/// and Conditions and the Privacy Policy.
///
/// Stateful only so "Screen opened" is logged once, not on every rebuild.
class PrivacyLegalScreen extends StatefulWidget {
  const PrivacyLegalScreen({super.key});

  static const Color primaryTeal = Color(0xFF23A8AA);
  static const Color darkTeal = Color(0xFF0D6E71);

  @override
  State<PrivacyLegalScreen> createState() => _PrivacyLegalScreenState();
}

class _PrivacyLegalScreenState extends State<PrivacyLegalScreen> {
  static const String _tag = 'PrivacyLegal';
  static const Color primaryTeal = PrivacyLegalScreen.primaryTeal;
  static const Color darkTeal = PrivacyLegalScreen.darkTeal;

  @override
  void initState() {
    super.initState();
    DiagnosticLogger.I.info(_tag, 'Screen opened');
  }

  void _open(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
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
                Container(
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
                      _choice(
                        icon: Icons.manage_accounts_outlined,
                        label: 'Account Info',
                        subtitle: 'View and update your personal information',
                        onTap: () => _open(context, const AccountInfoScreen()),
                      ),
                      const Divider(height: 1, indent: 64, endIndent: 16),
                      _choice(
                        icon: Icons.description_outlined,
                        label: 'Terms and Conditions',
                        subtitle: 'The rules for using RehabPlus',
                        onTap: () =>
                            _open(context, const LegalDocumentScreen.terms()),
                      ),
                      const Divider(height: 1, indent: 64, endIndent: 16),
                      _choice(
                        icon: Icons.privacy_tip_outlined,
                        label: 'Privacy Policy',
                        subtitle: 'How your information is used and protected',
                        onTap: () =>
                            _open(context, const LegalDocumentScreen.privacy()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Version ${LegalInfo.version} · effective ${LegalInfo.effectiveDate}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: palette.textMuted),
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Privacy & Legal',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choice({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final palette = context.palette;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: primaryTeal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: primaryTeal),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: palette.textMuted),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: palette.textFaint,
        size: 20,
      ),
    );
  }
}
