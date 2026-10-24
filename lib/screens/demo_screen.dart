import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

import '../widgets/pressable.dart';
import '../widgets/ios_page.dart';
import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../core/responsive.dart';

const String _tag = 'Demo';

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> with TickerProviderStateMixin {
  static const Color primaryTeal = Color(0xFF23A8AA);

  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  late final AnimationController _headerCtrl;
  late final AnimationController _contentCtrl;
  late final Animation<double> _headerFade;
  late final Animation<double> _contentFade;
  late final Animation<Offset> _contentSlide;

  // Active exercise demo state
  int _activeStep = 0;

  final List<_DemoFeature> _features = [
    _DemoFeature(
      icon: CupertinoIcons.graph_square,
      color: Color(0xFF23A8AA),
      title: 'Track Progress',
      subtitle:
          'Monitor your weekly recovery with visual charts and day-by-day check-ins.',
      preview: _PreviewType.progress,
    ),
    _DemoFeature(
      icon: CupertinoIcons.flame,
      color: Color(0xFF4A90D9),
      title: 'Exercise Plans',
      subtitle:
          'Follow guided rehab exercises assigned by your therapist with step-by-step instructions.',
      preview: _PreviewType.exercise,
    ),
    _DemoFeature(
      icon: CupertinoIcons.chat_bubble,
      color: Color(0xFF7C4DFF),
      title: 'Message Therapist',
      subtitle:
          'Stay connected with your therapist through real-time messaging and quick updates.',
      preview: _PreviewType.messages,
    ),
    _DemoFeature(
      icon: CupertinoIcons.bell,
      color: Color(0xFFFF6B35),
      title: 'Smart Reminders',
      subtitle:
          'Never miss a session with personalized notifications and progress alerts.',
      preview: _PreviewType.notifications,
    ),
  ];

  final List<_ExerciseStep> _steps = [
    _ExerciseStep(
      'Starting Position',
      'Stand straight, feet shoulder-width apart. Keep your back neutral.',
      5,
    ),
    _ExerciseStep(
      'Bend Knees',
      'Slowly lower your body by bending both knees to 90°. Hold for 2 seconds.',
      8,
    ),
    _ExerciseStep(
      'Extend Leg',
      'Straighten your right leg fully. Feel the quad engage. Hold 3 seconds.',
      6,
    ),
    _ExerciseStep(
      'Return',
      'Slowly return to starting position. Breathe out as you come up.',
      5,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _contentCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _contentFade = CurvedAnimation(parent: _contentCtrl, curve: Curves.easeOut);
    _contentSlide =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
          CurvedAnimation(parent: _contentCtrl, curve: Curves.easeOutCubic),
        );
    _headerCtrl.forward();
    // Skip if the screen was closed during the delay (a disposed
    // controller throws when started).
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _contentCtrl.forward();
    });

    DiagnosticLogger.I.info(_tag, 'Screen opened');
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _contentCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_activeStep < _steps.length - 1) {
      setState(() => _activeStep++);
    } else {
      setState(() {
        _activeStep = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // iOS page with a large title. The cards still ease in (the content
    // animation); on tablets they sit in two columns.
    return IosPage(
      title: 'App Demo',
      previousPageTitle: 'Home',
      maxWidth: adaptiveMaxWidth(context),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: FadeTransition(
            opacity: _headerFade,
            child: Text(
              'Explore what RehabPlus can do',
              style: TextStyle(fontSize: 15, color: context.palette.textMuted),
            ),
          ),
        ),
        SlideTransition(
          position: _contentSlide,
          child: FadeTransition(
            opacity: _contentFade,
            child: AdaptiveColumns(
              left: [
                _buildFeatureCarousel(),
                const SizedBox(height: 24),
                _buildVideoSection(),
                const SizedBox(height: 24),
              ],
              right: [
                _buildExerciseDemo(),
                const SizedBox(height: 24),
                _buildStatsPreview(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureCarousel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              CupertinoIcons.sparkles,
              size: 18,
              color: primaryTeal,
            ),
            const SizedBox(width: 8),
            Text(
              'Key Features',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: context.palette.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 220,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: _features.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (_, i) => _FeatureCard(feature: _features[i]),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _features.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _currentPage == i ? 20 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: _currentPage == i
                    ? primaryTeal
                    : context.palette.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── VIDEO SECTION ──────────────────────────────────────────────────────────
  Widget _buildVideoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              CupertinoIcons.videocam,
              size: 18,
              color: primaryTeal,
            ),
            const SizedBox(width: 8),
            Text(
              'Exercise Videos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: context.palette.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _VideoCard(
          title: 'Knee Extension',
          duration: '3:24',
          level: 'Beginner',
          color: Color(0xFF23A8AA),
          videoUrl: 'https://www.w3schools.com/html/mov_bbb.mp4',
        ),
        const SizedBox(height: 12),
        _VideoCard(
          title: 'Shoulder Rotation',
          duration: '2:15',
          level: 'Intermediate',
          color: Color(0xFF4A90D9),
          videoUrl: 'https://www.w3schools.com/html/movie.mp4',
        ),
      ],
    );
  }

  // ── EXERCISE DEMO ─────────────────────────────────────────────────────────────
  Widget _buildExerciseDemo() {
    final palette = context.palette;
    final step = _steps[_activeStep];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                CupertinoIcons.flame,
                size: 18,
                color: primaryTeal,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Exercise Demo',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90D9).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Knee Extension',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF4A90D9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Step indicator
          Row(
            children: List.generate(
              _steps.length,
              (i) => Expanded(
                child: Pressable(
                  onTap: () => setState(() => _activeStep = i),
                  semanticLabel: 'Step ${i + 1}',
                  pressedScale: 1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 5,
                    decoration: BoxDecoration(
                      color: i <= _activeStep
                          ? primaryTeal
                          : palette.surfaceMuted,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Step ${_activeStep + 1} of ${_steps.length}',
            style: TextStyle(fontSize: 11, color: palette.textMuted),
          ),
          const SizedBox(height: 16),

          // Step content
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.1, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: Container(
              key: ValueKey(_activeStep),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.isDarkMode
                    ? primaryTeal.withValues(alpha: 0.15)
                    : const Color(0xFFE0F5F5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: primaryTeal,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        '${_activeStep + 1}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          step.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              CupertinoIcons.timer,
                              size: 13,
                              color: primaryTeal,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${step.seconds}s hold',
                              style: const TextStyle(
                                fontSize: 11,
                                color: primaryTeal,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _activeStep > 0
                      ? () => setState(() => _activeStep--)
                      : null,
                  icon: const Icon(CupertinoIcons.chevron_left, size: 14),
                  label: const Text('Prev'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryTeal,
                    side: const BorderSide(color: primaryTeal),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _nextStep,
                  icon: Icon(
                    _activeStep < _steps.length - 1
                        ? CupertinoIcons.chevron_right
                        : CupertinoIcons.arrow_clockwise,
                    size: 14,
                  ),
                  label: Text(
                    _activeStep < _steps.length - 1 ? 'Next Step' : 'Restart',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryTeal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── STATS PREVIEW ─────────────────────────────────────────────────────────────
  Widget _buildStatsPreview() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.midTeal,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                CupertinoIcons.chart_bar,
                size: 18,
                color: Colors.white,
              ),
              SizedBox(width: 8),
              Text(
                'Sample Progress',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'This is how your recovery data will look',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _statPill('Sessions', '12', CupertinoIcons.heart),
              const SizedBox(width: 10),
              _statPill('Streak', '5 days', CupertinoIcons.flame_fill),
              const SizedBox(width: 10),
              _statPill('Score', '87%', CupertinoIcons.rosette),
            ],
          ),
          const SizedBox(height: 20),
          // Fake bar chart
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _bar('M', 0.6),
              _bar('T', 0.85),
              _bar('W', 0.4),
              _bar('T', 0.9),
              _bar('F', 0.7),
              _bar('S', 0.5),
              _bar('S', 0.75),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Weekly Activity',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statPill(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(String day, double height) {
    return Column(
      children: [
        Container(
          width: 28,
          height: 80 * height,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25 + height * 0.4),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          day,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

// ── FEATURE CARD ──────────────────────────────────────────────────────────────
class _FeatureCard extends StatelessWidget {
  final _DemoFeature feature;
  const _FeatureCard({required this.feature});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: feature.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(feature.icon, size: 28, color: feature.color),
          ),
          const SizedBox(height: 16),
          Text(
            feature.title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            feature.subtitle,
            style: TextStyle(
              fontSize: 13,
              color: palette.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── DATA MODELS ───────────────────────────────────────────────────────────────
enum _PreviewType { progress, exercise, messages, notifications }

class _DemoFeature {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final _PreviewType preview;
  const _DemoFeature({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.preview,
  });
}

class _ExerciseStep {
  final String title, description;
  final int seconds;
  const _ExerciseStep(this.title, this.description, this.seconds);
}

// ── VIDEO CARD ────────────────────────────────────────────────────────────────
class _VideoCard extends StatefulWidget {
  final String title, duration, level, videoUrl;
  final Color color;
  const _VideoCard({
    required this.title,
    required this.duration,
    required this.level,
    required this.color,
    required this.videoUrl,
  });

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  static const Color primaryTeal = Color(0xFF23A8AA);
  VideoPlayerController? _vpCtrl;
  ChewieController? _chewieCtrl;
  bool _loaded = false;
  bool _expanded = false;

  /// True while the video is connecting: further taps are ignored, so two
  /// players can't be created (the first one would leak).
  bool _initializing = false;

  /// The last load failed (no internet, bad URL): shown instead of an
  /// endless spinner.
  bool _failed = false;

  final DiagnosticLogger _logger = DiagnosticLogger.I;

  Color get _levelColor => switch (widget.level) {
    'Beginner' => const Color(0xFF4CAF50),
    'Intermediate' => const Color(0xFFFF9800),
    _ => const Color(0xFFE53935),
  };

  /// Creates and connects the player. Returns false (and cleans up) if the
  /// video couldn't be loaded.
  Future<bool> _initVideo() async {
    if (_loaded) return true;
    final uri = Uri.parse(widget.videoUrl);
    // Only ever stream over HTTPS.
    if (uri.scheme != 'https') {
      _logger.error(_tag, 'Refusing non-HTTPS demo video', {'scheme': uri.scheme});
      return false;
    }
    final stopwatch = Stopwatch()..start();
    final controller = VideoPlayerController.networkUrl(uri);
    try {
      await controller.initialize();
    } catch (e, st) {
      _logger.warn(_tag, 'Demo video failed to load', {
        'title': widget.title,
        'ms': stopwatch.elapsedMilliseconds,
      }, e, st);
      await controller.dispose();
      return false;
    }
    if (!mounted) {
      // Closed while connecting: nothing will ever dispose it otherwise.
      await controller.dispose();
      return false;
    }
    _logger.info(_tag, 'Demo video loaded', {
      'title': widget.title,
      'ms': stopwatch.elapsedMilliseconds,
    });
    _vpCtrl = controller;
    _chewieCtrl = ChewieController(
      videoPlayerController: controller,
      autoPlay: true,
      looping: false,
      aspectRatio: 16 / 9,
      placeholder: Container(color: Colors.black),
      materialProgressColors: ChewieProgressColors(
        playedColor: primaryTeal,
        handleColor: primaryTeal,
        bufferedColor: primaryTeal.withValues(alpha: 0.3),
        backgroundColor: Colors.grey.shade800,
      ),
    );
    setState(() => _loaded = true);
    return true;
  }

  Future<void> _togglePlayer() async {
    if (_initializing) return;
    if (!_expanded) {
      setState(() {
        _initializing = true;
        _failed = false;
        _expanded = true; // show the spinner while it connects
      });
      final ok = await _initVideo();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _failed = !ok;
      });
    } else {
      _logger.info(_tag, 'Demo video closed', {'title': widget.title});
      _chewieCtrl?.dispose();
      _vpCtrl?.dispose();
      _chewieCtrl = null;
      _vpCtrl = null;
      setState(() {
        _expanded = false;
        _loaded = false;
        _failed = false;
      });
    }
  }

  @override
  void dispose() {
    _chewieCtrl?.dispose();
    _vpCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          // Thumbnail / player row
          Pressable(
            onTap: _togglePlayer,
            pressedScale: 0.99,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              height: _expanded ? 200 : 72,
              decoration: BoxDecoration(
                color: _expanded
                    ? Colors.black
                    : widget.color.withValues(alpha: 0.08),
                borderRadius: _expanded
                    ? const BorderRadius.vertical(top: Radius.circular(20))
                    : BorderRadius.circular(20),
              ),
              child: _expanded
                  ? (_loaded && _chewieCtrl != null
                        ? ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                            child: Chewie(controller: _chewieCtrl!),
                          )
                        : _failed
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'Could not load the video. Check your '
                                'internet connection and tap to close.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          )
                        : const Center(
                            child: CircularProgressIndicator.adaptive(
                              valueColor: AlwaysStoppedAnimation(primaryTeal),
                              strokeWidth: 2,
                            ),
                          ))
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: widget.color,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              CupertinoIcons.play_fill,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  widget.title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: palette.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(
                                      CupertinoIcons.clock,
                                      size: 12,
                                      color: palette.textFaint,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      widget.duration,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: palette.textMuted,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _levelColor.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        widget.level,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _levelColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            _expanded
                                ? CupertinoIcons.chevron_up
                                : CupertinoIcons.play_circle,
                            color: widget.color,
                            size: 28,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
