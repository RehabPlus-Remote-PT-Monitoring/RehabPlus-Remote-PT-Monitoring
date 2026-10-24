import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
// `show`: the full intl library also exports a TextDirection that clashes
// with Flutter's.
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../services/app_provider.dart';
import '../models/session.dart';
import 'login_page.dart';
import 'edit_profile_screen.dart';
import 'goals_screen.dart';
import 'privacy_legal_screen.dart';
import 'settings_screen.dart';
import '../widgets/profile_avatar.dart';
import '../core/responsive.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color primaryTeal = Color(0xFF23A8AA);
  static const String _tag = 'Profile';

  final DiagnosticLogger _logger = DiagnosticLogger.I;

  /// Guards against double taps on Edit and Sign Out.
  bool _editing = false;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _logger.info(_tag, 'Screen opened');
  }

  static const _emptyProfile = ProfileData(
    name: '',
    email: '',
    phone: '',
    dob: '',
    condition: '',
  );

  // Loaded by AppProvider on sign-in; the Consumer in build() rebuilds this
  // screen when it changes.
  ProfileData get _profile =>
      context.read<AppProvider>().profile ?? _emptyProfile;

  Future<void> _openEdit() async {
    if (_editing) return;
    _editing = true;
    _logger.info(_tag, 'Opening edit profile');
    final ProfileData? result;
    try {
      result = await Navigator.push<ProfileData>(
        context,
        MaterialPageRoute(builder: (_) => EditProfileScreen(initial: _profile)),
      );
    } finally {
      _editing = false;
    }
    if (result != null && mounted) {
      context.read<AppProvider>().updateProfile(result);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(children: [
          Icon(CupertinoIcons.checkmark_circle, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Text('Profile updated successfully!'),
        ]),
        backgroundColor: primaryTeal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final sessions = provider.sessionHistory;
        final avgCompliance = sessions.isEmpty
            ? 0.0
            : sessions.map((s) => s.overallCompliance).reduce((a, b) => a + b) / sessions.length;
        final totalSets = sessions.fold(0, (sum, s) => sum + s.completedSets);
        final totalReps = sessions.fold(0, (sum, s) => sum + s.completedReps);

        return Scaffold(
          backgroundColor: context.palette.background,
          body: SingleChildScrollView(
            child: Column(
              children: [
                _buildHeader(),
                // Header full width; the cards below stay phone-width on tablets.
                ReadableWidth(
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildStatsRow(sessions.length, totalSets, totalReps, avgCompliance),
                      const SizedBox(height: 14),
                      _buildInfoCard(
                        title: 'Personal Info',
                        icon: CupertinoIcons.person,
                        items: [
                          _InfoRow(icon: CupertinoIcons.person, label: 'Full Name', value: _profile.name),
                          _InfoRow(icon: CupertinoIcons.envelope, label: 'Email', value: _profile.email),
                          _InfoRow(icon: CupertinoIcons.phone, label: 'Phone', value: _profile.phone),
                          _InfoRow(icon: CupertinoIcons.gift, label: 'Date of Birth', value: _profile.dob),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildInfoCard(
                        title: 'Rehab Info',
                        icon: CupertinoIcons.bandage,
                        items: [
                          _InfoRow(icon: CupertinoIcons.bandage, label: 'Condition', value: _profile.condition),
                          _InfoRow(icon: CupertinoIcons.person_crop_square, label: 'Therapist', value: _profile.therapist),
                          _InfoRow(
                            icon: CupertinoIcons.calendar,
                            label: 'Program Start',
                            value: _profile.programStart == null
                                ? ''
                                : DateFormat.yMMMd().format(_profile.programStart!),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildExerciseBreakdownCard(sessions),
                      const SizedBox(height: 14),
                      _buildGoalsCard(),
                      const SizedBox(height: 14),
                      _buildSettingsCard(),
                      const SizedBox(height: 14),
                      _buildLegalCard(),
                      const SizedBox(height: 14),
                      _buildSignOutButton(),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: AppPalette.midTeal,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Profile', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  GestureDetector(
                    onTap: _openEdit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(CupertinoIcons.pencil, color: Colors.white, size: 14),
                          SizedBox(width: 5),
                          Text('Edit', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  ProfileAvatar(photo: _profile.photo, size: 64, onHeader: true),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_profile.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 3),
                      Text(_profile.email, style: const TextStyle(fontSize: 13, color: Colors.white70)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.circle_fill, size: 7, color: Color(0xFF69F0AE)),
                            SizedBox(width: 5),
                            Text('Active Patient', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(int sessions, int sets, int reps, double avg) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            _statItem('Sessions', '$sessions', CupertinoIcons.flame),
            _vDivider(),
            _statItem('Total Sets', '$sets', CupertinoIcons.repeat),
            _vDivider(),
            _statItem('Total Reps', '$reps', CupertinoIcons.arrow_2_circlepath),
            _vDivider(),
            _statItem('Avg Score', '${(avg * 100).toInt()}%', CupertinoIcons.chart_bar),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    final palette = context.palette;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: primaryTeal, size: 20),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: palette.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: palette.textMuted, fontSize: 11), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(width: 1, height: 36, color: context.palette.divider);

  Widget _buildInfoCard({required String title, required IconData icon, required List<_InfoRow> items}) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(color: primaryTeal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
                    child: Icon(icon, size: 16, color: primaryTeal),
                  ),
                  const SizedBox(width: 10),
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: palette.textPrimary)),
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(children: items),
            ),
          ],
        ),
      ),
    );
  }

  // Groups sessions by exercise name, most-performed first.
  Map<String, List<ExerciseSession>> _groupByExercise(List<ExerciseSession> sessions) {
    final grouped = <String, List<ExerciseSession>>{};
    for (final s in sessions) {
      grouped.putIfAbsent(s.exerciseName, () => []).add(s);
    }
    return Map.fromEntries(
      grouped.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length)),
    );
  }

  Widget _buildExerciseBreakdownCard(List<ExerciseSession> sessions) {
    if (sessions.isEmpty) return const SizedBox.shrink();
    final grouped = _groupByExercise(sessions);
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(color: primaryTeal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
                    child: const Icon(CupertinoIcons.flame, size: 16, color: primaryTeal),
                  ),
                  const SizedBox(width: 10),
                  Text('Exercise Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: palette.textPrimary)),
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: grouped.entries
                    .map((e) => _exerciseBreakdownRow(e.key, e.value))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _exerciseBreakdownRow(String exerciseName, List<ExerciseSession> sessions) {
    final timesDone = sessions.length;
    final repCounts = sessions.map((s) => s.completedReps).toSet();

    // Most exercises finish at the same rep target every time, so show
    // "10 reps each"; if they varied, fall back to a total instead.
    final repsLabel = repCounts.length == 1
        ? '${repCounts.first} reps each'
        : '${sessions.fold(0, (sum, s) => sum + s.completedReps)} reps total';
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(CupertinoIcons.checkmark_circle, size: 17, color: palette.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              exerciseName,
              style: TextStyle(color: palette.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '×$timesDone  ·  $repsLabel',
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }

  /// Opens My Goals: the rehab goals the therapist set on the dashboard.
  Widget _buildGoalsCard() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: ListTile(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GoalsScreen())),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: primaryTeal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
            child: const Icon(CupertinoIcons.flag, size: 16, color: primaryTeal),
          ),
          title: Text('My Goals', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: palette.textPrimary)),
          subtitle: Text('The recovery goals your therapist set for you', style: TextStyle(fontSize: 12, color: palette.textMuted)),
          trailing: Icon(CupertinoIcons.chevron_right, color: palette.textFaint, size: 20),
        ),
      ),
    );
  }

  /// Opens Settings: exercise feedback, camera, reminders, notifications,
  /// text size, account and support.
  Widget _buildSettingsCard() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: ListTile(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: primaryTeal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
            child: const Icon(CupertinoIcons.gear, size: 16, color: primaryTeal),
          ),
          title: Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: palette.textPrimary)),
          subtitle: Text('Exercise, camera, reminders, notifications and more', style: TextStyle(fontSize: 12, color: palette.textMuted)),
          trailing: Icon(CupertinoIcons.chevron_right, color: palette.textFaint, size: 20),
        ),
      ),
    );
  }

  /// Opens Privacy & Legal: account info, Terms and Conditions, Privacy Policy.
  Widget _buildLegalCard() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: ListTile(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyLegalScreen())),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: primaryTeal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
            child: const Icon(CupertinoIcons.shield, size: 16, color: primaryTeal),
          ),
          title: Text('Privacy & Legal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: palette.textPrimary)),
          subtitle: Text('Account info, terms and privacy policy', style: TextStyle(fontSize: 12, color: palette.textMuted)),
          trailing: Icon(CupertinoIcons.chevron_right, color: palette.textFaint, size: 20),
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    _logger.info(_tag, 'Sign-out requested');
    try {
      await context.read<AppProvider>().signOut();
    } catch (e, st) {
      _logger.error(_tag, 'Sign-out failed', null, e, st);
      if (!mounted) return;
      setState(() => _signingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not sign out. Please try again.')),
      );
      return;
    }
    _logger.info(_tag, 'Signed out');
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  Widget _buildSignOutButton() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: _signingOut ? null : _signOut,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.square_arrow_right, color: Colors.red.shade400, size: 18),
              const SizedBox(width: 8),
              Text('Sign Out', style: TextStyle(color: Colors.red.shade400, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: palette.textMuted),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: palette.textMuted, fontSize: 13)),
          const Spacer(),
          Text(value.isEmpty ? '—' : value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: palette.textPrimary)),
        ],
      ),
    );
  }
}
