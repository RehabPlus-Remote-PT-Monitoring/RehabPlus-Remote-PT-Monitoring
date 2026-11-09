// lib/widgets/exercise_demo_sheet.dart
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../core/exercise_demo_videos.dart';
import '../models/exercise_model.dart';
import '../screens/pose_detector_screen.dart';

const Color _primaryTeal = Color(0xFF23A8AA);
const String _tag = 'ExerciseDemo';

/// Bottom sheet that shows how to do one exercise properly: its demo video
/// (when one is set in [exerciseDemoVideoUrls]) and the set-up notes, with a
/// button to start the exercise.
class ExerciseDemoSheet extends StatefulWidget {
  final ExerciseConfig config;

  const ExerciseDemoSheet({super.key, required this.config});

  static Future<void> show(BuildContext context, ExerciseConfig config) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ExerciseDemoSheet(config: config),
    );
  }

  @override
  State<ExerciseDemoSheet> createState() => _ExerciseDemoSheetState();
}

class _ExerciseDemoSheetState extends State<ExerciseDemoSheet> {
  VideoPlayerController? _videoCtrl;
  ChewieController? _chewieCtrl;

  /// Connecting to the video.
  bool _loading = false;

  /// The video could not be loaded (bad URL, no internet).
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final url = exerciseDemoVideoUrls[widget.config.type];
    if (url != null) _initVideo(url);
  }

  Future<void> _initVideo(String url) async {
    final uri = Uri.tryParse(url);
    // Only ever stream over HTTPS.
    if (uri == null || uri.scheme != 'https') {
      DiagnosticLogger.I.error(_tag, 'Refusing non-HTTPS exercise demo', {
        'type': widget.config.type.name,
        'scheme': uri?.scheme,
      });
      _failed = true;
      return;
    }
    _loading = true;
    final controller = VideoPlayerController.networkUrl(uri);
    try {
      await controller.initialize();
    } catch (e, st) {
      DiagnosticLogger.I.warn(_tag, 'Exercise demo failed to load', {
        'type': widget.config.type.name,
      }, e, st);
      await controller.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }
    if (!mounted) {
      // Closed while connecting: nothing else will dispose it.
      await controller.dispose();
      return;
    }
    DiagnosticLogger.I.info(_tag, 'Exercise demo loaded', {
      'type': widget.config.type.name,
    });
    setState(() {
      _loading = false;
      _videoCtrl = controller;
      _chewieCtrl = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: true,
        aspectRatio: 16 / 9,
        placeholder: Container(color: Colors.black),
        materialProgressColors: ChewieProgressColors(
          playedColor: _primaryTeal,
          handleColor: _primaryTeal,
          bufferedColor: _primaryTeal.withValues(alpha: 0.3),
          backgroundColor: Colors.grey.shade800,
        ),
      );
    });
  }

  @override
  void dispose() {
    _chewieCtrl?.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  /// Opens an outside demo video (YouTube etc.) in the browser or app.
  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return;
    bool opened;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      DiagnosticLogger.I.warn(_tag, 'Opening the demo link failed', {
        'type': widget.config.type.name,
      }, e, st);
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't open the video. Check your internet connection."),
        ),
      );
    }
  }

  Widget _buildLinkCard(ExerciseDemoLink link) {
    final palette = context.palette;
    final url = link.url;
    final host = Uri.tryParse(url)?.host ?? '';
    final where = host.contains('youtube') ? 'YouTube' : 'your browser';
    return ColoredBox(
      color: palette.surfaceMuted,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.ondemand_video_rounded, size: 36, color: _primaryTeal),
              const SizedBox(height: 8),
              Text(
                'Watch the demo',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Opens in $where',
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
              if (link.author != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Video by ${link.author}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: palette.textMuted),
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _openLink(url),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Open video'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryTeal,
                  side: const BorderSide(color: _primaryTeal),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMedia() {
    final palette = context.palette;
    if (_chewieCtrl != null) return Chewie(controller: _chewieCtrl!);
    if (_loading) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: _primaryTeal, strokeWidth: 2),
        ),
      );
    }
    // Outside videos show only once the creator has given permission.
    final link = exerciseDemoLinks[widget.config.type];
    if (link != null && link.authorConsent) return _buildLinkCard(link);
    final message = _failed
        ? 'Could not load the demo video. Check your internet connection.'
        : 'Demo video coming soon.';
    return ColoredBox(
      color: palette.surfaceMuted,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.ondemand_video_rounded,
                size: 36,
                color: palette.textMuted,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: palette.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final config = widget.config;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'How to do it',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              config.title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${config.repsText}  ·  ${config.cameraView.label}',
              style: TextStyle(fontSize: 12, color: palette.textMuted),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(aspectRatio: 16 / 9, child: _buildMedia()),
            ),
            const SizedBox(height: 16),
            Text(
              'Set-up',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              config.setupTip,
              style: TextStyle(
                fontSize: 13,
                color: palette.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(
                    MaterialPageRoute(
                      builder: (_) => PoseDetectorScreen(selectedExercise: config),
                    ),
                  );
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Start exercise'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryTeal,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
