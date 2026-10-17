// lib/core/diagnostic_logger.dart
//
// Structured logging for the RehabPlus pose pipeline.
//
// Why this exists
// ----------------
// The pose detection pipeline (camera -> ML Kit -> FormChecker -> rep cycle)
// is the most failure-prone part of the app: a single threshold or state
// transition can silently corrupt patient feedback. In production there is
// no way to know *why* a rep was rejected or *whether* a form fault was a
// real fault or a landmark jitter. This module gives every layer a single,
// consistent way to emit structured, tag-keyed records that an AI operator
// can grep, filter, and reason about.
//
// Levels (ascending severity)
// ---------------------------
//   verbose  - per-frame noise (every joint angle, every frame). Off by default.
//   info     - normal lifecycle events (session start, target reached).
//   warn     - soft problems (a landmark dropped out, a borderline angle).
//   error    - hard problems (ML Kit threw, camera init failed).
//
// The logger is intentionally dependency-free (no Flutter widget imports) so
// it can be used from pure-Dart services and unit tests alike. The only
// Flutter symbol it needs is `debugPrint` (foundation), which is a no-op in
// release builds and cheap to call.
import 'package:flutter/foundation.dart';

/// Severity of a diagnostic record.
enum DiagnosticLevel {
  verbose,
  info,
  warn,
  error,
}

/// A single structured diagnostic record.
class DiagnosticEvent {
  const DiagnosticEvent({
    required this.timestamp,
    required this.tag,
    required this.level,
    required this.message,
    this.data,
  });

  final DateTime timestamp;
  final String tag;
  final DiagnosticLevel level;
  final String message;
  final Map<String, Object?>? data;

  @override
  String toString() {
    final buf = StringBuffer()
      ..write('[${timestamp.toIso8601String()}] ')
      ..write('${level.name.toUpperCase()} ')
      ..write('$tag: $message');
    if (data != null && data!.isNotEmpty) {
      buf.write('  data: $data');
    }
    return buf.toString();
  }
}

/// A sink for diagnostic events.
///
/// The default implementation writes to `debugPrint` (which is a no-op in
/// release builds). Swap in a custom sink to ship events to a file, a
/// remote service, or a ring buffer for an on-screen debug console.
typedef DiagnosticSink = void Function(DiagnosticEvent event);

/// Application-wide diagnostic logger.
///
/// Usage:
///   DiagnosticLogger.I.info('FormChecker', 'No pose in frame');
///   DiagnosticLogger.I.warn('RepCycle', 'Target reached twice', data: {'hits': 2});
class DiagnosticLogger {
  DiagnosticLogger._internal();

  static final DiagnosticLogger _instance = DiagnosticLogger._internal();
  static DiagnosticLogger get I => _instance;

  // Minimum level that will actually be emitted. Events below this are
  // dropped before they even reach the sink, so a hot path can stay cheap.
  DiagnosticLevel minLevel = DiagnosticLevel.info;

  // Sink used for every emitted event. Replace to redirect output.
  DiagnosticSink _sink = (event) => debugPrint(event.toString());

  // Ring buffer of the most recent events, for on-screen debug consoles
  // and for post-mortem analysis after a crash. Bounded to avoid memory
  // growth in a long-running session.
  static const int _bufferCapacity = 256;
  final List<DiagnosticEvent> _buffer = [];

  /// Replace the output sink. Pass `null` to silence the logger entirely.
  void setSink(DiagnosticSink? sink) {
    _sink = sink ?? ((event) {});
  }

  /// Returns the most recent events, newest last. Cap the result with
  /// [limit] to avoid copying the whole buffer.
  List<DiagnosticEvent> recent({int limit = 50}) {
    final start = _buffer.length > limit ? _buffer.length - limit : 0;
    return _buffer.sublist(start);
  }

  /// Clear the ring buffer. Useful between sessions so a new run does not
  /// inherit the previous run's events.
  void clearBuffer() => _buffer.clear();

  void _emit(DiagnosticLevel level, String tag, String message,
      [Map<String, Object?>? data]) {
    if (level.index < minLevel.index) return;
    final event = DiagnosticEvent(
      timestamp: DateTime.now(),
      tag: tag,
      level: level,
      message: message,
      data: data,
    );
    _buffer.add(event);
    if (_buffer.length > _bufferCapacity) {
      _buffer.removeRange(0, _buffer.length - _bufferCapacity);
    }
    _sink(event);
  }

  void verbose(String tag, String message, [Map<String, Object?>? data]) =>
      _emit(DiagnosticLevel.verbose, tag, message, data);

  void info(String tag, String message, [Map<String, Object?>? data]) =>
      _emit(DiagnosticLevel.info, tag, message, data);

  void warn(String tag, String message, [Map<String, Object?>? data]) =>
      _emit(DiagnosticLevel.warn, tag, message, data);

  void error(String tag, String message, [Map<String, Object?>? data]) =>
      _emit(DiagnosticLevel.error, tag, message, data);
}