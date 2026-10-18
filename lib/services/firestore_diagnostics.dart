// lib/services/firestore_diagnostics.dart
//
// Shared logging helpers for the Firebase service layer, so every service
// reports reads, un-awaited writes and live listeners the same way.
//
// What ends up in the log (and what never does)
// ---------------------------------------------
//   - Constant messages ("Message sync failed"), variables in `data`.
//   - Firebase error codes (`code`: 'permission-denied', 'unavailable', ...),
//     the attached error and a trimmed stack trace.
//   - Counts, document ids, uids, `fromCache`, durations (`ms`).
//   - NEVER message text, pain notes, names, e-mail, phone, date of birth or
//     tokens. Callers must not put them in `data`.
//
// Reading the log: `adb logcat -s flutter | grep RPLOG`, then e.g.
//   grep '"tag":"ChatService"'       everything about messaging
//   grep 'sync failed'               writes the server rejected
//   grep 'stream error'              listeners that died (often rules)

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/diagnostic_logger.dart';

/// Diagnostic fields describing [error]: the Firebase error `code` and
/// `plugin` when it is a [FirebaseException], otherwise just its type.
Map<String, Object?> firebaseErrorData(Object error) => switch (error) {
  FirebaseException e => {'code': e.code, 'plugin': e.plugin},
  TimeoutException _ => {'code': 'timeout'},
  _ => {'errorType': error.runtimeType.toString()},
};

/// Logs the outcome of a Firestore write that is deliberately NOT awaited.
///
/// The app never awaits writes past the local cache: Firestore's offline
/// cache is the write queue, and the returned future only completes once
/// the server confirms (never, while offline). This attaches handlers so
/// the eventual result still reaches the log:
///   info  "(operation) synced"       {..., ms}  (ms = time to reach server)
///   error "(operation) sync failed"  {..., code, ms} + error + stack
/// A failure here usually means the security rules rejected the write, in
/// which case Firestore also removes it from the local cache.
void logUnawaitedWrite(
  Future<void> write, {
  required String tag,
  required String operation,
  Map<String, Object?>? data,
}) {
  final logger = DiagnosticLogger.I;
  final stopwatch = Stopwatch()..start();
  unawaited(
    write.then(
      (_) => logger.info(tag, '$operation synced', {
        ...?data,
        'ms': stopwatch.elapsedMilliseconds,
      }),
      onError: (Object e, StackTrace st) => logger.error(
        tag,
        '$operation sync failed',
        {
          ...?data,
          ...firebaseErrorData(e),
          'ms': stopwatch.elapsedMilliseconds,
        },
        e,
        st,
      ),
    ),
  );
}

/// Wraps a live Firestore listener ([source], e.g. `query.snapshots()`) so
/// its lifecycle is visible in the log, without changing what it delivers:
///   info    "(name) stream started"          when a widget subscribes
///   info    "(name) first snapshot"          {ms to first data, ...describe}
///   verbose "(name) snapshot"                every later update
///   warn    "(name) stream error"            {code} + error (still forwarded)
///   info    "(name) stream stopped"          {snapshots} when cancelled
///
/// Each listener to the returned stream gets its own subscription to
/// [source] (like `snapshots()` itself), and cancelling it cancels the
/// Firestore listener, so nothing leaks when a screen is disposed.
/// [describe] turns a snapshot into small diagnostic data (counts,
/// fromCache, hasPendingWrites); it must not return document contents.
Stream<T> observeStream<T>(
  Stream<T> source, {
  required String tag,
  required String name,
  Map<String, Object?>? data,
  Map<String, Object?> Function(T event)? describe,
}) {
  final logger = DiagnosticLogger.I;
  return Stream<T>.multi((controller) {
    final stopwatch = Stopwatch()..start();
    var snapshots = 0;
    logger.info(tag, '$name stream started', data);

    final subscription = source.listen(
      (event) {
        snapshots++;
        if (snapshots == 1) {
          logger.info(tag, '$name first snapshot', {
            ...?data,
            ...?describe?.call(event),
            'ms': stopwatch.elapsedMilliseconds,
          });
        } else if (logger.isVerbose) {
          logger.verbose(tag, '$name snapshot', {
            ...?data,
            ...?describe?.call(event),
            'n': snapshots,
          });
        }
        controller.addSync(event);
      },
      onError: (Object e, StackTrace st) {
        logger.warn(
          tag,
          '$name stream error',
          {...?data, ...firebaseErrorData(e)},
          e,
          st,
        );
        controller.addErrorSync(e, st);
      },
      onDone: () {
        logger.info(tag, '$name stream ended', {
          ...?data,
          'snapshots': snapshots,
        });
        controller.closeSync();
      },
    );

    controller
      ..onPause = subscription.pause
      ..onResume = subscription.resume
      ..onCancel = () {
        logger.info(tag, '$name stream stopped', {
          ...?data,
          'snapshots': snapshots,
          'aliveMs': stopwatch.elapsedMilliseconds,
        });
        return subscription.cancel();
      };
  });
}

/// Diagnostic description of a query snapshot (no document contents).
Map<String, Object?> describeQuery(QuerySnapshot<Object?> snap) => {
  'docs': snap.size,
  'changes': snap.docChanges.length,
  'fromCache': snap.metadata.isFromCache,
  'pendingWrites': snap.metadata.hasPendingWrites,
};

/// Diagnostic description of a document snapshot (no contents).
Map<String, Object?> describeDoc(DocumentSnapshot<Object?> snap) => {
  'exists': snap.exists,
  'fromCache': snap.metadata.isFromCache,
  'pendingWrites': snap.metadata.hasPendingWrites,
};
