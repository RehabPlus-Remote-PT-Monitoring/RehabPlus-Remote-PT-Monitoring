// Movement replay encoder: the byte layout is proven by decoding it here
// with an independent, test-side decoder written from the contract
// (API_CONTRACT.md "replay/"; docs/superpowers/specs/
// 2026-11-15-movement-replay-design.md), plus every limit the rules check.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rehabplus/services/replay_recorder.dart';

/// One decoded landmark; null x/y means "missing" (0xFFFF).
class _Lm {
  _Lm(this.x, this.y, this.conf);
  final int? x;
  final int? y;
  final int conf;
}

class _Frame {
  _Frame(this.t, this.angleTenths, this.landmarks);
  final int t;
  final int? angleTenths; // null = 0xFFFF
  final List<_Lm> landmarks;
}

/// Decoder written from the contract, not from the encoder's code.
List<_Frame> _decode(Uint8List data) {
  expect(data.length % 171, 0, reason: 'whole 171-byte frames');
  final view = ByteData.sublistView(data);
  final frames = <_Frame>[];
  for (var off = 0; off < data.length; off += 171) {
    final t = view.getUint32(off, Endian.little);
    final a = view.getUint16(off + 4, Endian.little);
    final lms = <_Lm>[];
    for (var i = 0; i < 33; i++) {
      final p = off + 6 + i * 5;
      final x = view.getUint16(p, Endian.little);
      final y = view.getUint16(p + 2, Endian.little);
      final c = view.getUint8(p + 4);
      lms.add(_Lm(x == 0xFFFF ? null : x, y == 0xFFFF ? null : y, c));
    }
    frames.add(_Frame(t, a == 0xFFFF ? null : a, lms));
  }
  return frames;
}

List<_Frame> _decodeAll(ReplayPayload p) => [
  for (final c in p.chunks) ..._decode(c.data),
];

List<ReplayPoint?> _pose(double x, double y, double c) =>
    List<ReplayPoint?>.generate(33, (i) => ReplayPoint(x, y, c));

ReplayPayload _encode(ReplayRecorder r) =>
    r.encode(aspect: 0.75, mirrored: true)!;

/// Records [n] frames 100 ms apart.
ReplayRecorder _withFrames(int n) {
  final r = ReplayRecorder(maxDurationMs: 1 << 30);
  for (var i = 0; i < n; i++) {
    r.addFrame(i * 100, _pose(0.5, 0.5, 1), 90);
  }
  return r;
}

