// lib/services/progress_report_loader.dart
//
// Computes progress reports for a screen ONCE per change of their inputs,
// instead of on every rebuild, and moves the work to a background isolate
// when the history is very long.
//
// Why this exists
// ---------------
// Screens used to call ProgressReport.build / ProgressStats.* inside
// build(), so the whole history was re-scanned on every setState (tapping a
// tab, a clock tick, the bottom-nav animation starting, a profile update).
// The loader memoises results keyed on:
//   - the session list's identity and length (AppProvider replaces the list
//     on every load, so identity changes exactly when the data does),
//   - the prescriptions list's identity,
//   - the calendar day (so "today" moves at midnight),
//   - and, for reports, the period length (7 / 30 / 90 days).
//
// Inline vs background isolate: [backgroundThreshold]
// ---------------------------------------------------
// Measured on the desktop Dart VM with the optimised builder (90-day report,
// all sessions inside the 2 × 90-day window the report reads):
//
//     sessions   inline build   Isolate.run round trip
//        200        ~0.9 ms          ~1.2 ms
//       1000        ~0.9 ms          ~3.4 ms
//       2000        ~1.5 ms          ~4.7 ms
//       5000        ~2.7 ms          ~6.8 ms
//
// A worker always costs more in total (spawning plus copying the sessions
// in), and copying the input still happens on the UI thread. It only pays
// off once the inline build would eat a noticeable share of a 16 ms frame
// on a mid-range phone (roughly 3–5× slower than the desktop numbers).
// That is around 2000 sessions in the window, about 11 a day for six
// months: far more than a real patient does, so in practice everything runs
// inline and only a corrupt or bulk-imported history uses the worker. The
// old suggestion of 200 would have made every normal patient pay the
// isolate overhead and see a loading state for no gain.
//
// Stale results
// -------------
// Every input change bumps a generation counter. A background result whose
// generation is out of date (new data, a new day) or that arrives after
// [dispose] (the screen was closed) is dropped and logged. A result for a
// period the user has since switched away from is still correct for that
// period, so it is cached under that period's key (switching back is then
// instant) but is never shown for another period.

import 'package:flutter/foundation.dart';

import '../core/background.dart';
import '../core/diagnostic_logger.dart';
import '../models/prescription.dart';
import '../models/session.dart';
import 'progress_report.dart';
import 'progress_stats.dart';

/// What a screen should show for one period.
class ProgressReportView {
  const ProgressReportView({
    required this.report,
    required this.isStale,
    required this.failed,
  });

  /// The report to draw. While a background build is running this is the
  /// last report shown (possibly for another period, see [isStale]); null
  /// only before the first report is ready or after a failure.
  final ProgressReport? report;

  /// True while [report] is an older result shown until the new one is
  /// ready. Only ever true for very long histories (background builds).
  final bool isStale;

  /// True when building the report threw. Already logged with the stack.
  final bool failed;

  bool get isLoading => report == null && !failed;
}

class ProgressReportLoader {
  ProgressReportLoader({
    required this.owner,
    required this.onBackgroundResult,
    this.backgroundThreshold = defaultBackgroundThreshold,
  });

  /// See the comment at the top of this file.
  static const int defaultBackgroundThreshold = 2000;

  /// Which screen this loader belongs to, for the diagnostic log
  /// ("dashboard", "report_screen").
  final String owner;

  /// Called (on the UI isolate) when a background build finishes and its
  /// result is current. The screen should `setState` if still mounted.
  final VoidCallback onBackgroundResult;

  /// Sessions in the report window at or above which the report is built
  /// on a background isolate. Overridable for tests.
  final int backgroundThreshold;

  static const String _tag = 'ProgressReport';
  final DiagnosticLogger _log = DiagnosticLogger.I;

  // ── Current inputs ────────────────────────────────────────────────────
  List<ExerciseSession>? _sessions;
  int _sessionCount = -1;
  List<Prescription>? _prescriptions;
  DateTime? _day;
  int _generation = 0;
  bool _disposed = false;

