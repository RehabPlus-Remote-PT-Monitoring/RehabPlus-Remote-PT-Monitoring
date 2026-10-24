// lib/widgets/exercise_card_body.dart
//
// What one exercise card on the Exercise tab looks like, without any
// navigation or animation (those stay in ExercisePage's AnimatedExerciseCard),
// so the layout can be tested without Firebase or the camera.
//
//   ┌──────────────────────────────────────────────┐
//   │ [icon]  Knee Extension                   (▶) │
//   │         Easy                                 │
//   │ ⏱ 12 min   ↻ 1 Set | 10 Reps                 │
//   │ 🎥 Side-on to the camera                     │
//   │ ▓▓▓▓▓▓▓░░░░░░  (plan exercises only)         │
//   └──────────────────────────────────────────────┘
//
// The details line used to sit in a narrow column between the title and the
// play button, so with the wider Inter font "1 Set | 10 Reps" ended in "...".
// The details now span the whole card width and wrap onto another line
// instead of truncating, at any width and text size.

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../models/exercise_model.dart';

class ExerciseCardBody extends StatelessWidget {
  const ExerciseCardBody({super.key, required this.config, this.progress});

  final ExerciseConfig config;

  /// 0.0–1.0 progress toward the prescription's weekly goal. Null for
  /// catalog exercises that aren't in the patient's plan (no bar shown).
  final double? progress;

  /// Icon + accent colour per exercise category. Hold exercises always get
  /// the timer icon regardless of category, since "how long" matters more
  /// than "which body part" at a glance.
  static ({Color accent, IconData icon}) visualsFor(ExerciseConfig config) {
    if (config.isHold) {
      return (accent: const Color(0xFFE91E63), icon: CupertinoIcons.timer_fill);
    }
    switch (config.category) {
      case 'MCL Recovery':
        return (
          accent: const Color(0xFF00ACC1),
          icon: CupertinoIcons.arrow_up_arrow_down,
        );
      case 'Lower Body':
        return (
          accent: const Color(0xFFFF7043),
          icon: Icons.directions_walk_rounded,
        );
      case 'Core & Hips':
        return (
          accent: const Color(0xFF7E57C2),
          icon: Icons.self_improvement_rounded,
        );
      case 'Arm Rehabilitation':
        return (
          accent: const Color(0xFF42A5F5),
          icon: Icons.fitness_center_rounded,
        );
      default:
        return (
          accent: AppPalette.teal,
          icon: Icons.accessibility_new_rounded,
        );
    }
  }

  /// Pastel chip backgrounds in light mode; in dark mode a translucent tint
  /// of the label colour, since the pastels glare on a dark card. The chip
  /// always shows the word too, so the colour is never the only signal.
  static ({Color bg, Color fg}) difficultyColors(
    BuildContext context,
    ExerciseDifficulty difficulty,
  ) {
    final light = switch (difficulty) {
      ExerciseDifficulty.easy => (
        bg: const Color(0xFFE2F3D3),
        fg: const Color(0xFF558B2F),
      ),
      ExerciseDifficulty.moderate => (
        bg: const Color(0xFFFFF3D6),
        // Darker amber than before: the old yellow text was hard to read
        // on its pale chip.
        fg: const Color(0xFFB7791F),
      ),
      ExerciseDifficulty.hard => (
        bg: const Color(0xFFFFE0E0),
        fg: const Color(0xFFD32F2F),
      ),
    };
    if (!context.isDarkMode) return light;
    return (bg: light.fg.withValues(alpha: 0.2), fg: light.fg);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final visuals = visualsFor(config);
    final difficulty = difficultyColors(context, config.difficulty);
    final progress = this.progress;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: category icon, name + difficulty, play button.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: visuals.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(visuals.icon, color: visuals.accent, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.title,
                      style: textTheme.titleMedium?.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _DifficultyChip(
                      label: config.difficulty.label,
                      colors: difficulty,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // The whole card starts the exercise; this is the visual cue
              // that it does. Excluded from semantics because the card
              // itself is announced as the "Start ..." button.
              const ExcludeSemantics(child: _PlayCircle()),
            ],
          ),
          const SizedBox(height: 12),
          // Details across the full card width. A Wrap moves an item that
          // doesn't fit to the next line instead of cutting it with "...".
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _MetaItem(
                icon: CupertinoIcons.clock,
                text: '${config.estimatedMinutes} min',
              ),
              _MetaItem(icon: CupertinoIcons.repeat, text: config.repsText),
              // Where to stand: the angles are only measurable from the
              // right camera view.
              _MetaItem(
                icon: CupertinoIcons.videocam,
                text: config.cameraView.label,
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 14),
            Semantics(
              label: 'Weekly goal',
              value: '${(progress * 100).round()} percent',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: visuals.accent.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(visuals.accent),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  const _DifficultyChip({required this.label, required this.colors});

  final String label;
  final ({Color bg, Color fg}) colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The round teal play button. 44 pt, the iOS minimum touch size.
class _PlayCircle extends StatelessWidget {
  const _PlayCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: AppPalette.teal,
        shape: BoxShape.circle,
      ),
      // Nudged right: a play triangle looks off-centre when centred exactly.
      padding: const EdgeInsets.only(left: 3),
      child: const Icon(CupertinoIcons.play_fill, color: Colors.white, size: 20),
    );
  }
}

/// One "icon + text" detail. The text may wrap inside its own item if it is
/// wider than the whole card on its own (very large text sizes).
class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: palette.textMuted),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
        ),
      ],
    );
  }
}