void main() {
  group('byte layout', () {
    test('frame is 171 bytes: uint32 t, uint16 angle, 33 x (x, y, conf)', () {
      expect(ReplayRecorder.frameBytes, 171);
      final r = ReplayRecorder();
      final points = List<ReplayPoint?>.generate(
        33,
        (i) => ReplayPoint(i / 100, 1 - i / 100, i / 32),
      );
      r.addFrame(123456, points, 87.25);
      final p = _encode(r);
      expect(p.chunks.single.data.length, 171);

      // Little-endian t: 123456 = 0x0001E240.
      expect(p.chunks.single.data.sublist(0, 4), [0x40, 0xE2, 0x01, 0x00]);

      final f = _decodeAll(p).single;
      expect(f.t, 123456);
      expect(f.angleTenths, 873); // 87.25 degrees -> 872.5 -> 873
      for (var i = 0; i < 33; i++) {
        expect(f.landmarks[i].x, (i / 100 * 10000).round(), reason: 'x $i');
        expect(f.landmarks[i].y, ((1 - i / 100) * 10000).round());
        expect(f.landmarks[i].conf, (i / 32 * 255).round());
      }
    });

    test('round trip: missing landmarks, no pose and no angle', () {
      final r = ReplayRecorder();
      final partial = _pose(0.25, 0.75, 0.5)..[3] = null;
      r.addFrame(0, partial, 120);
      r.addFrame(100, const [], null); // nobody in frame
      r.addFrame(200, _pose(0.1, 0.2, 0.9), null); // angle not measured
      final frames = _decodeAll(_encode(r));
      expect(frames.map((f) => f.t), [0, 100, 200]);

      expect(frames[0].angleTenths, 1200);
      expect(frames[0].landmarks[3].x, isNull);
      expect(frames[0].landmarks[3].y, isNull);
      expect(frames[0].landmarks[3].conf, 0);
      expect(frames[0].landmarks[4].x, 2500);
      expect(frames[0].landmarks[4].y, 7500);
      expect(frames[0].landmarks[4].conf, 128); // 127.5 rounds up

      expect(frames[1].angleTenths, isNull);
      expect(
        frames[1].landmarks.every((l) => l.x == null && l.conf == 0),
        isTrue,
      );

      expect(frames[2].angleTenths, isNull);
      expect(frames[2].landmarks[0].x, 1000);
    });

    test('x, y and confidence are clamped to 0-1; NaN is missing', () {
      final r = ReplayRecorder();
      final points = _pose(0.5, 0.5, 0.5)
        ..[0] = const ReplayPoint(-0.2, 1.7, 3)
        ..[1] = const ReplayPoint(double.nan, 0.5, 1)
        ..[2] = const ReplayPoint(0.5, 0.5, double.nan);
      r.addFrame(0, points, 45);
      final lms = _decodeAll(_encode(r)).single.landmarks;
      expect([lms[0].x, lms[0].y, lms[0].conf], [0, 10000, 255]);
      expect([lms[1].x, lms[1].y, lms[1].conf], [null, null, 0]);
      expect(lms[2].conf, 0);
    });

    test('angle: 0..6553.4 stored in tenths, anything else is "none"', () {
      expect(ReplayRecorder.encodeAngle(0), 0);
      expect(ReplayRecorder.encodeAngle(6553.4), 65534);
      expect(ReplayRecorder.encodeAngle(6553.5), 0xFFFF);
      expect(ReplayRecorder.encodeAngle(-1), 0xFFFF);
      expect(ReplayRecorder.encodeAngle(double.nan), 0xFFFF);
      expect(ReplayRecorder.encodeAngle(double.infinity), 0xFFFF);
      expect(ReplayRecorder.encodeAngle(null), 0xFFFF);
    });

    test('a short landmark list counts the rest as missing', () {
      final r = ReplayRecorder();
      r.addFrame(0, [const ReplayPoint(0.5, 0.5, 1)], 10);
      final lms = _decodeAll(_encode(r)).single.landmarks;
      expect(lms[0].x, 5000);
      expect(lms.skip(1).every((l) => l.x == null), isTrue);
    });
  });

  group('down-sampling and cap', () {
    test('keeps a frame only >= 100 ms after the last kept one', () {
      final r = ReplayRecorder();
      final kept = [
        for (final t in [0, 33, 66, 99, 100, 150, 199, 200, 350, 449, 450])
          if (r.addFrame(t, const [], null)) t,
      ];
      expect(kept, [0, 100, 200, 350, 450]);
      expect(_decodeAll(_encode(r)).map((f) => f.t), kept);
      expect(r.wantsFrame(500), isFalse);
      expect(r.wantsFrame(550), isTrue);
    });

    test('fps cap sets the gap and is limited to 1-10', () {
      expect(ReplayRecorder(fpsCap: 5).minFrameGapMs, 200);
      expect(ReplayRecorder(fpsCap: 30).fps, 10);
      expect(ReplayRecorder(fpsCap: 0).fps, 1);
    });

    test('frames past the duration cap are not kept and set truncated', () {
      final r = ReplayRecorder(maxDurationMs: 1000);
      for (var t = 0; t <= 1500; t += 100) {
        r.addFrame(t, const [], null);
      }
      expect(r.frameCount, 11); // 0..1000
      expect(r.truncated, isTrue);
      final p = _encode(r);
      expect(p.meta['truncated'], isTrue);
      expect(p.meta['durationMs'], 1000);
      // Nothing more is kept after truncation, even a "valid" time.
      expect(r.addFrame(2000, const [], null), isFalse);
    });

    test('a 10-minute session at 10 fps fills exactly 20 chunks', () {
      final r = ReplayRecorder(); // default cap 600000 ms
      for (var t = 0; t <= 700000; t += 100) {
        r.addFrame(t, const [], null);
      }
      final p = _encode(r);
      expect(r.frameCount, 6000);
      expect(p.chunks.length, 20);
      expect(p.meta['frameCount'], 6000);
      expect(p.meta['chunkCount'], 20);
      expect(p.meta['truncated'], isTrue);
      expect(p.chunks.last.docId, 'c019');
    });

    test('never more than 6000 frames, even with a longer duration cap', () {
      final r = _withFrames(6005);
      expect(r.frameCount, 6000);
      expect(r.truncated, isTrue);
      expect(_encode(r).chunks.length, 20);
    });

    test('time going backwards is dropped', () {
      final r = ReplayRecorder();
      expect(r.addFrame(500, const [], null), isTrue);
      expect(r.addFrame(400, const [], null), isFalse);
      expect(r.addFrame(-5, const [], null), isFalse);
      expect(r.frameCount, 1);
    });
  });

  group('chunks', () {
    test('no frames -> null (the rules need at least one chunk)', () {
      expect(ReplayRecorder().encode(aspect: 1, mirrored: false), isNull);
    });

    for (final (n, expected) in [
      (1, [1]),
      (300, [300]),
      (301, [300, 1]),
      (600, [300, 300]),
      (901, [300, 300, 300, 1]),
    ]) {
      test('$n frames -> chunk sizes $expected', () {
        final p = _encode(_withFrames(n));
        expect(p.chunks.map((c) => c.frames), expected);
        for (final (i, c) in p.chunks.indexed) {
          expect(c.index, i);
          expect(c.firstFrame, i * 300);
          expect(c.data.length, c.frames * 171);
          expect(c.docId, 'c${i.toString().padLeft(3, '0')}');
        }
        // Frames continue across chunk borders in order.
        final ts = _decodeAll(p).map((f) => f.t).toList();
        expect(ts, [for (var i = 0; i < n; i++) i * 100]);
      });
    }
  });

  group('events', () {
    test('kept with t, kind and note; notes clipped to 120', () {
      final r = ReplayRecorder();
      r.addEvent(1000, ReplayEventKind.counted, '');
      r.addEvent(2000, ReplayEventKind.rejected, 'x' * 200);
      r.addEvent(3000, ReplayEventKind.hold, '');
      r.addFrame(0, const [], null);
      final events = _encode(r).meta['events'] as List;
      expect(events[0], {'t': 1000, 'kind': 'counted', 'note': ''});
      expect(events[1]['note'], 'x' * 120);
      expect(events[2]['kind'], 'hold');
    });

    test('clipping never splits an emoji in half', () {
      final note = '${'a' * 119}😀';
      final clipped = ReplayRecorder.clipText(note, 120);
      expect(clipped, 'a' * 119);
    });

    test('at most 200; unknown kinds and events after the cap dropped', () {
      final r = ReplayRecorder(maxDurationMs: 100000);
      r.addEvent(5, 'teleported', 'nope');
      for (var i = 0; i < 250; i++) {
        r.addEvent(i, ReplayEventKind.counted, '');
      }
      r.addFrame(0, const [], null);
      expect(r.eventCount, 200);

      final late = ReplayRecorder(maxDurationMs: 1000)
        ..addEvent(1500, ReplayEventKind.counted, '')
        ..addEvent(900, ReplayEventKind.counted, '');
      expect(late.eventCount, 1);
    });
  });

  group('meta', () {
    test('has every field the rules require, within their limits', () {
      final r = _withFrames(10)
        ..addEvent(300, ReplayEventKind.rejected, 'Rep not counted.');
      final meta = r
          .encode(aspect: 480 / 640, mirrored: true, angleLabel: 'Knee angle')!
          .meta;
      expect(meta.keys.toSet(), {
        'version',
        'fps',
        'frameCount',
        'chunkCount',
        'durationMs',
        'truncated',
        'aspect',
        'mirrored',
        'angleLabel',
        'events',
      });
      expect(meta['version'], 1);
      expect(meta['fps'], 10);
      expect(meta['frameCount'], 10);
      expect(meta['chunkCount'], 1);
      expect(meta['durationMs'], 900);
      expect(meta['truncated'], isFalse);
      expect(meta['aspect'], closeTo(0.75, 1e-9));
      expect(meta['mirrored'], isTrue);
      expect(meta['angleLabel'], 'Knee angle');
      expect(meta.containsKey('createdAt'), isFalse); // storage adds it
    });

    test('aspect is clamped to 0.2-5 and a bad one becomes 1', () {
      double aspectOf(double a) =>
          _withFrames(1).encode(aspect: a, mirrored: false)!.meta['aspect']
              as double;
      expect(aspectOf(0.01), 0.2);
      expect(aspectOf(40), 5);
      expect(aspectOf(double.nan), 1);
      expect(aspectOf(0), 1);
    });

    test('angleLabel is omitted when null/blank and clipped to 60', () {
      final r = _withFrames(1);
      expect(
        r.encode(aspect: 1, mirrored: false)!.meta,
        isNot(contains('angleLabel')),
      );
      expect(
        r.encode(aspect: 1, mirrored: false, angleLabel: '  ')!.meta,
        isNot(contains('angleLabel')),
      );
      expect(
        r
            .encode(aspect: 1, mirrored: false, angleLabel: 'a' * 80)!
            .meta['angleLabel'],
        'a' * 60,
      );
    });

    test('a 2-minute session is about 200 KB', () {
      final p = _encode(_withFrames(1200)); // 120 s at 10 fps
      expect(p.byteCount, 1200 * 171); // 205,200 bytes
      expect(p.chunks.length, 4);
    });
  });
}
