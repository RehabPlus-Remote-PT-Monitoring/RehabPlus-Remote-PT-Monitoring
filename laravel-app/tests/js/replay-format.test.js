import { describe, expect, test } from 'vitest';
import {
    BONES, FRAME_BYTES, LANDMARK_COUNT,
    base64ToBytes, decodeChunk, decodeChunks, formatAngle, formatTime, frameAt, frameIndexAt,
    isOutOfFrame, isVisible, letterbox, markerPercent, recentEvent, toCanvas,
} from '../../resources/js/replay-format.js';
import { encodeFrames } from './replay-fixture.js';

describe('decodeChunk', () => {
    test('reads the exact little-endian layout, including 0xFFFF for missing values', () => {
        // Built by hand byte for byte (not with the fixture helper) so a mistake there can't hide one here.
        const bytes = new Uint8Array(FRAME_BYTES).fill(0xff); // every landmark missing to start
        const view = new DataView(bytes.buffer);
        view.setUint32(0, 123456, true);              // t
        view.setUint16(4, 925, true);                 // 92.5 degrees
        // landmark 11 (left shoulder): x 0.25, y 0.5, confidence 255
        view.setUint16(6 + 11 * 5, 2500, true);
        view.setUint16(6 + 11 * 5 + 2, 5000, true);
        view.setUint8(6 + 11 * 5 + 4, 255);
        // landmark 32 (last): x 1.0, y 0, confidence 51 (= 0.2)
        view.setUint16(6 + 32 * 5, 10000, true);
        view.setUint16(6 + 32 * 5 + 2, 0, true);
        view.setUint8(6 + 32 * 5 + 4, 51);

        const [frame] = decodeChunk(btoa(String.fromCharCode(...bytes)));

        expect(frame.t).toBe(123456);
        expect(frame.angle).toBe(92.5);
        expect(frame.points).toHaveLength(LANDMARK_COUNT);
        expect(frame.points[11]).toEqual({ x: 0.25, y: 0.5, c: 1 });
        expect(frame.points[32]).toEqual({ x: 1, y: 0, c: 0.2 });
        expect(frame.points[0]).toBeNull();           // x = y = 0xFFFF
        expect(frame.points[31]).toBeNull();
    });

    test('0xFFFF angle means not measured', () => {
        const [frame] = decodeChunk(encodeFrames([{ t: 5, angle: null, points: [] }]));
        expect(frame.angle).toBeNull();
        expect(frame.t).toBe(5);
    });

    test('several frames in order; a partial trailing record is ignored', () => {
        const base64 = encodeFrames([{ t: 0, angle: 10 }, { t: 100, angle: 20 }, { t: 200, angle: 30 }]);
        const bytes = base64ToBytes(base64);
        expect(bytes.length).toBe(3 * FRAME_BYTES);

        const truncated = btoa(String.fromCharCode(...bytes.slice(0, 2 * FRAME_BYTES + 10)));
        expect(decodeChunk(truncated).map((f) => f.t)).toEqual([0, 100]);
        expect(decodeChunks([base64, encodeFrames([{ t: 300 }])]).map((f) => f.angle)).toEqual([10, 20, 30, null]);
    });

    test('not base64 throws (the player shows its error instead)', () => {
        expect(() => decodeChunk('%%%')).toThrow();
    });
});

describe('frameAt', () => {
    const frames = [{ t: 0 }, { t: 100 }, { t: 250 }, { t: 400 }];

    test('picks the last frame at or before the time', () => {
        expect(frameIndexAt(frames, 0)).toBe(0);
        expect(frameIndexAt(frames, 99)).toBe(0);
        expect(frameIndexAt(frames, 100)).toBe(1);
        expect(frameIndexAt(frames, 399)).toBe(2);
        expect(frameIndexAt(frames, 99999)).toBe(3);
        expect(frameAt(frames, 260)).toBe(frames[2]);
    });

    test('before the first frame shows the first; no frames gives nothing', () => {
        expect(frameIndexAt([{ t: 50 }, { t: 60 }], 10)).toBe(0);
        expect(frameIndexAt([], 10)).toBe(-1);
        expect(frameAt([], 10)).toBeNull();
    });
});

describe('visibility', () => {
    test('joints under 0.3 confidence are not drawn', () => {
        expect(isVisible(null)).toBe(false);
        expect(isVisible({ x: 0, y: 0, c: 0.29 })).toBe(false);
        expect(isVisible({ x: 0, y: 0, c: 0.3 })).toBe(true);
    });

    test('a frame with nothing confident is out of frame', () => {
        expect(isOutOfFrame({ points: new Array(33).fill(null) })).toBe(true);
        expect(isOutOfFrame({ points: [{ x: 0, y: 0, c: 0.1 }] })).toBe(true);
        expect(isOutOfFrame({ points: [null, { x: 0, y: 0, c: 0.9 }] })).toBe(false);
        expect(isOutOfFrame(null)).toBe(true);
    });
});

describe('letterbox and mirroring', () => {
    test('portrait recording in a landscape canvas: full height, centred horizontally', () => {
        expect(letterbox(400, 300, 0.5)).toEqual({ x: 125, y: 0, width: 150, height: 300 });
    });

    test('landscape recording in a portrait canvas: full width, centred vertically', () => {
        expect(letterbox(300, 400, 1.5)).toEqual({ x: 0, y: 100, width: 300, height: 200 });
    });

    test('same aspect fills the canvas', () => {
        expect(letterbox(160, 90, 16 / 9)).toEqual({ x: 0, y: 0, width: 160, height: 90 });
    });

    test('positions map into the box; mirrored flips x inside it, like the app', () => {
        const box = { x: 125, y: 0, width: 150, height: 300 };
        expect(toCanvas({ x: 0.2, y: 0.5 }, box, false)).toEqual({ x: 155, y: 150 });
        expect(toCanvas({ x: 0.2, y: 0.5 }, box, true)).toEqual({ x: 245, y: 150 });
        // The app mirrors with canvasWidth - x; a centred box gives the same point.
        expect(400 - toCanvas({ x: 0.2, y: 0.5 }, box, false).x).toBe(245);
    });
});

describe('formatting and markers', () => {
    test('angle and time', () => {
        expect(formatAngle(92.5)).toBe('93°');
        expect(formatAngle(null)).toBe('—');
        expect(formatTime(0)).toBe('0:00');
        expect(formatTime(65_400)).toBe('1:05');
        expect(formatTime(-10)).toBe('0:00');
    });

    test('markers sit at the event share of the session, clamped', () => {
        expect(markerPercent(500, 1000)).toBe(50);
        expect(markerPercent(2000, 1000)).toBe(100);
        expect(markerPercent(10, 0)).toBe(0);
    });

    test('recent event caption only shortly after the event', () => {
        const events = [{ t: 1000, kind: 'counted' }, { t: 3000, kind: 'rejected' }];
        expect(recentEvent(events, 900)).toBeNull();
        expect(recentEvent(events, 1200)).toBe(events[0]);
        expect(recentEvent(events, 2600)).toBeNull();
        expect(recentEvent(events, 3100)).toBe(events[1]);
    });

    test('bones are the app skeleton (12 connections between body landmarks)', () => {
        expect(BONES).toHaveLength(12);
        expect(BONES.flat().every((i) => i >= 11 && i <= 28)).toBe(true);
    });
});
