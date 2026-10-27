// lib/core/diagnostic_logger.dart
//
// Structured, privacy-safe diagnostic logging for the whole RehabPlus app.
//
// Why this exists
// ---------------
// Most problems in this app are silent: a rep rejected for a reason the
// patient can't see, a Firestore write that never syncs, a push that lands on
// the wrong channel. This logger gives every layer ONE consistent way to emit
// structured, tag-keyed records that a developer (or an AI assistant) can
// grep, filter and reason about after the fact.
//
// Where the records go
// --------------------
//   1. An in-memory ring buffer (the last [bufferCapacity] events). Used by
//      Settings > Report a problem, and by tests.
//   2. The console via `debugPrint`, one line per event, prefixed with
//      [consolePrefix]. NOTE: debugPrint is NOT silent in release builds; it
//      still reaches `adb logcat`. That is intentional (it is how we debug a
//      patient's phone) and is why every record is redacted first.
//   3. A rotating JSON-lines file on the phone, once [installFileSink] has
//      run (main() does this). One JSON object per line, so a tool can parse
//      it line by line.
//
// How to read the logs (for a developer or an AI assistant)
// --------------------------------------------------------
//   Live:      adb logcat -s flutter | grep RPLOG
//   From file: adb shell run-as com.rehabplus.app ls files/logs
//              adb shell run-as com.rehabplus.app cat files/logs/rehabplus-0.jsonl
//   Each JSON line has: ts, seq, run, lvl, tag, msg, and optionally data,
//   err (error type + message) and stack.
//   `run` is a random id per app launch, so you can split one file into
//   launches. `seq` is a per-launch counter, so gaps mean dropped events.
//
// Conventions for callers
// -----------------------
//   - tag:  the class or subsystem, e.g. 'SessionStorage', 'PosePipeline'.
//   - msg:  a short, constant sentence ("Session sync failed"). Put variable
//           values in `data`, not in the message, so messages stay greppable.
//   - data: small, flat maps of numbers/bools/short strings. Never put
//           passwords, tokens, message text, pain notes or other health
//           free text in here. Keys listed in [_sensitiveKeys] are masked
//           automatically as a safety net, and e-mail addresses are masked
//           in every string, but don't rely on that.
//
// Levels (ascending severity)
// ---------------------------
//   verbose - per-frame noise. Off by default; enable with
//             --dart-define=RP_LOG_LEVEL=verbose
//   info    - normal lifecycle events (session start, target reached).
//   warn    - soft problems (a landmark dropped out, a retryable failure).
//   error   - hard problems (ML Kit threw, camera init failed, uncaught).
//
// The logger only depends on Flutter's foundation library and dart:io, so it
// can be used from services, screens and unit tests alike.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Severity of a diagnostic record.
enum DiagnosticLevel { verbose, info, warn, error }

/// A single structured diagnostic record.
class DiagnosticEvent {
  const DiagnosticEvent({
    required this.timestamp,
    required this.sequence,
    required this.tag,
    required this.level,
    required this.message,
    this.data,
    this.error,
    this.stackTrace,
  });

  final DateTime timestamp;

  /// Per-launch counter; a gap means events were dropped.
  final int sequence;
  final String tag;
  final DiagnosticLevel level;
  final String message;
  final Map<String, Object?>? data;

  /// "ErrorType: message" of an attached error, already redacted.
  final String? error;

  /// Trimmed stack trace of an attached error.
  final String? stackTrace;

  /// The record as a JSON-friendly map (the file sink writes this).
  Map<String, Object?> toJson(String runId) => {
    'ts': timestamp.toIso8601String(),
    'seq': sequence,
    'run': runId,
    'lvl': level.name,
    'tag': tag,
    'msg': message,
    if (data != null && data!.isNotEmpty) 'data': data,
    if (error != null) 'err': error,
    if (stackTrace != null) 'stack': stackTrace,
  };

