// lib/widgets/chat_composer_surface.dart
//
// The background of the chat's message box (composer).
//
// Android keeps exactly the flat bar it always had. On iPhone the composer
// becomes a floating rounded bar: Liquid Glass (cupertino_native_better's
// LiquidGlassContainer, a native SwiftUI glass view drawn under the Flutter
// content) on iOS 26+, and a translucent surface on older iOS, where that
// container would draw nothing. The text field inside stays a Flutter
// TextField either way.

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/app_palette.dart';
import '../ios/ios_chrome.dart';

class ChatComposerSurface extends StatelessWidget {
  const ChatComposerSurface({super.key, required this.child});

  /// The composer row (buttons and text field).
  final Widget child;

  static const double _radius = 26;

  /// True only on a real iOS 26+ device. Checked on the real platform (not
  /// just [useIosChrome]) because tests force the iPhone look on a Linux
  /// host, where the version check would ask the wrong OS.
  bool get _nativeGlass =>
      defaultTargetPlatform == TargetPlatform.iOS &&
      PlatformVersion.shouldUseNativeControls;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (!useIosChrome) {
      // Android: unchanged from before the iPhone composer.
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        color: palette.surfaceMuted,
        child: SafeArea(top: false, child: child),
      );
    }

    final glass = _nativeGlass;
    final bar = Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        // Over real glass only a light wash, so the glass shows; without
        // it (older iOS) a mostly opaque surface, so text stays readable
        // over the gradient.
        color: glass
            ? palette.surface.withValues(alpha: 0.2)
            : palette.surfaceMuted.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: child,
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: glass
            ? LiquidGlassContainer(
                config: const LiquidGlassConfig(
                  effect: CNGlassEffect.regular,
                  shape: CNGlassEffectShape.rect,
                  cornerRadius: _radius,
                ),
                child: bar,
              )
            : bar,
      ),
    );
  }
}
