// lib/core/app_diagnostics.dart
//
// App-wide error capture and startup diagnostics.
//
// [AppDiagnostics.install] is the first thing main() runs. It makes sure that
// NO error disappears silently:
//   - Flutter framework errors (build/layout/paint)  -> FlutterError.onError
//   - Uncaught async errors anywhere on this isolate -> PlatformDispatcher.onError
// Both are written to the DiagnosticLogger (memory, console, log file) with
// their stack traces, so the log file shows what went wrong before a crash.
//
// It also records one "App started" event with the build mode, app version,
// OS and the per-launch run id, which is the first thing to check when
// reading a log from a patient's phone.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'diagnostic_logger.dart';

class AppDiagnostics {
  AppDiagnostics._();

  static const String _tag = 'App';
  static bool _installed = false;

  /// Installs the global error handlers immediately (synchronously, so
  /// startup errors are caught too) and starts the log file in the
  /// background. Call once, after WidgetsFlutterBinding.ensureInitialized().
  static void install() {
    if (_installed) return;
    _installed = true;
    final logger = DiagnosticLogger.I;

    // Framework errors: keep Flutter's own console dump in debug builds
    // (the red-screen details), and always log a structured record.
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      logger.error(
        'FlutterError',
        'Framework error',
        {
          'library': details.library,
          'context': details.context?.toDescription(),
          'silent': details.silent,
        },
        details.exception,
        details.stack,
      );
      if (kDebugMode) previousFlutterHandler?.call(details);
    };

    // Errors no one awaited or caught (e.g. a failed unawaited Future).
    // Returning true marks them handled, so the app keeps running.
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      logger.error('Uncaught', 'Uncaught async error', null, error, stack);
      return true;
    };

    // Flush the log file when the app is backgrounded: Android may kill a
    // background app without any further callback.
    WidgetsBinding.instance.addObserver(_FlushOnPause());

    unawaited(_startFileLoggingAndDescribeApp());
  }

  static Future<void> _startFileLoggingAndDescribeApp() async {
    final logger = DiagnosticLogger.I;
    try {
      final support = await getApplicationSupportDirectory();
      await logger.installFileSink(
        Directory('${support.path}${Platform.pathSeparator}logs'),
      );
    } catch (e, st) {
      logger.warn(_tag, 'Could not locate the log directory', null, e, st);
    }

    String version = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Not fatal: only used for the log line below.
    }

    logger.info(_tag, 'App started', {
      'run': logger.runId,
      'version': version,
      'mode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'locale': Platform.localeName,
      'processors': Platform.numberOfProcessors,
      'logLevel': logger.minLevel.name,
    });
  }
}

class _FlushOnPause with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    DiagnosticLogger.I.info('Lifecycle', 'App state changed', {
      'state': state.name,
    });
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(DiagnosticLogger.I.flush());
    }
  }
}
