// lib/widgets/care_plan_sections.dart
//
// The four sections of Profile > "Care plan & clearance". Each takes plain
// data (no Firebase), so they are widget-tested on their own
// (test/care_plan_test.dart).
//
// Terminology (design doc §1), kept apart on purpose:
//   - Exercise completion: finished sessions vs the clinician's target.
//   - Compliance: how well and how regularly; NOT a medical result.
//   - Medical clearance: only a physician-signed record. The page never
//     says "cleared" unless such a record exists.

import 'package:flutter/material.dart';
// `show`: the full intl library also exports a TextDirection that clashes
// with Flutter's.
import 'package:intl/intl.dart' show DateFormat;

import '../core/app_palette.dart';
import '../models/clearance_record.dart';
import '../models/clinical_profile.dart';
import '../services/care_gate.dart';
import '../services/care_plan_data.dart';
import '../services/clinical_service.dart';

final DateFormat _dateFormat = DateFormat('d MMM y');

String _date(DateTime date) => _dateFormat.format(date);

/// A white (or dark-surface) card with a heading and a one-line explanation.
class CarePlanSectionCard extends StatelessWidget {
  const CarePlanSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.explanation,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String explanation;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppPalette.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: AppPalette.teal),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            explanation,
            style: TextStyle(
              fontSize: 12,
              color: palette.textMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

/// A short note (icon + text) inside a section, e.g. an empty state.
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color ?? palette.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: palette.textSecondary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// "Label ..... value" row whose value wraps under itself instead of
/// overflowing (see the skill note on Spacer rows).
class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: palette.textMuted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              softWrap: true,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A label with a paragraph under it (findings, precautions).
class _Paragraph extends StatelessWidget {
  const _Paragraph({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: palette.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Exercise completion ─────────────────────────────────────────────────

class ExerciseCompletionSection extends StatelessWidget {
  const ExerciseCompletionSection({super.key, required this.gate});

  /// Null when the prescriptions couldn't be read.
  final CareGateResult? gate;

  static const Color _metGreen = Color(0xFF2E7D32);
  static const Color _blockedOrange = Color(0xFFD84315);

  @override
  Widget build(BuildContext context) {
    return CarePlanSectionCard(
      icon: Icons.checklist_rounded,
      title: 'Exercise completion',
      explanation:
          'Finished sessions for each exercise your clinician prescribed. '
          'Sessions ended early do not count.',
      children: _body(context),
    );
  }

  List<Widget> _body(BuildContext context) {
    final gate = this.gate;
    if (gate == null) {
      return const [
        _Note(
          icon: Icons.cloud_off_rounded,
          text:
              'Not available right now. Check your connection and pull '
              'down to refresh.',
        ),
      ];
    }
    if (gate.state == CareGateState.noProgram) {
      return const [
        _Note(
          icon: Icons.event_note_rounded,
          text: 'No exercise program assigned yet.',
        ),
      ];
    }

    final missing = gate.missing;
    return [
      for (final requirement in gate.requirements)
        _RequirementRow(requirement: requirement),
      const SizedBox(height: 4),
      if (missing.isEmpty)
        const _Note(
          icon: Icons.check_circle_rounded,
          color: _metGreen,
          text: 'Every prescribed exercise is complete.',
        )
      else ...[
        Text(
          'Still missing',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        for (final requirement in missing)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _Note(
              icon: requirement.restricted
                  ? Icons.lock_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: requirement.restricted ? _blockedOrange : null,
              text: '${requirement.exerciseName}: ${requirement.statusText}',
            ),
          ),
      ],
    ];
  }
}

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.requirement});

  final GateRequirement requirement;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = requirement.restricted
        ? ExerciseCompletionSection._blockedOrange
        : requirement.isMet
        ? ExerciseCompletionSection._metGreen
        : AppPalette.teal;
    final target = requirement.required;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  requirement.exerciseName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                target == null
                    ? '${requirement.finished} done'
                    : '${requirement.finished} / $target',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: requirement.fraction ?? 0,
              minHeight: 7,
              backgroundColor: palette.surfaceMuted,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          if (requirement.restricted || !requirement.hasTarget) ...[
            const SizedBox(height: 4),
            Text(
              requirement.restricted
                  ? 'Restricted by your clinician'
                  : 'No completion target set',
              style: TextStyle(fontSize: 12, color: palette.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Compliance ──────────────────────────────────────────────────────────

class ComplianceSection extends StatelessWidget {
  const ComplianceSection({super.key, required this.summary});

  final ComplianceSummary summary;

  @override
  Widget build(BuildContext context) {
    final accuracy = summary.formAccuracy;
    final adherence = summary.weekAdherence;
    return CarePlanSectionCard(
      icon: Icons.insights_rounded,
      title: 'Compliance',
      explanation:
          'How well and how regularly you did your exercises. This is not '
          'a medical result.',
      children: [
        _ValueRow(
          label: 'Form accuracy',
          value: accuracy == null
              ? 'No finished sessions yet'
              : '${accuracy.round()}% '
                    '(${summary.finishedSessions} finished '
                    '${summary.finishedSessions == 1 ? 'session' : 'sessions'})',
        ),
        _ValueRow(
          label: 'This week',
          value: adherence == null
              ? 'Nothing planned yet'
              : '${(adherence * 100).round()}% of planned sessions',
        ),
      ],
    );
  }
}

// ── Medical clearance ───────────────────────────────────────────────────

class MedicalClearanceSection extends StatelessWidget {
  const MedicalClearanceSection({super.key, required this.status});

  final ClearanceStatus status;

  static const Color _clearedGreen = Color(0xFF2E7D32);
  static const Color _notClearedOrange = Color(0xFFD84315);

  @override
  Widget build(BuildContext context) {
    return CarePlanSectionCard(
      icon: Icons.verified_user_outlined,
      title: 'Medical clearance',
      explanation:
          'Only your physician can clear you, after a final assessment. '
          'Finishing your exercises does not clear you by itself.',
      children: _body(context),
    );
  }

  List<Widget> _body(BuildContext context) {
    final record = status.record;
    switch (status.kind) {
      case ClearanceStatusKind.cleared:
        return [
          _StatusLine(
            icon: Icons.verified_rounded,
            color: _clearedGreen,
            text: 'Cleared by your physician',
          ),
          const SizedBox(height: 10),
          ..._recordDetails(record!),
          if (status.programChangedSinceClearance)
            const _Note(
              icon: Icons.info_outline_rounded,
              text: 'Your program was updated after this clearance.',
            ),
        ];
      case ClearanceStatusKind.notCleared:
        return [
          _StatusLine(
            icon: Icons.pending_actions_rounded,
            color: _notClearedOrange,
            text: 'Not cleared yet: continue your program',
          ),
          const SizedBox(height: 10),
          ..._recordDetails(record!),
        ];
      case ClearanceStatusKind.readyForReview:
        return const [
          _StatusLine(
            icon: Icons.assignment_ind_outlined,
            color: AppPalette.teal,
            text: 'Ready for physician assessment',
          ),
          SizedBox(height: 8),
          _Note(
            icon: Icons.info_outline_rounded,
            text:
                'You finished every prescribed exercise. Your physician '
                'will do a final assessment before deciding.',
          ),
        ];
      case ClearanceStatusKind.notEligible:
        return [
          _StatusLine(
            icon: Icons.hourglass_top_rounded,
            color: context.palette.textMuted,
            text: 'Not ready for assessment yet',
          ),
          const SizedBox(height: 8),
          if (status.missing.isEmpty)
            const _Note(
              icon: Icons.event_note_rounded,
              text: 'No exercise program assigned yet.',
            )
          else ...[
            const _Note(
              icon: Icons.info_outline_rounded,
              text: 'Finish these first:',
            ),
            const SizedBox(height: 4),
            for (final requirement in status.missing)
              Padding(
                padding: const EdgeInsets.only(left: 26, bottom: 3),
                child: Text(
                  '• ${requirement.exerciseName}: ${requirement.statusText}',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.palette.textSecondary,
                  ),
                ),
              ),
          ],
        ];
      case ClearanceStatusKind.unavailable:
        return [
          _StatusLine(
            icon: Icons.cloud_off_rounded,
            color: context.palette.textMuted,
            text: 'Not available yet',
          ),
          const SizedBox(height: 8),
          const _Note(
            icon: Icons.info_outline_rounded,
            text:
                'Your clearance status can\'t be shown right now. This '
                'does not mean you are cleared. Ask your clinician if you '
                'need it.',
          ),
        ];
    }
  }

  List<Widget> _recordDetails(ClearanceRecord record) {
    final assessed = record.assessedAt;
    return [
      if (record.physicianName.isNotEmpty)
        _ValueRow(label: 'Physician', value: record.physicianName),
      if (record.physicianLicense.isNotEmpty)
        _ValueRow(label: 'PRC license no.', value: record.physicianLicense),
      _ValueRow(
        label: 'Assessment date',
        value: _date(assessed ?? record.signedAt),
      ),
      if (record.findings.isNotEmpty)
        _Paragraph(label: 'Findings', text: record.findings),
      if (record.recommendations.isNotEmpty)
        _Paragraph(label: 'Recommendations', text: record.recommendations),
    ];
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Precautions from your clinician ─────────────────────────────────────

class PrecautionsSection extends StatelessWidget {
  const PrecautionsSection({super.key, required this.result});

  final ClinicalProfileResult result;

  static const String dietaryLabel =
      'Dietary context (for information only; it does not change your '
      'exercises)';

  @override
  Widget build(BuildContext context) {
    return CarePlanSectionCard(
      icon: Icons.health_and_safety_outlined,
      title: 'Precautions from your clinician',
      explanation:
          'What your clinician wants you to keep in mind while you '
          'exercise.',
      children: _body(context),
    );
  }

  List<Widget> _body(BuildContext context) {
    if (!result.available) {
      return const [
        _Note(
          icon: Icons.cloud_off_rounded,
          text: 'Not available yet. Pull down to try again later.',
        ),
      ];
    }
    final profile = result.profile;
    if (profile == null || profile.isEmpty) {
      return const [
        _Note(
          icon: Icons.check_circle_outline_rounded,
          text: 'Your clinician has not added any precautions.',
        ),
      ];
    }

    final palette = context.palette;
    final precautions = profile.precautions?.trim() ?? '';
    final toleranceNote = profile.toleranceNote?.trim() ?? '';
    final dietaryNotes = profile.dietaryNotes?.trim() ?? '';
    final restricted = [
      for (final type in profile.restrictedExercises)
        exerciseNameFor(type.name),
    ]..sort();
    final hasDiet =
        dietaryNotes.isNotEmpty || profile.nutritionFlags.isNotEmpty;

    return [
      if (precautions.isNotEmpty)
        _Paragraph(label: 'Precautions', text: precautions),
      if (profile.lowTolerance)
        _Paragraph(
          label: 'Low exercise tolerance',
          text: toleranceNote.isEmpty
              ? 'Take it slowly and stop if pain increases.'
              : toleranceNote,
        )
      else if (toleranceNote.isNotEmpty)
        _Paragraph(label: 'Tolerance', text: toleranceNote),
      if (restricted.isNotEmpty) ...[
        _Paragraph(label: 'Paused exercises', text: restricted.join(', ')),
      ],
      if (hasDiet) ...[
        Text(
          dietaryLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        if (profile.nutritionFlags.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final flag in profile.nutritionFlags) _FlagChip(flag: flag),
            ],
          ),
        if (dietaryNotes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            dietaryNotes,
            style: TextStyle(
              fontSize: 13,
              color: palette.textPrimary,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 10),
      ],
      if (_validatedLine(profile) case final line?)
        Text(line, style: TextStyle(fontSize: 12, color: palette.textMuted)),
      if (profile.nextReassessmentAt case final next?) ...[
        const SizedBox(height: 3),
        Text(
          'Next reassessment: ${_date(next)}',
          style: TextStyle(fontSize: 12, color: palette.textMuted),
        ),
      ],
    ];
  }

  /// "Validated by Dr. Cruz on 3 Nov 2026", with whichever part is known.
  static String? _validatedLine(ClinicalProfile profile) {
    final name = profile.validatedByName?.trim() ?? '';
    final at = profile.validatedAt;
    if (name.isEmpty && at == null) return null;
    if (at == null) return 'Validated by $name';
    if (name.isEmpty) return 'Validated on ${_date(at)}';
    return 'Validated by $name on ${_date(at)}';
  }
}

class _FlagChip extends StatelessWidget {
  const _FlagChip({required this.flag});

  final NutritionFlag flag;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        flag.label,
        style: TextStyle(fontSize: 12, color: palette.textSecondary),
      ),
    );
  }
}
