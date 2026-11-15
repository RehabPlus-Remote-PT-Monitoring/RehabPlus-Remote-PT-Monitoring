// Movement replay: Firestore payload builders (replay_storage.dart) and the
// screen bridge (replay_capture.dart). No Firestore fake exists in this
// repo, so the documents are checked as plain maps with FieldValue/Blob
// equality, and the capture against ML Kit landmark objects built by hand.

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' show Blob, FieldValue;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:rehabplus/models/session.dart';
import 'package:rehabplus/services/replay_capture.dart';
import 'package:rehabplus/services/replay_recorder.dart';
import 'package:rehabplus/services/replay_storage.dart';

ReplayPayload _payload({int frames = 301, int events = 2}) {
  final r = ReplayRecorder();
  for (var i = 0; i < frames; i++) {
    r.addFrame(i * 100, const [], null);
  }
  for (var i = 0; i < events; i++) {
    r.addEvent(i * 1000, ReplayEventKind.counted, '');
  }
  return r.encode(aspect: 0.75, mirrored: true)!;
}

PoseLandmark _lm(PoseLandmarkType type, double x, double y, double c) =>
    PoseLandmark(type: type, x: x, y: y, z: 0, likelihood: c);

int _u16(Uint8List data, int offset) =>
    ByteData.sublistView(data).getUint16(offset, Endian.little);

