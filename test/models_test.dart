// Defensive parsing of Firestore documents (pure Dart, no Firebase needed).
//
// The dashboard writes with a service account that bypasses the security
// rules, so the app must survive any shape of data: one malformed document
// is skipped or repaired, never allowed to break the whole list.

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/models/app_notification.dart';
import 'package:rehabplus/models/chat.dart';
import 'package:rehabplus/models/firestore_fields.dart';
import 'package:rehabplus/models/prescription.dart';
import 'package:rehabplus/models/session.dart';
import 'package:rehabplus/services/notification_prefs_service.dart';

final _start = DateTime(2026, 10, 1, 9, 0);

Map<String, dynamic> _validSessionDoc() => {
  'exerciseId': 'kneeExtension',
  'exerciseName': 'Knee Extension',
  'startTime': Timestamp.fromDate(_start),
  'endTime': Timestamp.fromDate(_start.add(const Duration(minutes: 5))),
  'completedReps': 8,
  'completedSets': 1,
  'targetReps': 10,
  'targetSets': 1,
  'rejectedReps': 2,
  'repComplianceScores': [1.0, 1.0, 0.0],
  'painLevel': 3,
  'painNote': null,
  'prescriptionId': 'rx1',
  'outsideSchedule': false,
  'endedEarly': true,
};

