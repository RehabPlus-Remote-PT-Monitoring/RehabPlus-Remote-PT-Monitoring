// Unit tests for PosePipelineStats, the per-frame counters behind the
// "Pipeline window" and "Session summary" diagnostic logs.

import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/screens/pose_detector_screen.dart';
import 'package:rehabplus/services/form_checker.dart';

void main() {
  test('a window with no frames reports nothing', () {
    final stats = PosePipelineStats();
    expect(stats.isWindowDue(5000), isTrue);
    expect(stats.takeWindow(5000), isNull);
  });

  test('counts, fps and latency for one window, then resets', () {
    final stats = PosePipelineStats(windowMs: 5000);

    // 5 s of a 30 fps camera: 150 frames, 60 analysed, the rest dropped.
    for (var i = 0; i < 150; i++) {
      stats.onReceived();
    }
    for (var i = 0; i < 60; i++) {
      stats.onProcessed(latencyUs: 20000 + i * 100, poseFound: i % 10 != 0);
      stats.onForm(i < 6 ? FormStatus.notInFrame : FormStatus.ok);
    }
    for (var i = 0; i < 75; i++) {
      stats.onSkippedThrottle();
    }
    for (var i = 0; i < 15; i++) {
      stats.onSkippedBusy();
    }
    stats.onError();

    expect(stats.isWindowDue(4999), isFalse);
    expect(stats.isWindowDue(5000), isTrue);

    final window = stats.takeWindow(5000)!;
    expect(window['received'], 150);
    expect(window['processed'], 60);
    expect(window['skippedThrottle'], 75);
    expect(window['skippedBusy'], 15);
    expect(window['receivedFps'], 30.0);
    expect(window['processedFps'], 12.0);
    expect(window['maxMlMs'], 25.9);
    expect(window['avgMlMs'], closeTo(22.95, 0.1));
    expect(window['posesFound'], 54);
    expect(window['posesEmpty'], 6);
    expect(window['notInFrame'], 6);
    expect(window['errors'], 1);

    // The next window starts from zero but the session keeps the totals.
    expect(stats.isWindowDue(9999), isFalse);
    stats.onReceived();
    final next = stats.takeWindow(10000)!;
    expect(next['received'], 1);
    expect(next['processed'], 0);
    expect(next['avgMlMs'], 0);

    final totals = stats.sessionTotals(10000);
    expect(totals['framesReceived'], 151);
    expect(totals['framesProcessed'], 60);
    expect(totals['framesNoPose'], 6);
    expect(totals['frameErrors'], 1);
    expect(totals['avgProcessedFps'], 6.0);
    expect(totals['maxMlMs'], 25.9);
  });
}