  // ── Results for the current inputs ────────────────────────────────────
  final Map<int, ProgressReport> _reports = {};
  final Set<int> _pending = {};
  final Set<int> _failed = {};
  ProgressOverview? _overview;

  /// Last report handed to the screen, kept across input changes so a
  /// background rebuild never flashes an empty card.
  ProgressReport? _lastShown;

  /// Starts a new generation when any input differs from the last call.
  void _syncInputs(
    List<ExerciseSession> sessions,
    List<Prescription> prescriptions,
    DateTime now,
  ) {
    final day = CalendarDays.startOf(now);
    final same =
        identical(sessions, _sessions) &&
        sessions.length == _sessionCount &&
        identical(prescriptions, _prescriptions) &&
        day == _day;
    if (same) return;

    final reason =
        !identical(sessions, _sessions) || sessions.length != _sessionCount
        ? 'sessions'
        : (day != _day ? 'day' : 'prescriptions');
    if (_sessions != null) {
      _log.verbose(_tag, 'Inputs changed; cache cleared', {
        'owner': owner,
        'reason': reason,
        'sessionsIn': sessions.length,
        'cachedReports': _reports.length,
        'pending': _pending.length,
      });
    }

    _sessions = sessions;
    _sessionCount = sessions.length;
    _prescriptions = prescriptions;
    _day = day;
    _generation++;
    _reports.clear();
    _pending.clear();
    _failed.clear();
    _overview = null;
  }

