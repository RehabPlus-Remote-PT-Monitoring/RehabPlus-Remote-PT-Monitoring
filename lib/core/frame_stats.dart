// lib/core/frame_stats.dart
//
// Frame-smoothness diagnostics: how long Flutter takes to build and draw
// each frame, summarised every few seconds into ONE log line, so "the app
// feels laggy" can be checked from the device log instead of guessed.
//
//   RPLOG ... INFO Frames: Frame window {frames, janky, jankPct, p90BuildMs,
//   p90RasterMs, worstBuildMs, worstRasterMs, screen}
//
// How to read it:
//   - janky = frames whose build OR raster time went over one refresh
//     (16.7 ms at 60 Hz). A few % while navigating is normal; double digits
//     while scrolling a list is what people feel as stutter.
//   - High build ms: Dart work in build()/layout (too many rebuilds).
//     High raster ms: drawing cost (shadows, blurs, clips, native views).
//   - screen: the route on top when the window ended (FrameStats.screen).
//
// Windows with no frames (the app idle) are not logged at all, and the
// callback only does a few additions per frame, so it is cheap enough to
// leave on in release builds.

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';

import 'diagnostic_logger.dart';

/// Pure accumulator for one window of frames (unit-tested).
class FrameStatsWindow {
  FrameStatsWindow({required this.budgetMs});

  /// One refresh at the display's rate (16.7 ms at 60 Hz).
  final double budgetMs;

  final List<double> _build = [];
  final List<double> _raster = [];
  int _janky = 0;

  void add({required double buildMs, required double rasterMs}) {
    _build.add(buildMs);
    _raster.add(rasterMs);
    if (buildMs > budgetMs || rasterMs > budgetMs) _janky++;
  }

  /// The window's summary, or null when no frames were drawn. Starts a new
  /// window either way.
  Map<String, Object?>? takeSummary() {
    if (_build.isEmpty) return null;
    final frames = _build.length;
    final summary = <String, Object?>{
      'frames': frames,
      'janky': _janky,
      'jankPct': (_janky * 1000 / frames).round() / 10,
      'p90BuildMs': _p90(_build),
      'p90RasterMs': _p90(_raster),
      'worstBuildMs': _round1(_build.reduce(math.max)),
      'worstRasterMs': _round1(_raster.reduce(math.max)),
    };
    _build.clear();
    _raster.clear();
    _janky = 0;
    return summary;
  }

  /// Nearest-rank 90th percentile.
  static double _p90(List<double> values) {
    final sorted = [...values]..sort();
    final rank = (0.9 * sorted.length).ceil().clamp(1, sorted.length);
    return _round1(sorted[rank - 1]);
  }

  static double _round1(double v) => (v * 10).round() / 10;
}

/// Hooks [FrameStatsWindow] into the engine's frame timings and logs one
/// summary per [window]. Call [install] once at startup.
class FrameStats {
  FrameStats._();

  static const Duration window = Duration(seconds: 10);
  static final FrameStatsWindow _current = FrameStatsWindow(budgetMs: 16.7);
  static DateTime _windowStart = DateTime.now();
  static bool _installed = false;

  /// Name of the screen on top, kept current by [FrameStatsRouteObserver].
  static String screen = 'startup';

  static void install() {
    if (_installed) return;
    _installed = true;
    try {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
    } catch (e, st) {
      DiagnosticLogger.I.warn(
        'Frames',
        'Frame timing hook failed',
        null,
        e,
        st,
      );
    }
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _current.add(
        buildMs: t.buildDuration.inMicroseconds / 1000,
        rasterMs: t.rasterDuration.inMicroseconds / 1000,
      );
    }
    final now = DateTime.now();
    if (now.difference(_windowStart) < window) return;
    _windowStart = now;
    final summary = _current.takeSummary();
    if (summary == null) return;
    summary['screen'] = screen;
    DiagnosticLogger.I.info('Frames', 'Frame window', summary);
  }
}

/// Records which screen is on top so each frame window can name it.
/// Screens are identified by the route's settings name, or else the
/// widget type the route builds (good enough for MaterialPageRoute).
class FrameStatsRouteObserver extends NavigatorObserver {
  void _set(Route<dynamic>? route) {
    if (route == null) return;
    final name = route.settings.name;
    FrameStats.screen = name ?? route.runtimeType.toString();
    if (route is MaterialPageRoute) {
      try {
        final context = navigator?.context;
        if (context != null) {
          FrameStats.screen = route.builder(context).runtimeType.toString();
        }
      } catch (e) {
        // Creating the page widget only runs its constructor, which
        // shouldn't fail; if one does, the route type is good enough.
        FrameStats.screen = name ?? route.runtimeType.toString();
        DiagnosticLogger.I.info('Frames', 'Screen name unavailable', {
          'error': e.runtimeType.toString(),
        });
      }
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _set(newRoute);
}
