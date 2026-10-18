import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Animated startup screen, then a crossfade into [next] (the login page or,
/// when already signed in, the dashboard). [next] is a future: the app's
/// startup work (Firebase, the patient's data) runs behind the splash, which
/// keeps the shield breathing at 2.0 s until it's done.
///
/// Timeline (one 3.4 s controller, see the intervals below):
///   0.00–0.75 s  black screen; a large blue shield, turned 45° so its plus
///                reads as an ×, spins upright and shrinks to logo size
///   0.75–2.00 s  the small shield breathes gently (longer if the app is
///                still starting)
///   2.00–2.50 s  the background fades from black to the login teal and the
///                soft circles appear
///   2.05–2.70 s  the shield slides beside the "Rehab" wordmark and
///                "PHYSIOTHERAPY" fades in underneath
///   3.40 s       crossfade into [next]
///
/// The Android launch screen is plain black (res/values-v31) so the hand-off
/// from the system splash into this one is seamless.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.next, this.onFinished});

  final Future<Widget> next;

  /// Called once [next] is on screen (e.g. to open a launch notification).
  final VoidCallback? onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const int _totalMs = 3400;
  static const Color _shieldBlue = Color(0xFF5B7FEA);

  // Shield sizes: the intro starts this many times larger, settles at
  // [_logoSize] and docks next to the wordmark at [_dockedSize].
  static const double _introScale = 2.6;
  static const double _logoSize = 56;
  static const double _dockedSize = 38;
  static const double _wordGap = 8;

  static const TextStyle _wordStyle = TextStyle(
    color: Colors.white,
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.5,
    height: 1.1,
  );
  static const TextStyle _taglineStyle = TextStyle(
    color: Colors.white,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.6,
  );

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _totalMs),
  );

  /// Loops while the shield waits, independent of how long startup takes.
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );

  /// Where the intro pauses until startup is done.
  static const double _holdAt = 2000 / _totalMs;
  Widget? _nextScreen;

  late final Animation<double> _spin = _interval(0, 750, Curves.easeInOutCubic);
  late final Animation<double> _reveal = _interval(
    2000,
    2500,
    Curves.easeInOut,
  );
  late final Animation<double> _dock = _interval(
    2050,
    2650,
    Curves.easeInOutCubic,
  );
  late final Animation<double> _text = _interval(
    2150,
    2700,
    Curves.easeOutCubic,
  );

  bool _left = false;

  Animation<double> _interval(int startMs, int endMs, Curve curve) =>
      CurvedAnimation(
        parent: _ctrl,
        curve: Interval(startMs / _totalMs, endMs / _totalMs, curve: curve),
      );

  @override
  void initState() {
    super.initState();
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _goNext();
    });
    _run();
  }

  Future<void> _run() async {
    _breath.repeat();
    await Future.wait([
      _ctrl.animateTo(_holdAt).orCancel.catchError((_) {}),
      widget.next.then((w) => _nextScreen = w),
    ]);
    if (!mounted) return;
    _breath.stop();
    _ctrl.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the system "remove animations" setting: skip straight on.
    if (MediaQuery.of(context).disableAnimations && !_ctrl.isCompleted) {
      _ctrl.duration = Duration.zero;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _breath.dispose();
    super.dispose();
  }

  void _goNext() {
    final next = _nextScreen;
    if (_left || !mounted || next == null) return;
    _left = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, _, _) => next,
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeInOut),
          child: child,
        ),
      ),
    );
    // The new route is on screen after the first frame of its transition.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onFinished?.call(),
    );
  }

  Size _measure(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    return painter.size;
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);

    // Where the docked shield sits, relative to the screen centre: the
    // wordmark row ("Rehab" + gap + shield) and the tagline below it are
    // centred as one block.
    final word = _measure('Rehab', _wordStyle, scaler);
    final tagline = _measure('PHYSIOTHERAPY', _taglineStyle, scaler);
    const taglineGap = 6.0;
    final rowWidth = word.width + _wordGap + _dockedSize;
    final rowHeight = math.max(word.height, _dockedSize);
    final blockHeight = rowHeight + taglineGap + tagline.height;
    final dockedOffset = Offset(
      -rowWidth / 2 + word.width + _wordGap + _dockedSize / 2,
      -blockHeight / 2 + rowHeight / 2,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: Listenable.merge([_ctrl, _breath]),
        builder: (context, _) {
          final reveal = _reveal.value;
          final spin = _spin.value;
          final dock = _dock.value;
          final text = _text.value;

          // Gentle "breathing" once the intro spin is done, until it docks.
          final breathe =
              1 +
              0.06 * math.sin(_breath.value * math.pi * 2) * spin * (1 - dock);

          final introScale = lerpDouble(_introScale, 1, spin)!;
          final size = lerpDouble(_logoSize, _dockedSize, dock)!;
          final angle = lerpDouble(-math.pi / 4, 0, spin)!;
          final offset = Offset.lerp(Offset.zero, dockedOffset, dock)!;

          return Stack(
            fit: StackFit.expand,
            children: [
              // Black fades to the same teal gradient as the login page.
              Opacity(
                opacity: reveal,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF0D6E71),
                        Color(0xFF1E8E92),
                        Color(0xFF2FB8BD),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              ..._circles(reveal),

              // Wordmark, with an empty slot where the shield docks.
              Center(
                child: Opacity(
                  opacity: text,
                  child: Transform.translate(
                    offset: Offset(-14 * (1 - text), 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: rowHeight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Rehab',
                                style: _wordStyle,
                                maxLines: 1,
                              ),
                              const SizedBox(width: _wordGap + _dockedSize),
                            ],
                          ),
                        ),
                        const SizedBox(height: taglineGap),
                        const Text(
                          'PHYSIOTHERAPY',
                          style: _taglineStyle,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // The shield: spins in, breathes, then slides into its slot.
              Center(
                child: Transform.translate(
                  offset: offset,
                  child: Transform.rotate(
                    angle: angle,
                    child: Transform.scale(
                      scale: introScale * breathe,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _shieldBlue.withValues(
                                alpha: 0.35 * (1 - reveal),
                              ),
                              blurRadius: 28,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: PhosphorIcon(
                          PhosphorIcons.shieldPlus(PhosphorIconsStyle.fill),
                          size: size,
                          color: _shieldBlue,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The login page's decorative circles, growing in with the background.
  List<Widget> _circles(double t) {
    Widget circle(double size, double alpha) => Transform.scale(
      scale: lerpDouble(0.6, 1, t)!,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: alpha * t),
          shape: BoxShape.circle,
        ),
      ),
    );

    return [
      Positioned(top: -80, right: -80, child: circle(260, 0.07)),
      Positioned(top: 60, right: -30, child: circle(120, 0.05)),
      Positioned(bottom: -100, left: -60, child: circle(300, 0.06)),
    ];
  }
}
