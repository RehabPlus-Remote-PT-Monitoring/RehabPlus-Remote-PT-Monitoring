// Small, pure helpers that keep the exercise screen honest when pose
// tracking runs slowly (a weak or memory-starved phone, or screen casting,
// which on low-end phones can push ML Kit from ~80 ms to 1-2 s per frame).
//
// They take plain millisecond timestamps (from the screen's frame Stopwatch)
// so they can be unit-tested without a camera.
//
// - [RepClock]: times a rep by when its frames were CAPTURED, not when ML
//   Kit's results arrived. Result arrival times jump around with ML latency,
//   which made real reps look "too fast". It also says when frames are too
//   far apart to judge rep speed at all.
// - [TrackingHealth]: rolling analysed-frames-per-second with hysteresis, so
//   the screen can warn "tracking is slow" without flickering.
// - [isPoseStale]: whether a skeleton is too old to draw (it would trail
//   behind the patient or cover only part of them).

/// A skeleton older than this (capture time to now) is hidden rather than
/// drawn in the wrong place.
const int maxPoseAgeMs = 600;

/// True when the pose captured at [capturedMs] should no longer be drawn.
bool isPoseStale({required int capturedMs, required int nowMs}) =>
    nowMs - capturedMs > maxPoseAgeMs;

/// Times rep cycles from frame capture timestamps.
///
/// Call [onFrame] for EVERY analysed frame (in or out of a rep), then
/// [startCycle] on the frame where the joint leaves rest. [durationMs] and
/// [speedMeasurable] describe the rep when it is judged.
class RepClock {
  /// When any gap between analysed frames in a rep (including the gap just
  /// before it started) is longer than this, the start/end times are too
  /// uncertain to call the rep "too fast". 300 ms is about 3.3 analysed
  /// frames per second; a healthy phone analyses 7-10.
  static const int maxGapForSpeedCheckMs = 300;

  int? _lastFrameMs;
  int _lastGapMs = 0;
  int? _startMs;
  int _maxGapMs = 0;

  bool get isTiming => _startMs != null;

  /// Largest gap between analysed frames seen in the current rep.
  int get maxGapMs => _maxGapMs;

  /// Whether the current rep's duration is reliable enough for the
  /// minimum-duration ("too fast") rule.
  bool get speedMeasurable => _maxGapMs <= maxGapForSpeedCheckMs;

  void onFrame(int capturedMs) {
    final last = _lastFrameMs;
    _lastGapMs = last == null ? 0 : capturedMs - last;
    _lastFrameMs = capturedMs;
    if (_startMs != null && _lastGapMs > _maxGapMs) _maxGapMs = _lastGapMs;
  }

  /// Starts timing at [capturedMs] (the frame just passed to [onFrame]).
  /// The gap before this frame counts: the rep really started somewhere
  /// inside it.
  void startCycle(int capturedMs) {
    _startMs = capturedMs;
    _maxGapMs = _lastGapMs;
  }

  /// Rep length from its first frame to the frame captured at [capturedMs].
  int durationMs(int capturedMs) => capturedMs - (_startMs ?? capturedMs);

  /// Stops timing the current rep (frame history is kept).
  void cancel() {
    _startMs = null;
    _maxGapMs = 0;
  }

  /// Forgets everything, e.g. after the camera restarts, so the pause is not
  /// counted as a gap.
  void reset() {
    cancel();
    _lastFrameMs = null;
    _lastGapMs = 0;
  }
}

/// Rolling "how many frames per second is ML Kit really analysing" with
/// hysteresis, for the slow-tracking warning.
class TrackingHealth {
  TrackingHealth({
    this.windowMs = 3000,
    this.slowBelowFps = 4.0,
    this.recoverAboveFps = 6.0,
  });

  /// Length of the rolling window, and how long tracking must have run
  /// before it can be judged (so a camera start-up isn't called "slow").
  final int windowMs;

  /// Becomes slow when the rate drops below this...
  final double slowBelowFps;

  /// ...and only recovers above this, so the warning doesn't flicker.
  final double recoverAboveFps;

  final List<int> _frames = [];
  int? _startedMs;
  bool _isSlow = false;

  bool get isSlow => _isSlow;

  /// Records one analysed frame, captured at [capturedMs].
  void onProcessed(int capturedMs) => _frames.add(capturedMs);

  /// Analysed frames per second over the last [windowMs].
  double fps(int nowMs) {
    _drop(nowMs);
    return _frames.length * 1000 / windowMs;
  }

  /// Re-evaluates at [nowMs]. Returns true when [isSlow] changed.
  bool update(int nowMs) {
    _startedMs ??= nowMs;
    if (nowMs - _startedMs! < windowMs) return false; // not enough history
    final rate = fps(nowMs);
    final next = _isSlow ? rate < recoverAboveFps : rate < slowBelowFps;
    if (next == _isSlow) return false;
    _isSlow = next;
    return true;
  }

  /// Starts over (camera restarted or app resumed).
  void reset() {
    _frames.clear();
    _startedMs = null;
    _isSlow = false;
  }

  void _drop(int nowMs) {
    final cutoff = nowMs - windowMs;
    _frames.removeWhere((ms) => ms <= cutoff);
  }
}
