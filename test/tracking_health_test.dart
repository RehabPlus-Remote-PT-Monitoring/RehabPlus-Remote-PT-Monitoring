import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/services/tracking_health.dart';

void main() {
  group('isPoseStale', () {
    test('fresh pose is drawn, old pose is hidden', () {
      expect(
        isPoseStale(capturedMs: 1000, nowMs: 1000 + maxPoseAgeMs),
        isFalse,
      );
      expect(isPoseStale(capturedMs: 1000, nowMs: 1001 + maxPoseAgeMs), isTrue);
    });
  });

  group('RepClock', () {
    test('times a rep by capture time, ignoring ML latency', () {
      // Frames every 120 ms (healthy). Results may arrive late, but only
      // capture times are passed in, so the duration is the real one.
      final clock = RepClock();
      for (var t = 0; t <= 480; t += 120) {
        clock.onFrame(t);
      }
      clock.startCycle(480);
      for (var t = 600; t <= 1680; t += 120) {
        clock.onFrame(t);
      }
      expect(clock.durationMs(1680), 1200);
      expect(clock.speedMeasurable, isTrue);
    });

    test('a long gap inside the rep makes speed unmeasurable', () {
      final clock = RepClock()..onFrame(0);
      clock.onFrame(100);
      clock.startCycle(100);
      clock.onFrame(200);
      clock.onFrame(1400); // ML Kit stalled for 1.2 s
      expect(clock.maxGapMs, 1200);
      expect(clock.speedMeasurable, isFalse);
    });

    test('the gap just before the rep started counts too', () {
      final clock = RepClock()..onFrame(0);
      clock.onFrame(900); // first frame outside rest, 900 ms after the last
      clock.startCycle(900);
      clock.onFrame(1000);
      expect(clock.speedMeasurable, isFalse);
    });

    test('gaps outside a rep are not held against the next rep', () {
      final clock = RepClock()..onFrame(0);
      clock.onFrame(1000); // slow, but no rep running
      clock.onFrame(1100);
      clock.startCycle(1100);
      clock.onFrame(1200);
      expect(clock.maxGapMs, 100);
      expect(clock.speedMeasurable, isTrue);
    });

    test('cancel stops timing; reset also forgets the last frame', () {
      final clock = RepClock()..onFrame(0);
      clock.startCycle(0);
      clock.cancel();
      expect(clock.isTiming, isFalse);

      clock.reset();
      clock.onFrame(5000); // after a camera restart: no 5 s "gap"
      clock.startCycle(5000);
      expect(clock.maxGapMs, 0);
    });
  });

  group('TrackingHealth', () {
    void feed(TrackingHealth h, int fromMs, int toMs, int everyMs) {
      for (var t = fromMs; t < toMs; t += everyMs) {
        h.onProcessed(t);
      }
    }

    test('is not judged before a full window of history', () {
      final h = TrackingHealth();
      expect(h.update(0), isFalse);
      expect(h.update(2999), isFalse);
      expect(h.isSlow, isFalse);
    });

    test('healthy tracking is not slow', () {
      final h = TrackingHealth()..update(0);
      feed(h, 0, 3000, 120); // ~8 fps
      expect(h.update(3000), isFalse);
      expect(h.isSlow, isFalse);
      // 25 frames at 0..2880; the one at exactly t=0 has left the window.
      expect(h.fps(3000), closeTo(8.0, 0.01));
    });

    test('becomes slow below 4 fps and recovers only above 6 fps', () {
      final h = TrackingHealth()..update(0);
      feed(h, 0, 3000, 1000); // 1 fps, like casting on a weak phone
      expect(h.update(3000), isTrue);
      expect(h.isSlow, isTrue);

      feed(h, 3000, 6000, 200); // 5 fps: between the limits, stays slow
      expect(h.update(6000), isFalse);
      expect(h.isSlow, isTrue);

      feed(h, 6000, 9000, 125); // 8 fps: recovered
      expect(h.update(9000), isTrue);
      expect(h.isSlow, isFalse);
    });

    test('reset clears the state and the start-up grace period', () {
      final h = TrackingHealth()..update(0);
      h.update(3000);
      expect(h.isSlow, isTrue);
      h.reset();
      expect(h.isSlow, isFalse);
      expect(h.update(10000), isFalse); // grace period restarts here
    });
  });
}
