import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
// `show`: the full intl library also exports a TextDirection that clashes
// with Flutter's.
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import '../core/diagnostic_logger.dart';
import '../services/app_provider.dart';
import '../models/session.dart';
import 'login_page.dart';
import 'edit_profile_screen.dart';
import 'goals_screen.dart';
import 'privacy_legal_screen.dart';
import 'settings_screen.dart';
import '../widgets/ios_list.dart';
import '../widgets/ios_page.dart';
import '../widgets/profile_parts.dart';
import '../core/responsive.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

/// The Profile tab (4th tab of the dashboard), laid out like the Apple ID
/// page of iPhone Settings: a large "Profile" title with Edit, the identity
/// card, the numbers, grouped info sections, links and Sign Out.
///
/// It is a root tab page, so there is no back button. On wide screens
/// (tablet landscape) the identity, numbers, links and Sign Out sit on the
/// left and the info sections on the right.
class _ProfileScreenState extends State<ProfileScreen> {
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
    // No "updated" snackbar: the page shows the new details straight away.
    if (result != null && mounted) {
      context.read<AppProvider>().updateProfile(result);
      _logger.info(_tag, 'Profile updated from edit');
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

        // The cards, built once and arranged per width below.
        final identity = _buildIdentityCard();
        final stats = _buildStatsCard(sessions.length, totalSets, totalReps, avgCompliance);
        final personal = _buildPersonalSection();
        final rehab = _buildRehabSection();
        final breakdown = _buildExerciseBreakdownSection(sessions);
        final links = _buildLinksSection();
        final signOut = _buildSignOutSection();

        final List<Widget> content;
        if (isTwoColumn(context)) {
          // Tablet landscape: who you are and what you can do on the left,
          // the details on the right.
          content = [
            AdaptiveColumns(
              left: [identity, const SizedBox(height: 16), stats, links, signOut],
              right: [personal, rehab, breakdown],
            ),
          ];
        } else {
          // Phone and tablet portrait: one column in reading order.
          content = [
            identity,
            const SizedBox(height: 16),
            stats,
            personal,
            rehab,
            breakdown,
            links,
            signOut,
          ];
        }

        // The dashboard's tab bar may float translucently over the bottom
        // of this page; the bottom safe-area padding lets the last section
        // scroll clear of it.
        final bottomInset = MediaQuery.paddingOf(context).bottom;

        return IosPage(
          title: 'Profile',
          trailing: ProfileNavTextButton(label: 'Edit', onPressed: _openEdit),
          maxWidth: adaptiveMaxWidth(context),
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + bottomInset),
          children: content,
        );
      },
    );
  }

  Widget _buildIdentityCard() {
    return ProfileIdentityCard(
      photo: _profile.photo,
      name: _profile.name,
      email: _profile.email,
      statusLabel: 'Active Patient',
      onTap: _openEdit,
    );
  }

  Widget _buildStatsCard(int sessions, int sets, int reps, double avg) {
    return ProfileStatsCard(
      stats: [
        ProfileStat(label: 'Sessions', value: '$sessions'),
        ProfileStat(label: 'Total Sets', value: '$sets'),
        ProfileStat(label: 'Total Reps', value: '$reps'),
        ProfileStat(label: 'Avg Score', value: '${(avg * 100).toInt()}%'),
      ],
    );
  }

  Widget _buildPersonalSection() {
    return IosSection(
      header: 'Personal Info',
      hasLeading: false,
      children: [
        ProfileInfoRow(label: 'Full Name', value: _profile.name),
        ProfileInfoRow(label: 'Email', value: _profile.email),
        ProfileInfoRow(label: 'Phone', value: _profile.phone),
        ProfileInfoRow(label: 'Date of Birth', value: _profile.dob),
      ],
    );
  }

  Widget _buildRehabSection() {
    final programStart = _profile.programStart == null
        ? ''
        : DateFormat.yMMMd().format(_profile.programStart!);
    return IosSection(
      header: 'Rehab Info',
      hasLeading: false,
      children: [
        ProfileInfoRow(label: 'Condition', value: _profile.condition),
        ProfileInfoRow(label: 'Therapist', value: _profile.therapist),
        ProfileInfoRow(label: 'Program Start', value: programStart),
      ],
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

  /// One row per exercise: how often it was done and the reps. Hidden until
  /// there is at least one session.
  Widget _buildExerciseBreakdownSection(List<ExerciseSession> sessions) {
    if (sessions.isEmpty) return const SizedBox.shrink();
    final grouped = _groupByExercise(sessions);
    return IosSection(
      header: 'Exercise Breakdown',
      hasLeading: false,
      children: grouped.entries
          .map((e) => _exerciseBreakdownRow(e.key, e.value))
          .toList(),
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
    final timesLabel = timesDone == 1 ? '1 time' : '$timesDone times';

    return IosRow(
      title: exerciseName,
      subtitle: repsLabel,
      value: timesLabel,
      showChevron: false,
    );
  }

  /// My Goals (the goals the therapist set), Settings (exercise feedback,
  /// camera, reminders, notifications, text size, account and support) and
  /// Privacy & Legal (account info, terms, privacy policy).
  Widget _buildLinksSection() {
    return IosSection(
      children: [
        IosRow(
          icon: CupertinoIcons.flag_fill,
          iconColor: IosColors.orange,
          title: 'My Goals',
          subtitle: 'The recovery goals your therapist set for you',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GoalsScreen())),
        ),
        IosRow(
          icon: CupertinoIcons.gear_solid,
          iconColor: IosColors.gray,
          title: 'Settings',
          subtitle: 'Exercise, camera, reminders, notifications and more',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
        IosRow(
          icon: CupertinoIcons.hand_raised_fill,
          iconColor: IosColors.blue,
          title: 'Privacy & Legal',
          subtitle: 'Account info, terms and privacy policy',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyLegalScreen())),
        ),
      ],
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

  Widget _buildSignOutSection() {
    return IosSection(
      hasLeading: false,
      children: [
        ProfileCentredActionRow(
          title: 'Sign Out',
          destructive: true,
          busy: _signingOut,
          onTap: _signOut,
        ),
      ],
    );
  }
}