  /// Human-readable single line (the console sink writes this).
  @override
  String toString() {
    final buffer = StringBuffer()
      ..write('[${timestamp.toIso8601String()}] ')
      ..write('${level.name.toUpperCase()} ')
      ..write('$tag: $message');
    if (data != null && data!.isNotEmpty) {
      buffer.write('  data: ${jsonEncode(data, toEncodable: _fallbackJson)}');
    }
    if (error != null) buffer.write('  error: $error');
    return buffer.toString();
  }
}

/// A destination for diagnostic events.
typedef DiagnosticSink = void Function(DiagnosticEvent event);

/// Application-wide diagnostic logger (one per isolate).
///
/// Usage:
///   DiagnosticLogger.I.info('FormChecker', 'No pose in frame');
///   DiagnosticLogger.I.warn('RepCycle', 'Target reached twice', {'hits': 2});
///   DiagnosticLogger.I.error('Camera', 'Init failed', {'code': e.code},
///       error: e, stackTrace: st);
///   final sessions = await DiagnosticLogger.I.timed(
///       'SessionStorage', 'Load sessions', () => col.get());
class DiagnosticLogger {
  DiagnosticLogger._internal();

  static final DiagnosticLogger _instance = DiagnosticLogger._internal();
  static DiagnosticLogger get I => _instance;

  /// Prefix on every console line, so `adb logcat | grep RPLOG` finds them.
  static const String consolePrefix = 'RPLOG';

  /// How many recent events are kept in memory.
  static const int bufferCapacity = 500;

  /// Random id for this app launch (appears in every file record).
  final String runId = _newRunId();

  /// Minimum level that is actually emitted. Events below it are dropped
  /// before any work is done, so hot paths stay cheap. Set at build time
  /// with --dart-define=RP_LOG_LEVEL=verbose|info|warn|error.
  DiagnosticLevel minLevel = _levelFromEnvironment();

  /// Whether verbose events would be emitted. Check this before building an
  /// expensive `data` map on a per-frame path.
  bool get isVerbose => minLevel == DiagnosticLevel.verbose;

  int _sequence = 0;
  final List<DiagnosticEvent> _buffer = [];
  DiagnosticSink _consoleSink = _defaultConsoleSink;
  _FileSink? _fileSink;

  // ---------------------------------------------------------------------
  // Logging API
  // ---------------------------------------------------------------------

  void verbose(String tag, String message, [Map<String, Object?>? data]) =>
      _emit(DiagnosticLevel.verbose, tag, message, data);

  void info(String tag, String message, [Map<String, Object?>? data]) =>
      _emit(DiagnosticLevel.info, tag, message, data);

  void warn(
    String tag,
    String message, [
    Map<String, Object?>? data,
    Object? error,
    StackTrace? stackTrace,
  ]) => _emit(DiagnosticLevel.warn, tag, message, data, error, stackTrace);

  void error(
    String tag,
    String message, [
    Map<String, Object?>? data,
    Object? error,
    StackTrace? stackTrace,
  ]) => _emit(DiagnosticLevel.error, tag, message, data, error, stackTrace);

  /// Runs [operation], logging how long it took and whether it failed.
  ///
  /// Success is logged at info level with `ms`; failure at warn level with
  /// the error, and the error is re-thrown so behaviour doesn't change.
  Future<T> timed<T>(
    String tag,
    String operation,
    Future<T> Function() body, {
    Map<String, Object?>? data,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await body();
      info(tag, '$operation done', {
        ...?data,
        'ms': stopwatch.elapsedMilliseconds,
      });
      return result;
    } catch (e, st) {
      warn(
        tag,
        '$operation failed',
        {...?data, 'ms': stopwatch.elapsedMilliseconds},
        e,
        st,
      );
      rethrow;
    }
  }

  // ---------------------------------------------------------------------
  // Reading the buffer
  // ---------------------------------------------------------------------

  /// The most recent events, newest last, at most [limit] of them.
  List<DiagnosticEvent> recent({int limit = 50}) {
    final start = _buffer.length > limit ? _buffer.length - limit : 0;
    return List.unmodifiable(_buffer.sublist(start));
  }

  /// Clears the in-memory buffer (the log file is kept).
  void clearBuffer() => _buffer.clear();