  /// The week and the 7/30/90-day stat totals for the dashboard. A single
  /// linear pass (about 2 ms for 20 000 sessions on the desktop VM), so it
  /// always runs inline, once per input change.
  ProgressOverview overviewFor(
    List<ExerciseSession> sessions, {
    List<Prescription> prescriptions = const [],
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    _syncInputs(sessions, prescriptions, clock);
    final cached = _overview;
    if (cached != null) return cached;

    final stopwatch = Stopwatch()..start();
    try {
      final overview = ProgressStats.overview(sessions, clock);
      _log.verbose(_tag, 'Overview built', {
        'owner': owner,
        'sessionsIn': sessions.length,
        'ms': stopwatch.elapsedMilliseconds,
      });
      return _overview = overview;
    } catch (e, st) {
      _log.error(
        _tag,
        'Overview build failed',
        {'owner': owner, 'sessionsIn': sessions.length},
        e,
        st,
      );
      // Zeros rather than a red error screen; the failure is in the log.
      return _overview = ProgressStats.overview(const [], clock);
    }
  }

  /// The report for the last [days] days. Builds it inline (and returns it)
  /// when the window is small; otherwise starts a background build and
  /// returns the last shown report marked stale until it finishes.
  ProgressReportView reportFor(
    List<ExerciseSession> sessions, {
    required int days,
    List<Prescription> prescriptions = const [],
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    _syncInputs(sessions, prescriptions, clock);

    final cached = _reports[days];
    if (cached != null) return _show(cached);
    if (_failed.contains(days)) {
      return ProgressReportView(report: null, isStale: false, failed: true);
    }
    if (_pending.contains(days)) {
      return ProgressReportView(
        report: _lastShown,
        isStale: _lastShown != null,
        failed: false,
      );
    }

    // Small histories: build right here, no filtering or copying needed.
    if (sessions.length < backgroundThreshold) {
      final report = _buildInline(sessions, clock, days, prescriptions);
      return report == null
          ? const ProgressReportView(report: null, isStale: false, failed: true)
          : _show(report);
    }

    // Long history: keep only the sessions the report reads (cheap instant
    // comparisons), then decide on that count.
    final relevant = ProgressReport.relevantSessions(
      sessions,
      clock,
      days: days,
    );
    if (relevant.length < backgroundThreshold) {
      final report = _buildInline(relevant, clock, days, prescriptions);
      return report == null
          ? const ProgressReportView(report: null, isStale: false, failed: true)
          : _show(report);
    }

    _startBackground(relevant, clock, days, prescriptions, sessions.length);
    return ProgressReportView(
      report: _lastShown,
      isStale: _lastShown != null,
      failed: false,
    );
  }

  /// Whether a background build for [days] is running.
  bool isComputing(int days) => _pending.contains(days);

  /// Stops delivering results; call from the screen's dispose().
  void dispose() {
    _disposed = true;
    if (_pending.isNotEmpty) {
      _log.verbose(_tag, 'Loader disposed with builds running', {
        'owner': owner,
        'pending': _pending.length,
      });
    }
  }

  ProgressReportView _show(ProgressReport report) {
    _lastShown = report;
    return ProgressReportView(report: report, isStale: false, failed: false);
  }

  ProgressReport? _buildInline(
    List<ExerciseSession> sessions,
    DateTime now,
    int days,
    List<Prescription> prescriptions,
  ) {
    final stopwatch = Stopwatch()..start();
    try {
      final report = ProgressReport.build(
        sessions,
        now,
        days: days,
        prescriptions: prescriptions,
      );
      _reports[days] = report;
      _logBuilt(report, sessions.length, days, stopwatch, 'inline');
      return report;
    } catch (e, st) {
      _failed.add(days);
      _log.error(
        _tag,
        'Report build failed',
        {
          'owner': owner,
          'days': days,
          'sessionsIn': sessions.length,
          'where': 'inline',
        },
        e,
        st,
      );
      return null;
    }
  }

  void _startBackground(
    List<ExerciseSession> relevant,
    DateTime now,
    int days,
    List<Prescription> prescriptions,
    int totalSessions,
  ) {
    final generation = _generation;
    _pending.add(days);
    final stopwatch = Stopwatch()..start();
    _log.info(_tag, 'Report build started in background', {
      'owner': owner,
      'days': days,
      'sessionsIn': totalSessions,
      'inWindow': relevant.length,
    });

    runInBackground<ProgressReport>(
      'ProgressReport.build',
      _buildJob(relevant, now, days, prescriptions),
      heavy: true,
      data: {'owner': owner, 'days': days, 'inWindow': relevant.length},
    ).then(
      (report) {
        if (_disposed || generation != _generation) {
          _log.verbose(_tag, 'Report result discarded', {
            'owner': owner,
            'days': days,
            'reason': _disposed ? 'disposed' : 'inputs_changed',
            'ms': stopwatch.elapsedMilliseconds,
          });
          return;
        }
        _pending.remove(days);
        _reports[days] = report;
        _logBuilt(report, relevant.length, days, stopwatch, 'background');
        onBackgroundResult();
      },
      onError: (Object e, StackTrace st) {
        if (_disposed || generation != _generation) return;
        _pending.remove(days);
        _failed.add(days);
        _log.error(
          _tag,
          'Report build failed',
          {
            'owner': owner,
            'days': days,
            'sessionsIn': relevant.length,
            'where': 'background',
          },
          e,
          st,
        );
        onBackgroundResult();
      },
    );
  }

  /// The job sent to the worker isolate. A static function so the closure
  /// captures only its plain-data parameters: a closure written inside an
  /// instance method could also capture `this` (the loader, which holds a
  /// callback into the widget), which can't be sent to another isolate.
  static ProgressReport Function() _buildJob(
    List<ExerciseSession> sessions,
    DateTime now,
    int days,
    List<Prescription> prescriptions,
  ) =>
      () => ProgressReport.build(
        sessions,
        now,
        days: days,
        prescriptions: prescriptions,
      );

  void _logBuilt(
    ProgressReport report,
    int sessionsIn,
    int days,
    Stopwatch stopwatch,
    String where,
  ) {
    _log.info(_tag, 'Report built', {
      'owner': owner,
      'days': days,
      'sessionsIn': sessionsIn,
      'inWindow': report.sessions,
      'verdict': report.status.name,
      'findings': report.findings.length,
      'ms': stopwatch.elapsedMilliseconds,
      'where': where,
    });
  }
}