void main() {
  group('replayWrites', () {
    test('meta first with a server createdAt, then one doc per chunk', () {
      final payload = _payload();
      final writes = replayWrites(payload);
      expect(writes.map((w) => w.$1), ['meta', 'c000', 'c001']);

      final meta = writes.first.$2;
      expect(meta['createdAt'], FieldValue.serverTimestamp());
      expect(meta['frameCount'], 301);
      expect(meta['chunkCount'], 2);

      final c1 = writes[2].$2;
      expect(c1.keys.toSet(), {'index', 'firstFrame', 'frames', 'data'});
      expect(c1['index'], 1);
      expect(c1['firstFrame'], 300);
      expect(c1['frames'], 1);
      expect(c1['data'], isA<Blob>());
      expect((c1['data'] as Blob).bytes, payload.chunks[1].data);
      expect((c1['data'] as Blob).bytes.length, 171);
    });

    test('does not change the payload meta (createdAt is added on a copy)', () {
      final payload = _payload();
      replayWrites(payload);
      expect(payload.meta.containsKey('createdAt'), isFalse);
    });
  });

  group('replayProblems', () {
    test('an encoded payload passes every rules check', () {
      expect(replayProblems(_payload()), isEmpty);
      expect(replayProblems(_payload(frames: 6000, events: 200)), isEmpty);
    });

    test('flags a payload the rules would refuse', () {
      final good = _payload();
      ReplayPayload withMeta(Map<String, Object?> changes) =>
          ReplayPayload(meta: {...good.meta, ...changes}, chunks: good.chunks);

      expect(replayProblems(withMeta({'fps': 30})), contains('fps'));
      expect(replayProblems(withMeta({'aspect': 9})), contains('aspect'));
      expect(
        replayProblems(withMeta({'chunkCount': 3})),
        contains('chunkCount'),
      );
      expect(
        replayProblems(withMeta({'angleLabel': 'a' * 61})),
        contains('angleLabel'),
      );
      expect(
        replayProblems(
          withMeta({
            'events': [
              {'t': 1, 'kind': 'counted', 'note': 'x' * 121},
            ],
          }),
        ),
        contains('events'),
      );

      final badChunk = ReplayPayload(
        meta: {...good.meta, 'chunkCount': 1, 'frameCount': 2},
        chunks: [
          ReplayChunk(index: 0, firstFrame: 0, frames: 2, data: Uint8List(100)),
        ],
      );
      expect(replayProblems(badChunk), contains('chunk c000'));
    });
  });

  group('ReplayCapture', () {
    test('times are ms since the session started (origin of the clock)', () {
      final capture = ReplayCapture(originMs: 5000);
      for (final clock in [7000, 7050, 7100]) {
        capture.onFrame(
          clockMs: clock,
          landmarks: null,
          uprightWidth: 480,
          uprightHeight: 640,
          angle: null,
          mirrored: false,
        );
      }
      capture.onEvent(7100, ReplayEventKind.counted, '');
      final p = capture.finish()!;
      expect(p.meta['frameCount'], 2); // 7050 dropped by the 10 fps cap
      expect(p.meta['durationMs'], 2100);
      expect((p.meta['events'] as List).single['t'], 2100);
      expect(p.meta['aspect'], closeTo(0.75, 1e-9));
    });

    test('normalises by the upright image size in PoseLandmarkType order', () {
      final capture = ReplayCapture(originMs: 0);
      capture.onFrame(
        clockMs: 0,
        landmarks: {
          PoseLandmarkType.nose: _lm(PoseLandmarkType.nose, 240, 160, 0.9),
          PoseLandmarkType.rightAnkle: _lm(
            PoseLandmarkType.rightAnkle,
            480,
            640,
            1,
          ),
        },
        uprightWidth: 480,
        uprightHeight: 640,
        angle: 0.0, // the screen's "could not measure" sentinel
        mirrored: true,
      );
      final data = capture.finish()!.chunks.single.data;
      expect(PoseLandmarkType.values.length, 33);
      int lmOffset(PoseLandmarkType t) => 6 + t.index * 5;

      expect(_u16(data, 4), 0xFFFF, reason: 'angle 0.0 stored as none');
      final nose = lmOffset(PoseLandmarkType.nose);
      expect(_u16(data, nose), 5000); // 240 / 480
      expect(_u16(data, nose + 2), 2500); // 160 / 640
      expect(data[nose + 4], (0.9 * 255).round());
      final ankle = lmOffset(PoseLandmarkType.rightAnkle);
      expect([_u16(data, ankle), _u16(data, ankle + 2)], [10000, 10000]);
      final eye = lmOffset(PoseLandmarkType.leftEye);
      expect(
        [_u16(data, eye), _u16(data, eye + 2), data[eye + 4]],
        [0xFFFF, 0xFFFF, 0],
      );
    });

    test('mirrored follows what most kept frames were drawn as', () {
      final capture = ReplayCapture(originMs: 0);
      for (var i = 0; i < 5; i++) {
        capture.onFrame(
          clockMs: i * 100,
          landmarks: null,
          uprightWidth: 480,
          uprightHeight: 640,
          angle: 90,
          mirrored: i < 3,
        );
      }
      expect(capture.finish()!.meta['mirrored'], isTrue);
    });

    test('nothing recorded -> null; never throws on bad sizes', () {
      final capture = ReplayCapture(originMs: 0);
      capture.onFrame(
        clockMs: 0,
        landmarks: null,
        uprightWidth: 0,
        uprightHeight: 0,
        angle: null,
        mirrored: false,
      );
      expect(capture.finish(), isNull);
    });
  });

  group('ExerciseSession.hasReplay', () {
    ExerciseSession session({bool hasReplay = false}) => ExerciseSession(
      id: 's1',
      exerciseId: 'kneeExtension',
      exerciseName: 'Knee Extension',
      startTime: DateTime(2026, 11, 15, 9),
      targetReps: 10,
      targetSets: 1,
      painLevel: 2,
      hasReplay: hasReplay,
    );

    test('written only when true, so old-shape sessions stay unchanged', () {
      expect(session().toFirestore(), isNot(contains('hasReplay')));
      expect(session(hasReplay: true).toFirestore()['hasReplay'], isTrue);
    });

    test('parsed as a bool; a wrong type falls back to false', () {
      final base = {
        'exerciseId': 'kneeExtension',
        'startTime': '2026-11-15T09:00:00',
        'painLevel': 1,
      };
      expect(
        ExerciseSession.fromFirestore('a', {
          ...base,
          'hasReplay': true,
        }).hasReplay,
        isTrue,
      );
      expect(ExerciseSession.fromFirestore('b', base).hasReplay, isFalse);
      final parsed = ExerciseSession.parseFirestore('c', {
        ...base,
        'hasReplay': 'yes',
      });
      expect(parsed.value!.hasReplay, isFalse);
      expect(parsed.repaired, contains('hasReplay'));
    });
  });
}