  /// Path of the current log file, or null before [installFileSink].
  String? get logFilePath => _fileSink?.currentPath;

  // ---------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------

  /// Replace the console sink. Pass `null` to silence console output (the
  /// buffer and the file still receive events). Used by tests.
  void setSink(DiagnosticSink? sink) {
    _consoleSink = sink ?? (_) {};
  }

  /// Starts writing events to rotating JSON-lines files in [directory]
  /// (typically `<app support dir>/logs`). Safe to call once; later calls
  /// are ignored. Never throws: if the file can't be opened, logging simply
  /// stays in memory and on the console.
  Future<void> installFileSink(Directory directory) async {
    if (_fileSink != null) return;
    try {
      final sink = await _FileSink.open(directory);
      _fileSink = sink;
      // Events logged before the file existed are written now, so a crash
      // during startup is still on disk.
      for (final event in _buffer) {
        sink.write(event, runId);
      }
      info('Logger', 'File logging started', {'path': sink.currentPath});
    } catch (e, st) {
      warn('Logger', 'File logging unavailable', null, e, st);
    }
  }

  /// Writes any buffered file output to disk. Call when the app goes to the
  /// background, since the OS may kill it without warning afterwards.
  Future<void> flush() async => _fileSink?.flush();

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  void _emit(
    DiagnosticLevel level,
    String tag,
    String message, [
    Map<String, Object?>? data,
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (level.index < minLevel.index) return;

    final event = DiagnosticEvent(
      timestamp: DateTime.now(),
      sequence: ++_sequence,
      tag: tag,
      level: level,
      message: redactText(message),
      data: data == null ? null : redactData(data),
      error: error == null ? null : _describeError(error),
      stackTrace: stackTrace == null ? null : _trimStack(stackTrace),
    );

    _buffer.add(event);
    if (_buffer.length > bufferCapacity) {
      _buffer.removeRange(0, _buffer.length - bufferCapacity);
    }

    // A broken sink must never take the app down with it.
    try {
      _consoleSink(event);
    } catch (_) {}
    try {
      _fileSink?.write(event, runId);
    } catch (_) {}
  }

  static void _defaultConsoleSink(DiagnosticEvent event) {
    debugPrint('$consolePrefix $event');
    if (event.stackTrace != null && event.level == DiagnosticLevel.error) {
      debugPrint('$consolePrefix   stack: ${event.stackTrace}');
    }
  }

  static DiagnosticLevel _levelFromEnvironment() {
    const name = String.fromEnvironment('RP_LOG_LEVEL', defaultValue: 'info');
    return DiagnosticLevel.values.asNameMap()[name] ?? DiagnosticLevel.info;
  }

  static String _newRunId() {
    final random = Random();
    return List.generate(
      8,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  static String _describeError(Object error) {
    // FirebaseException and friends put the useful part in `code`, which
    // their toString() already includes.
    final text = error.toString();
    final clipped = text.length > 500 ? '${text.substring(0, 500)}...' : text;
    return '${error.runtimeType}: ${redactText(clipped)}';
  }

  /// Keeps the top frames only: enough to locate the fault, small enough to
  /// keep the log file readable.
  static String _trimStack(StackTrace stackTrace, {int frames = 12}) {
    final lines = stackTrace
        .toString()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final kept = lines.take(frames).join('\n');
    return lines.length > frames
        ? '$kept\n... ${lines.length - frames} more frames'
        : kept;
  }
}

// -------------------------------------------------------------------------
// Redaction
// -------------------------------------------------------------------------

/// Data keys whose values are never logged. Matched case-insensitively
/// against the whole key, after removing '_' and '-'.
const Set<String> _sensitiveKeys = {
  'password',
  'token',
  'fcmtoken',
  'idtoken',
  'accesstoken',
  'refreshtoken',
  'apikey',
  'secret',
  'email',
  'phone',
  'dob',
  'dateofbirth',
  'name',
  'displayname',
  'text',
  'body',
  'note',
  'painnote',
  'photo',
  'image',
};

final RegExp _emailPattern = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');

/// Masks e-mail addresses in free text (keeps the domain, for debugging
/// which tenant/test account it was).
@visibleForTesting
String redactText(String text) => text.replaceAllMapped(
  _emailPattern,
  (match) => '***@${match.group(0)!.split('@').last}',
);

/// Returns a copy of [data] with sensitive keys masked, e-mails masked in
/// strings, long strings clipped and non-JSON values turned into strings.
@visibleForTesting
Map<String, Object?> redactData(Map<String, Object?> data, {int depth = 0}) {
  final result = <String, Object?>{};
  data.forEach((key, value) {
    final normalised = key.toLowerCase().replaceAll(RegExp('[_-]'), '');
    if (_sensitiveKeys.contains(normalised)) {
      result[key] = value == null ? null : '<redacted>';
    } else {
      result[key] = _redactValue(value, depth);
    }
  });
  return result;
}

Object? _redactValue(Object? value, int depth) {
  if (value == null || value is num || value is bool) return value;
  if (value is String) {
    final clipped = value.length > 300 ? '${value.substring(0, 300)}...' : value;
    return redactText(clipped);
  }
  if (depth >= 3) return '<nested>';
  if (value is Map) {
    return redactData(
      value.map((k, v) => MapEntry(k.toString(), v)),
      depth: depth + 1,
    );
  }
  if (value is Iterable) {
    final items = value.take(20).map((v) => _redactValue(v, depth + 1));
    return items.toList();
  }
  if (value is DateTime) return value.toIso8601String();
  if (value is Duration) return value.inMilliseconds;
  if (value is Enum) return value.name;
  return redactText(value.toString());
}

Object? _fallbackJson(Object? value) => value.toString();

// -------------------------------------------------------------------------
// File sink
// -------------------------------------------------------------------------

/// Appends JSON lines to `rehabplus-0.jsonl`, rotating to `-1`, `-2` when the
/// file passes [_maxBytes]. dart:io does the actual disk writes on its own
/// I/O thread, so logging never blocks the UI isolate on the disk.
class _FileSink {
  _FileSink._(this._directory);

  static const int _maxBytes = 1024 * 1024; // 1 MB per file
  static const int _maxFiles = 3; // ~3 MB of history in total

  final Directory _directory;
  IOSink? _sink;
  int _bytesWritten = 0;
  bool _rotating = false;

  String get currentPath => _fileAt(0).path;

  File _fileAt(int index) =>
      File('${_directory.path}${Platform.pathSeparator}rehabplus-$index.jsonl');

  static Future<_FileSink> open(Directory directory) async {
    await directory.create(recursive: true);
    final sink = _FileSink._(directory);
    final current = sink._fileAt(0);
    sink._bytesWritten = await current.exists() ? await current.length() : 0;
    sink._sink = current.openWrite(mode: FileMode.append);
    return sink;
  }

  void write(DiagnosticEvent event, String runId) {
    final sink = _sink;
    if (sink == null) return;
    final line = '${jsonEncode(event.toJson(runId), toEncodable: _fallbackJson)}\n';
    sink.write(line);
    _bytesWritten += line.length;
    if (_bytesWritten > _maxBytes && !_rotating) unawaited(_rotate());
  }

  Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }

  /// Closes the current file, shifts older files up by one, starts a new one.
  Future<void> _rotate() async {
    _rotating = true;
    final old = _sink;
    _sink = null; // events during rotation are kept in the memory buffer
    try {
      await old?.flush();
      await old?.close();
      final oldest = _fileAt(_maxFiles - 1);
      if (await oldest.exists()) await oldest.delete();
      for (var i = _maxFiles - 2; i >= 0; i--) {
        final file = _fileAt(i);
        if (await file.exists()) await file.rename(_fileAt(i + 1).path);
      }
    } catch (_) {
      // Worst case we keep appending to a slightly larger file.
    } finally {
      _bytesWritten = 0;
      _sink = _fileAt(0).openWrite(mode: FileMode.append);
      _rotating = false;
    }
  }
}
