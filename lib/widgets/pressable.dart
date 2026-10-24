// lib/widgets/pressable.dart
//
// Press feedback for custom tappable cards and tiles (apple-design rule 1:
// respond on touch-DOWN, not on release). The child dims and shrinks a
// little the instant a finger lands, follows the finger off and back on,
// and springs back on release or cancel. Replaces bare GestureDetectors,
// which gave no feedback at all.
//
//   Pressable(onTap: _open, child: _card())
//
// Accessibility: the child is exposed as a button with [semanticLabel] (or
// its own text). With the system's "remove animations" setting on, the
// scale is skipped and only the dimming remains.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.pressedScale = 0.97,
    this.haptic = false,
    this.semanticLabel,
  });

  final Widget child;

  /// Null disables the feedback and the tap (e.g. while saving).
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Scale while pressed. 0.97 for cards; ~0.92 for small icon buttons.
  final double pressedScale;

  /// A light tap of haptics on release. Only for meaningful actions
  /// (starting an exercise, sending), never for plain navigation.
  final bool haptic;

  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final pressed = enabled && _pressed;

    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.lightImpact();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        child: AnimatedOpacity(
          // Instant on press, gentle on release, like UIKit highlights.
          duration: Duration(milliseconds: pressed ? 0 : 180),
          opacity: pressed ? 0.7 : 1,
          child: AnimatedScale(
            duration: Duration(milliseconds: pressed ? 90 : 220),
            curve: pressed ? Curves.easeOut : Curves.easeOutBack,
            scale: pressed && !reduceMotion ? widget.pressedScale : 1,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
