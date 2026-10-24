import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/diagnostic_logger.dart';
import '../services/app_provider.dart';
import '../widgets/ios_list.dart';
import '../widgets/ios_page.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_parts.dart';
import 'edit_profile_screen.dart';

/// Privacy & Legal > Account Info: the patient's personal information as an
/// iOS grouped list, with Edit in the navigation bar to update it (name,
/// phone and date of birth; the email is the login and is changed by the
/// clinic).
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
        MaterialPageRoute(
          builder: (_) => EditProfileScreen(
            initial: current,
            previousPageTitle: 'Account Info',
          ),
        ),
      );
    } finally {
      _editing = false;
    }
    if (result == null || !context.mounted) return;
    // No "updated" snackbar: this page rebuilds with the new details.
    context.read<AppProvider>().updateProfile(result);
    _logger.info(_tag, 'Account information updated');
  }

  @override
  Widget build(BuildContext context) {
    final profile =
        context.watch<AppProvider>().profile ??
        const ProfileData(name: '', email: '', phone: '', dob: '', condition: '');
    return IosPage(
      title: 'Account Info',
      previousPageTitle: 'Privacy',
      trailing: ProfileNavTextButton(
        label: 'Edit',
        onPressed: () => _update(context, profile),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Center(child: ProfileAvatar(photo: profile.photo, size: 88)),
        ),
        IosSection(
          header: 'Personal Info',
          footer:
              'Your email is your login. To change it, contact the clinic '
              'through Help & Support.',
          hasLeading: false,
          children: [
            ProfileInfoRow(label: 'Full Name', value: profile.name),
            ProfileInfoRow(label: 'Email', value: profile.email),
            ProfileInfoRow(label: 'Phone', value: profile.phone),
            ProfileInfoRow(label: 'Date of Birth', value: profile.dob),
          ],
        ),
        // A full-width row as well as the nav-bar Edit, so the action is
        // obvious to patients who don't look at the top corner.
        IosSection(
          hasLeading: false,
          children: [
            ProfileCentredActionRow(
              title: 'Update Account Information',
              onTap: () => _update(context, profile),
            ),
          ],
        ),
      ],
    );
  }
}
