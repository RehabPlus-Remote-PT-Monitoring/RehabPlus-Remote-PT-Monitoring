// lib/widgets/exercise_controls.dart
//
// On-screen Pause / End buttons for the live exercise screen, and the
// "Paused" overlay with Resume. Before these, the only way out was the
// Back button, which patients standing 2 m away didn't find, and there was
// no way to stop counting for a moment (to fix a strap, sit down, answer
// the door) without ending the session.
//
// The widgets only report taps; the screen owns what pausing means (see
// _pauseByUser / _resumeByUser in lib/screens/pose_detector_screen.dart).

import 'package:flutter/material.dart';

/// Pause and End, side by side, for the bottom card.
class ExerciseSessionControls extends StatelessWidget {
  const ExerciseSessionControls({
    super.key,
    required this.canPause,
    required this.onPause,
    required this.onEnd,
  });

  /// False during the start countdown (nothing is being counted yet, and
  /// the countdown has its own timer), so the Pause button is disabled.
  final bool canPause;
  final VoidCallback onPause;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canPause ? onPause : null,
            icon: const Icon(Icons.pause_rounded, size: 20),
            label: const Text('Pause', overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white38,
              side: const BorderSide(color: Colors.white38),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onEnd,
            icon: const Icon(Icons.stop_rounded, size: 20),
            label: const Text('End', overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent.shade100,
              side: BorderSide(color: Colors.redAccent.shade100),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-screen dimmed overlay shown while the patient has paused.
class ExercisePausedOverlay extends StatelessWidget {
  const ExercisePausedOverlay({
    super.key,
    required this.onResume,
    required this.onEnd,
  });

  final VoidCallback onResume;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.7),
      child: SafeArea(
        child: Center(
          // Scrolls instead of overflowing in phone landscape at large text.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.pause_circle_filled_rounded,
                  color: Colors.white,
                  size: 64,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Paused',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Nothing is being counted. Resume when you are ready.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onResume,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Resume'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onEnd,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent.shade100,
                  ),
                  child: const Text('End session'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