void main() {
  group('ExerciseSession.fromFirestore', () {
    test('parses a well-formed document without repairs', () {
      final parsed = ExerciseSession.parseFirestore('s1', _validSessionDoc());
      expect(parsed.isOk, isTrue);
      expect(parsed.repaired, isEmpty);
      final s = parsed.value!;
      expect(s.id, 's1');
      expect(s.exerciseId, 'kneeExtension');
      expect(s.startTime, _start);
      expect(s.completedReps, 8);
      expect(s.painLevel, 3);
      expect(s.prescriptionId, 'rx1');
      expect(s.endedEarly, isTrue);
      expect(s.overallCompliance, closeTo(2 / 3, 1e-9));
    });

    test('a missing start time makes the document unusable', () {
      final doc = _validSessionDoc()..remove('startTime');
      final parsed = ExerciseSession.parseFirestore('s1', doc);
      expect(parsed.isOk, isFalse);
      expect(parsed.error, contains('startTime'));
      expect(
        () => ExerciseSession.fromFirestore('s1', doc),
        throwsFormatException,
      );
    });

    test('a blank or non-string exercise id makes it unusable', () {
      for (final bad in ['', '   ', 42, null]) {
        final doc = _validSessionDoc()..['exerciseId'] = bad;
        expect(
          ExerciseSession.parseFirestore('s1', doc).isOk,
          isFalse,
          reason: 'exerciseId = $bad',
        );
      }
    });

    test('pain outside 0..10 is clamped, not dropped, and reported', () {
      final high = ExerciseSession.parseFirestore(
        's1',
        _validSessionDoc()..['painLevel'] = 15,
      );
      expect(high.value!.painLevel, 10);
      expect(high.repaired, contains('painLevel'));

      final low = ExerciseSession.parseFirestore(
        's1',
        _validSessionDoc()..['painLevel'] = -2,
      );
      expect(low.value!.painLevel, 0);
    });

    test('wrong types fall back to defaults and are reported', () {
      final doc = _validSessionDoc()
        ..['completedReps'] = 'eight'
        ..['targetReps'] = -5
        ..['painLevel'] = '3'
        ..['endedEarly'] = 'yes'
        ..['exerciseName'] = 7
        ..['repComplianceScores'] = [1.0, 'x', double.nan, 2.0]
        ..['notes'] = {'not': 'a string'};
      final parsed = ExerciseSession.parseFirestore('s1', doc);
      final s = parsed.value!;
      expect(s.completedReps, 0);
      expect(s.targetReps, 0);
      expect(s.painLevel, isNull);
      expect(s.endedEarly, isFalse);
      expect(s.exerciseName, 'kneeExtension'); // falls back to the id
      expect(s.repComplianceScores, [1.0, 1.0]); // junk dropped, 2.0 clamped
      expect(s.notes, isNull);
      expect(
        parsed.repaired,
        containsAll([
          'completedReps',
          'targetReps',
          'painLevel',
          'endedEarly',
          'exerciseName',
          'repComplianceScores',
          'notes',
        ]),
      );
    });

    test('whole doubles (as PHP/JS write them) are accepted as ints', () {
      final doc = _validSessionDoc()..['completedReps'] = 8.0;
      final parsed = ExerciseSession.parseFirestore('s1', doc);
      expect(parsed.value!.completedReps, 8);
      expect(parsed.repaired, isEmpty);
    });

    test('an end time before the start is dropped', () {
      final doc = _validSessionDoc()
        ..['endTime'] = Timestamp.fromDate(
          _start.subtract(const Duration(hours: 1)),
        );
      final parsed = ExerciseSession.parseFirestore('s1', doc);
      expect(parsed.value!.endTime, isNull);
      expect(parsed.repaired, contains('endTime'));
    });

    test('an over-long pain note is clipped to the rules limit', () {
      final doc = _validSessionDoc()..['painNote'] = 'x' * 500;
      final s = ExerciseSession.fromFirestore('s1', doc);
      expect(s.painNote!.length, ExerciseSession.maxPainNoteLength);
    });

    test('a batch skips bad documents and keeps the rest in order', () {
      final batch = ExerciseSession.parseFirestoreBatch([
        ('a', _validSessionDoc()),
        ('bad', <String, dynamic>{'exerciseId': 'kneeExtension'}),
        ('b', _validSessionDoc()..['painLevel'] = 99),
      ]);
      expect(batch.sessions.map((s) => s.id), ['a', 'b']);
      expect(batch.skipped.keys, ['bad']);
      expect(batch.skipped['bad'], contains('startTime'));
      expect(batch.repaired, {
        'b': ['painLevel'],
      });
    });
  });

  group('ExerciseSession writing', () {
    ExerciseSession session({int? pain = 4, String? note}) => ExerciseSession(
      id: 's1',
      exerciseId: 'kneeExtension',
      exerciseName: 'Knee Extension',
      startTime: _start,
      targetReps: 10,
      targetSets: 1,
      completedReps: 10,
      painLevel: pain,
      painNote: note,
    );

    test('a valid session has no rule problems', () {
      expect(session().firestoreProblems(), isEmpty);
    });

    test('a missing or out-of-range pain level is reported', () {
      expect(session(pain: null).firestoreProblems(), ['painLevel']);
      expect(session(pain: 11).firestoreProblems(), ['painLevel']);
    });

    test('toFirestore clips the pain note and uses Timestamps', () {
      final data = session(note: 'n' * 400).toFirestore();
      expect(
        (data['painNote'] as String).length,
        ExerciseSession.maxPainNoteLength,
      );
      expect(data['startTime'], isA<Timestamp>());
      expect(data.containsKey('id'), isFalse);
    });

    test('toJson / fromJson round-trip', () {
      final original = session(note: 'sore');
      final copy = ExerciseSession.fromJson(original.toJson());
      expect(copy.toJson(), original.toJson());
    });
  });

  group('Prescription.fromMap', () {
    Map<String, dynamic> doc() => {
      'exerciseType': 'bicepCurl',
      'targetReps': 12,
      'frequencyPerWeek': 4,
      'active': true,
      'createdAt': Timestamp.fromDate(_start),
    };

    test('parses a well-formed document', () {
      final parsed = Prescription.parse('rx1', doc());
      final p = parsed.value!;
      expect(parsed.repaired, isEmpty);
      expect(p.exerciseType, 'bicepCurl');
      expect(p.targetReps, 12);
      expect(p.frequencyPerWeek, 4);
      expect(p.holdSeconds, isNull);
      expect(p.schedule, isNull);
      expect(p.assignedAt, _start);
    });

    test('missing type or non-positive reps make it unusable', () {
      expect(
        Prescription.parse('rx', doc()..remove('exerciseType')).isOk,
        isFalse,
      );
      expect(Prescription.parse('rx', doc()..['targetReps'] = 0).isOk, isFalse);
      expect(
        Prescription.parse('rx', doc()..['targetReps'] = 'ten').isOk,
        isFalse,
      );
      expect(
        () => Prescription.fromMap('rx', doc()..remove('targetReps')),
        throwsFormatException,
      );
    });

    test('bad optional fields fall back to defaults', () {
      final parsed = Prescription.parse(
        'rx',
        doc()
          ..['frequencyPerWeek'] = 0
          ..['holdSeconds'] = -3
          ..['notes'] = 5
          ..['schedule'] = 'weekdays',
      );
      final p = parsed.value!;
      expect(p.frequencyPerWeek, Prescription.defaultFrequencyPerWeek);
      expect(p.holdSeconds, isNull);
      expect(p.notes, isNull);
      expect(p.schedule, isNull);
      expect(
        parsed.repaired,
        containsAll(['frequencyPerWeek', 'holdSeconds', 'notes', 'schedule']),
      );
    });

    test('schedule drops unknown days and an inverted hour window', () {
      final parsed = Prescription.parse(
        'rx',
        doc()
          ..['schedule'] = {
            'days': [1, 3, 9, 0, 'Mon', 3],
            'startHour': 20,
            'endHour': 8,
          },
      );
      final schedule = parsed.value!.schedule!;
      expect(schedule.days, [1, 3]);
      expect(schedule.startHour, isNull);
      expect(schedule.endHour, isNull);
      expect(parsed.repaired, containsAll(['schedule.days', 'schedule.hours']));
    });

    test('schedule ignores hours outside 0..23 / 0..24', () {
      final schedule = PrescriptionSchedule.fromMap({
        'startHour': -1,
        'endHour': 24,
      });
      expect(schedule.startHour, isNull);
      expect(schedule.endHour, 24);
      expect(schedule.allows(DateTime(2026, 10, 1, 23)), isTrue);
    });
  });

  group('Chat', () {
    test('a message without text is unusable', () {
      expect(ChatMessage.parse('m', {'senderRole': 'patient'}).isOk, isFalse);
    });

    test('a message without sentAt falls back to now', () {
      final before = DateTime.now();
      final parsed = ChatMessage.parse('m', {
        'text': 'hi',
        'senderRole': 'staff',
      }, pending: true);
      final m = parsed.value!;
      expect(m.fromPatient, isFalse);
      expect(m.pending, isTrue);
      expect(m.sentAt.isBefore(before), isFalse);
      expect(parsed.repaired, ['sentAt']);
    });

    test('thread summary tolerates bad data', () {
      expect(ChatThreadSummary.fromMap(null).unreadForPatient, 0);
      final s = ChatThreadSummary.fromMap({
        'lastMessage': 42,
        'lastMessageAt': 'not a date',
        'unreadForPatient': -4,
      });
      expect(s.lastMessage, isNull);
      expect(s.lastMessageAt, isNull);
      expect(s.unreadForPatient, 0);
    });

    test('thread summary reads the staff unread count', () {
      expect(ChatThreadSummary.fromMap({'unreadForStaff': 2}).unreadForStaff, 2);
      expect(ChatThreadSummary.fromMap({'unreadForStaff': -1}).unreadForStaff, 0);
      expect(ChatThreadSummary.fromMap(null).unreadForStaff, 0);
    });

    group('seenByStaff (read receipts)', () {
      ChatMessage msg(String id, {required bool mine}) => ChatMessage(
        id: id,
        text: id,
        fromPatient: mine,
        sentAt: DateTime(2026, 10, 18),
      );
      // Newest first, as the chat screen lists them.
      final msgs = [
        msg('p3', mine: true),
        msg('s2', mine: false),
        msg('p2', mine: true),
        msg('p1', mine: true),
        msg('s1', mine: false),
      ];

      test('the newest unreadForStaff patient messages are unseen', () {
        expect(seenByStaff(msgs, 2), {'p1'});
      });

      test('everything of mine is seen once staff opened the chat', () {
        expect(seenByStaff(msgs, 0), {'p3', 'p2', 'p1'});
      });

      test('nothing is seen before the summary loads or when all are unread', () {
        expect(seenByStaff(msgs, null), isEmpty);
        expect(seenByStaff(msgs, 5), isEmpty);
      });
    });

    test('thread names parse safely', () {
      expect(ChatThread.tryParse('clinic'), ChatThread.clinic);
      expect(ChatThread.tryParse('admin'), isNull);
      expect(ChatThread.tryParse(null), isNull);
    });
  });

  group('AppNotification.fromFirestore', () {
    test('every field has a fallback', () {
      final n = AppNotification.fromFirestore('n1', {});
      expect(n.type, AppNotification.fallbackType);
      expect(n.title, '');
      expect(n.read, isFalse);
      expect(n.data, isEmpty);
    });

    test('keeps flat data values and drops nested ones', () {
      final parsed = AppNotification.parse('n1', {
        'type': 'message',
        'read': true,
        'data': {
          'thread': 'therapist',
          'count': 2,
          'nested': {'a': 1},
        },
      });
      expect(parsed.value!.data, {'thread': 'therapist', 'count': '2'});
      expect(parsed.repaired, ['data.nested']);
    });
  });

  group('NotificationPrefs.fromMap', () {
    test('missing or non-bool values mean "on"', () {
      final none = NotificationPrefs.fromMap(null);
      expect(none.messages, isTrue);
      expect(none.exercises, isTrue);
      final bad = NotificationPrefs.fromMap({
        'messages': 'no',
        'exercises': false,
      });
      expect(bad.messages, isTrue);
      expect(bad.exercises, isFalse);
      expect(bad.reminders, isTrue, reason: 'older app versions never saved it');
    });

    test('reminders round-trips and copyWith changes one switch only', () {
      final off = NotificationPrefs.fromMap({'reminders': false});
      expect(off.reminders, isFalse);
      expect(off.toFirestore()['reminders'], isFalse);
      final changed = off.copyWith(messages: false);
      expect(changed.messages, isFalse);
      expect(changed.exercises, isTrue);
      expect(changed.reminders, isFalse);
    });
  });

  group('clipText', () {
    test('leaves short text alone and cuts long text', () {
      expect(clipText('abc', 5), 'abc');
      expect(clipText('abcdef', 3), 'abc');
    });

    test('never splits an emoji in half', () {
      const text = 'ab😀cd'; // 😀 is two UTF-16 code units at index 2..3
      expect(clipText(text, 3), 'ab');
      expect(clipText(text, 4), 'ab😀');
    });
  });
}
