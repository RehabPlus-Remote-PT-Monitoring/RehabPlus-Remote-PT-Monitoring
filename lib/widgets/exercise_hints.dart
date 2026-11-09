// lib/widgets/exercise_hints.dart
//
// Small text overlays for the live exercise screen:
//  - ExerciseHintBanner: one-line advice in the top banner column (used for
//    "step back / move closer"), same dark translucent pill as the setup tip.
//  - ExerciseTempoCue: the "Lift... hold... lower" cue on the bottom card,
//    so patients slow down (reps under the minimum time are not counted).

import 'package:flutter/material.dart';

class ExerciseHintBanner extends StatelessWidget {
  const ExerciseHintBanner({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.tealAccent, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class ExerciseTempoCue extends StatelessWidget {
  const ExerciseTempoCue({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    // Changes a few times per rep; isolate its repaint from the card.
    return RepaintBoundary(
      child: Semantics(
        liveRegion: true,
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.tealAccent,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
