// Pure helpers used by the UI screens: the e-mail pre-check on the login and
// forgot-password pages, and the Settings > Report a problem payload.

import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/diagnostic_logger.dart';
import 'package:rehabplus/screens/login_page.dart';
import 'package:rehabplus/screens/settings_screen.dart';

DiagnosticEvent _event(
  int sequence,
  DiagnosticLevel level,
  String tag,
  String message, [
  Map<String, Object?>? data,
]) => DiagnosticEvent(
  timestamp: DateTime(2026, 10, 18, 12, 0, sequence),
  sequence: sequence,
  tag: tag,
  level: level,
  message: message,
  data: data,
);

void main() {
  group('looksLikeEmail', () {
    test('accepts ordinary addresses', () {
      expect(looksLikeEmail('rob@rehabplus.com'), isTrue);
      expect(looksLikeEmail('first.last+tag@sub.example.ph'), isTrue);
    });

    test('rejects obvious typos', () {
      for (final bad in [
        '',
        'rob',
        'rob@',
        '@rehabplus.com',
        'rob@rehabplus',
        'rob @rehabplus.com',
        'rob@@rehabplus.com',
      ]) {
        expect(looksLikeEmail(bad), isFalse, reason: bad);
      }
    });

    test('rejects addresses longer than the standard allows', () {
      final long = '${'a' * maxEmailLength}@x.com';
      expect(looksLikeEmail(long), isFalse);
    });
  });

  group('buildProblemReport', () {
    final events = [
      _event(1, DiagnosticLevel.info, 'Settings', 'Screen opened'),
      _event(2, DiagnosticLevel.warn, 'ChatService', 'markRead failed', {
        'email': 'rob@rehabplus.com',
      }),
      _event(3, DiagnosticLevel.error, 'Startup', 'Startup failed'),
      _event(4, DiagnosticLevel.verbose, 'Messages', 'Marking thread read'),
    ];

    test('includes version, run id and newest warnings/errors only', () {
      final report = buildProblemReport(
        userText: 'The camera froze',
        appVersion: '1.0.0 (5)',
        runId: 'abc123',
        recentEvents: events,
      );
      expect(report, startsWith('Problem report: The camera froze\n\n['));
      expect(report, contains('App 1.0.0 (5)'));
      expect(report, contains('run abc123'));
      // Newest first, info/verbose left out.
      expect(
        report,
        contains(
          'recent errors: Startup: Startup failed; '
          'ChatService: markRead failed]',
        ),
      );
      expect(report, isNot(contains('Screen opened')));
      expect(report, isNot(contains('Marking thread read')));
    });

    test('never includes event data (could hold personal details)', () {
      final report = buildProblemReport(
        userText: 'x',
        appVersion: '1',
        runId: 'r',
        recentEvents: events,
      );
      expect(report, isNot(contains('rob@rehabplus.com')));
    });

    test('keeps at most $problemReportErrorCount events', () {
      final many = [
        for (var i = 0; i < 20; i++)
          _event(i, DiagnosticLevel.warn, 'Tag$i', 'Problem $i'),
      ];
      final report = buildProblemReport(
        userText: 'x',
        appVersion: '1',
        runId: 'r',
        recentEvents: many,
      );
      expect(
        RegExp(r'Tag\d+: ').allMatches(report).length,
        problemReportErrorCount,
      );
      expect(report, contains('Tag19: Problem 19'));
      expect(report, isNot(contains('Tag14:')));
    });

    test('stays within the Firestore limit, keeping the diagnostics', () {
      final report = buildProblemReport(
        userText: 'w' * 5000,
        appVersion: '1.0.0 (5)',
        runId: 'abc123',
        recentEvents: events,
      );
      expect(report.length, lessThanOrEqualTo(maxProblemReportLength));
      expect(report, endsWith('ChatService: markRead failed]'));
    });

    test('says "unknown" when the version could not be read', () {
      final report = buildProblemReport(
        userText: 'x',
        appVersion: '',
        runId: 'r',
        recentEvents: const [],
      );
      expect(report, endsWith('[App unknown; run r]'));
    });
  });
}
