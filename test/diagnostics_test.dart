import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/core/background.dart';
import 'package:rehabplus/core/diagnostic_logger.dart';

void main() {
  final logger = DiagnosticLogger.I;

  setUp(() {
    logger.setSink(null); // keep test output quiet
    logger.clearBuffer();
    logger.minLevel = DiagnosticLevel.info;
  });

  group('redaction', () {
    test('masks e-mail addresses but keeps the domain', () {
      expect(
        redactText('Sign-in failed for rob@rehabplus.com today'),
        'Sign-in failed for ***@rehabplus.com today',
      );
    });

    test('masks sensitive keys whatever their case or separators', () {
      final redacted = redactData({
        'Password': 'hunter2',
        'fcm_token': 'abc',
        'painNote': 'my knee hurts',
        'uid': 'pVRh123',
        'reps': 10,
      });
      expect(redacted['Password'], '<redacted>');
      expect(redacted['fcm_token'], '<redacted>');
      expect(redacted['painNote'], '<redacted>');
      expect(redacted['uid'], 'pVRh123');
      expect(redacted['reps'], 10);
    });

    test('redacts inside nested maps and lists, clips long strings', () {
      final redacted = redactData({
        'user': {'email': 'a@b.co', 'role': 'patient'},
        'list': ['x@y.org'],
        'long': 'z' * 1000,
      });
      expect((redacted['user'] as Map)['email'], '<redacted>');
      expect((redacted['user'] as Map)['role'], 'patient');
      expect((redacted['list'] as List).single, '***@y.org');
      expect((redacted['long'] as String).length, lessThan(320));
    });
  });

  group('DiagnosticLogger', () {
    test('drops events below minLevel', () {
      logger.verbose('T', 'noise');
      logger.info('T', 'kept');
      expect(logger.recent().map((e) => e.message), ['kept']);
    });

    test('sequence numbers increase, events carry error and stack', () {
      logger.info('T', 'first');
      try {
        throw StateError('boom');
      } catch (e, st) {
        logger.error('T', 'second', {'k': 1}, e, st);
      }
      final events = logger.recent();
      expect(events[1].sequence, greaterThan(events[0].sequence));
      expect(events[1].error, contains('StateError'));
      expect(events[1].stackTrace, isNotNull);
    });

    test('a throwing sink never breaks the caller', () {
      logger.setSink((_) => throw Exception('sink broke'));
      expect(() => logger.info('T', 'still fine'), returnsNormally);
      expect(logger.recent().single.message, 'still fine');
    });

    test('timed logs success with ms and rethrows failures', () async {
      final value = await logger.timed('T', 'Work', () async => 42);
      expect(value, 42);
      expect(logger.recent().last.message, 'Work done');
      expect(logger.recent().last.data!['ms'], isA<int>());

      await expectLater(
        logger.timed('T', 'Bad work', () async => throw StateError('x')),
        throwsStateError,
      );
      expect(logger.recent().last.message, 'Bad work failed');
      expect(logger.recent().last.level, DiagnosticLevel.warn);
    });

    test('file sink writes one parseable JSON object per line', () async {
      final dir = await Directory.systemTemp.createTemp('rplog');
      addTearDown(() => dir.delete(recursive: true));

      logger.info('T', 'before file', {'email': 'p@q.com'});
      await logger.installFileSink(dir);
      logger.warn('T', 'after file', {'n': 3});
      await logger.flush();

      final lines = await File(logger.logFilePath!).readAsLines();
      final records = lines.map((l) => jsonDecode(l) as Map).toList();
      final messages = records.map((r) => r['msg']).toList();
      expect(messages, containsAll(['before file', 'after file']));
      expect(records.every((r) => r['run'] == logger.runId), isTrue);
      // Redaction also applies to what reaches the disk.
      expect(lines.join(), isNot(contains('p@q.com')));
    });
  });

  group('runInBackground', () {
    test('returns the same result inline and "heavy"', () async {
      int sum() => List.generate(1000, (i) => i).reduce((a, b) => a + b);
      expect(await runInBackground('sum', sum, heavy: false), 499500);
      expect(await runInBackground('sum', sum, heavy: true), 499500);
    });

    test('propagates errors from the job', () async {
      await expectLater(
        runInBackground<int>('bad', () => throw StateError('x'), heavy: true),
        throwsStateError,
      );
    });
  });
}
