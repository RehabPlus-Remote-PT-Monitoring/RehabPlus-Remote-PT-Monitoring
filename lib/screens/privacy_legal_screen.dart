import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../core/diagnostic_logger.dart';
import '../legal/legal_info.dart';
import '../widgets/ios_list.dart';
import '../widgets/ios_page.dart';
import 'account_info_screen.dart';
import 'legal_document_screen.dart';

/// Profile > Privacy & Legal: the patient's account information, the Terms
/// and Conditions and the Privacy Policy, as one iOS inset grouped list with
/// the documents' version as its footnote.
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

  /// What the back button on the documents opened from here says
  /// ("‹ Privacy"); the full "Privacy & Legal" is long for a back button.
  static const String _backTitle = 'Privacy';

  @override
  void initState() {
    super.initState();
    DiagnosticLogger.I.info(_tag, 'Screen opened');
  }

  void _open(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return IosPage(
      title: 'Privacy & Legal',
      previousPageTitle: 'Profile',
      children: [
        IosSection(
          footer:
              'Version ${LegalInfo.version} · effective ${LegalInfo.effectiveDate}',
          children: [
            IosRow(
              icon: CupertinoIcons.person_fill,
              iconColor: IosColors.gray,
              title: 'Account Info',
              subtitle: 'View and update your personal information',
              onTap: () => _open(context, const AccountInfoScreen()),
            ),
            IosRow(
              icon: CupertinoIcons.doc_text_fill,
              iconColor: IosColors.blue,
              title: 'Terms and Conditions',
              subtitle: 'The rules for using RehabPlus',
              onTap: () => _open(
                context,
                const LegalDocumentScreen.terms(previousPageTitle: _backTitle),
              ),
            ),
            IosRow(
              icon: CupertinoIcons.lock_shield_fill,
              iconColor: IosColors.indigo,
              title: 'Privacy Policy',
              subtitle: 'How your information is used and protected',
              onTap: () => _open(
                context,
                const LegalDocumentScreen.privacy(
                  previousPageTitle: _backTitle,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
