// lib/core/background.dart
//
// Running CPU-heavy work off the UI thread.
//
// Dart "multithreading" in one paragraph
// --------------------------------------
// Dart code runs in isolates: separate threads that share NO memory and talk
// by copying messages. All Flutter UI code runs on the main (UI) isolate.
// Waiting on I/O (Firestore, files, platform channels such as ML Kit and the
// camera) does not block that isolate: the work happens on native threads and
// `await` just yields. Only pure Dart CPU work (parsing, statistics, image
// maths) can freeze the UI, and only that is worth moving to another isolate.
//
// Moving work has a cost: the input is copied into the worker and the result
// copied back, and spawning a worker takes a few milliseconds. So small jobs
// are faster inline. [runInBackground] takes a [heavy] flag so each caller
// decides from the size of its input, and it falls back to running inline if
// a worker can't be used (web, tests, or a value that can't be sent).

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'diagnostic_logger.dart';

/// Runs [job] on a short-lived background isolate when [heavy] is true,
/// otherwise inline on the current isolate. Either way the result is the
/// same; only where the CPU time is spent changes.
///
/// Rules for [job]:
///   - It must be a top-level/static function or a closure that only
///     captures plain data (no BuildContext, no Firestore objects, no
///     platform-channel plugins: those only work on the main isolate).
///   - Its result must be plain data (numbers, strings, lists, maps, simple
///     immutable classes).
///
/// [label] names the job in the diagnostic log, together with where it ran
/// and how long it took (`ms`), so slow jobs are easy to spot.
Future<T> runInBackground<T>(
  String label,
  FutureOr<T> Function() job, {
  required bool heavy,
  Map<String, Object?>? data,
}) async {
  final logger = DiagnosticLogger.I;
  final stopwatch = Stopwatch()..start();

  // Isolate.run isn't available on the web, and see [_isFlutterTest].
  final useIsolate = heavy && !kIsWeb && !_isFlutterTest;

  if (useIsolate) {
    try {
      final result = await Isolate.run<T>(job, debugName: label);
      logger.info('Background', '$label done', {
        ...?data,
        'where': 'isolate',
        'ms': stopwatch.elapsedMilliseconds,
      });
      return result;
    } on ArgumentError catch (e, st) {
      // Something in the closure or the result can't be sent between
      // isolates. That's a programming error, but the user shouldn't pay
      // for it: log it loudly and do the work inline instead.
      logger.error(
        'Background',
        '$label could not run in an isolate; running inline',
        data,
        e,
        st,
      );
    }
  }

  final result = await job();
  logger.verbose('Background', '$label done', {
    ...?data,
    'where': 'inline',
    'ms': stopwatch.elapsedMilliseconds,
  });
  return result;
}

/// True inside `flutter test`, which sets FLUTTER_TEST in the environment.
/// Widget tests run in a fake-async zone where awaiting a real isolate can
/// hang, so jobs run inline there.
final bool _isFlutterTest =
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
