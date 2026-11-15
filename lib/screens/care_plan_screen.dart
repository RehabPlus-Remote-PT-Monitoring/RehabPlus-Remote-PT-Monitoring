// lib/screens/care_plan_screen.dart
//
// Profile > "Care plan & clearance": four clearly separated sections,
// Exercise completion, Compliance, Medical clearance and Precautions from
// your clinician (design doc §6). Read-only; everything here is set by the
// clinic on the dashboard.
//
// Data: the prescriptions, clinical profile and clearance records come from
// ClinicalService (each read can fail on its own and is then shown as
// "unavailable", never as cleared); the session history comes from
// AppProvider. Pull to refresh reloads both.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../core/responsive.dart';
import '../models/session.dart';
import '../services/app_provider.dart';
import '../services/care_plan_data.dart';
import '../services/clinical_service.dart';
import '../widgets/care_plan_sections.dart';
import '../widgets/header_column.dart';

class CarePlanScreen extends StatefulWidget {
  const CarePlanScreen({super.key, this.loader, this.sessions});

  /// For tests: replaces the Firestore reads.
  final Future<CarePlanSnapshot> Function()? loader;

  /// For tests: a fixed session history instead of AppProvider's.
  final List<ExerciseSession>? sessions;

  @override
  State<CarePlanScreen> createState() => _CarePlanScreenState();
}

class _CarePlanScreenState extends State<CarePlanScreen> {
  static const String _tag = 'CarePlan';

  final DiagnosticLogger _logger = DiagnosticLogger.I;
  late Future<CarePlanSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _logger.info(_tag, 'Screen opened');
    _snapshot = _load();
  }

  /// One load of the three dashboard-written reads. ClinicalService never
  /// throws, but an unexpected error is still caught here so the page shows
  /// "unavailable" instead of a red screen.
  Future<CarePlanSnapshot> _load() async {
    try {
      final loader = widget.loader;
      final snapshot = loader != null
          ? await loader()
          : await CarePlanSnapshot.load(ClinicalService());
      _logger.info(_tag, 'Care plan loaded', {
        'prescriptions': snapshot.prescriptions?.length,
        'profileAvailable': snapshot.profile.available,
        'clearances': snapshot.clearances?.length,
      });
      return snapshot;
    } catch (e, st) {
      _logger.error(_tag, 'Care plan load failed', null, e, st);
      return const CarePlanSnapshot(
        prescriptions: null,
        profile: ClinicalProfileResult.unavailable(),
        clearances: null,
      );
    }
  }

  /// Pull to refresh: reloads the clinic data and the session history.
  /// Never throws (both loads log their own failures).
  Future<void> _refresh() async {
    _logger.info(_tag, 'Refreshing');
    final next = _load();
    setState(() {
      _snapshot = next;
    });
    await Future.wait([
      next,
      if (widget.sessions == null) context.read<AppProvider>().loadHistory(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sessions =
        widget.sessions ?? context.watch<AppProvider>().sessionHistory;
    return Scaffold(
      backgroundColor: palette.background,
      body: HeaderColumn(
        children: [
          _header(context),
          Expanded(
            child: FutureBuilder<CarePlanSnapshot>(
              future: _snapshot,
              builder: (context, snap) {
                final data = snap.data;
                if (data == null) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppPalette.teal),
                  );
                }
                final view = CarePlanView.build(
                  snapshot: data,
                  sessions: sessions,
                  now: DateTime.now(),
                );
                return _sections(view);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sections(CarePlanView view) {
    return RefreshIndicator(
      color: AppPalette.teal,
      onRefresh: _refresh,
      child: ListView(
        clipBehavior: Clip.none, // HeaderColumn: scrolls under the corners
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: readablePadding(
          context,
          const EdgeInsets.fromLTRB(16, 20, 16, 24),
        ),
        children: [
          ExerciseCompletionSection(gate: view.gate),
          const SizedBox(height: 14),
          ComplianceSection(summary: view.compliance),
          const SizedBox(height: 14),
          MedicalClearanceSection(status: view.clearance),
          const SizedBox(height: 14),
          PrecautionsSection(result: view.profile),
          const SizedBox(height: 14),
          Text(
            'Your care plan is set by your clinic. Message your therapist '
            'if something looks wrong.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: context.palette.textMuted),
          ),
        ],
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
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white,
                  size: 20,
                ),
                tooltip: 'Back',
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
                  Icons.verified_user_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Care plan & clearance',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
