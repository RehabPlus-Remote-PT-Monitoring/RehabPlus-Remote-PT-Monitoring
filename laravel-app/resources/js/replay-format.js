/**
 * Movement replay: decoding and drawing maths, no DOM (tested in
 * tests/js/replay-format.test.js; the player is session-replay.js).
 *
 * Byte layout (API_CONTRACT.md, replay chunks), little-endian, 171 bytes per frame:
 *   uint32 t (ms since the session started)
 *   uint16 angle x 10 (0xFFFF = not measured this frame)
 *   33 x (uint16 x x 10000, uint16 y x 10000, uint8 confidence x 255)
 * in ML Kit's PoseLandmarkType order. A landmark the model didn't return is
 * x = y = 0xFFFF with confidence 0.
 */

export const FRAME_BYTES = 171;
export const LANDMARK_COUNT = 33;
const MISSING = 0xffff;

/** Joints drawn faintly below this confidence look like real data, so they're left out. */
export const MIN_CONFIDENCE = 0.3;

/** Indexes into the 33 landmarks (ML Kit PoseLandmarkType order). */
const L = {
    nose: 0,
    leftShoulder: 11, rightShoulder: 12,
    leftElbow: 13, rightElbow: 14,
    leftWrist: 15, rightWrist: 16,
    leftHip: 23, rightHip: 24,
    leftKnee: 25, rightKnee: 26,
    leftAnkle: 27, rightAnkle: 28,
};

/** Face landmarks (0-10): the app draws no dots for them; neither do we (the nose gets a head marker). */
export const FACE_LANDMARKS = new Set([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

export const HEAD = L.nose;

/** The same bones the app's PosePainter draws (lib/widgets/pose_painter.dart), so the replay looks like what the patient saw. */
export const BONES = [
    // Arms
    [L.leftShoulder, L.leftElbow], [L.leftElbow, L.leftWrist],
    [L.rightShoulder, L.rightElbow], [L.rightElbow, L.rightWrist],
    // Legs
    [L.leftHip, L.leftKnee], [L.leftKnee, L.leftAnkle],
    [L.rightHip, L.rightKnee], [L.rightKnee, L.rightAnkle],
    // Torso
    [L.leftShoulder, L.rightShoulder], [L.leftHip, L.rightHip],
    [L.leftShoulder, L.leftHip], [L.rightShoulder, L.rightHip],
];

/** Base64 text -> bytes. Throws on text that isn't base64. */
export function base64ToBytes(base64) {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
}

/**
 * One chunk's frames: [{t, angle, points}], angle in degrees or null,
 * points[33] each {x, y, c} (0-1 position, 0-1 confidence) or null when the
 * model didn't return that landmark. Trailing bytes that don't make a whole
 * frame are ignored (the server already rejects chunks of the wrong size).
 */
export function decodeChunk(base64) {
    const bytes = base64ToBytes(base64);
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const frames = [];

    for (let offset = 0; offset + FRAME_BYTES <= bytes.length; offset += FRAME_BYTES) {
        const t = view.getUint32(offset, true);
        const rawAngle = view.getUint16(offset + 4, true);
        const points = new Array(LANDMARK_COUNT);

        for (let i = 0; i < LANDMARK_COUNT; i++) {
            const at = offset + 6 + i * 5;
            const x = view.getUint16(at, true);
            const y = view.getUint16(at + 2, true);
            points[i] = x === MISSING || y === MISSING
                ? null
                : { x: x / 10000, y: y / 10000, c: view.getUint8(at + 4) / 255 };
        }

        frames.push({ t, angle: rawAngle === MISSING ? null : rawAngle / 10, points });
    }

    return frames;
}

/** Every chunk's frames in one list (chunks arrive in order from the server). */
export function decodeChunks(chunks) {
    return chunks.flatMap((chunk) => decodeChunk(chunk));
}

/**
 * Index of the frame showing at time tMs: the last frame with t <= tMs
 * (binary search; frames are in time order). Before the first frame -> 0;
 * no frames -> -1.
 */
export function frameIndexAt(frames, tMs) {
    if (frames.length === 0) {
        return -1;
    }
    let lo = 0;
    let hi = frames.length - 1;
    while (lo < hi) {
        const mid = Math.ceil((lo + hi) / 2);
        if (frames[mid].t <= tMs) {
            lo = mid;
        } else {
            hi = mid - 1;
        }
    }
    return lo;
}

export function frameAt(frames, tMs) {
    const index = frameIndexAt(frames, tMs);
    return index < 0 ? null : frames[index];
}

/** A point we may draw: returned by the model and confident enough. */
export function isVisible(point) {
    return point !== null && point.c >= MIN_CONFIDENCE;
}

/** "Out of frame": nothing in this frame is confident enough to draw. */
export function isOutOfFrame(frame) {
    return !frame || !frame.points.some(isVisible);
}

/** "93°", or an em dash when the app didn't measure the angle this frame. */
export function formatAngle(angle) {
    return angle === null || angle === undefined ? '—' : `${Math.round(angle)}°`;
}

/** "1:05" (minutes:seconds) for a time in ms. */
export function formatTime(ms) {
    const total = Math.max(0, Math.floor(ms / 1000));
    const minutes = Math.floor(total / 60);
    const seconds = String(total % 60).padStart(2, '0');
    return `${minutes}:${seconds}`;
}

/**
 * The largest box with the recording's aspect (width / height) that fits
 * the canvas, centred: the camera image area, letterboxed.
 */
export function letterbox(canvasWidth, canvasHeight, aspect) {
    let width = canvasWidth;
    let height = width / aspect;
    if (height > canvasHeight) {
        height = canvasHeight;
        width = height * aspect;
    }
    return { x: (canvasWidth - width) / 2, y: (canvasHeight - height) / 2, width, height };
}

/**
 * A 0-1 landmark position in canvas pixels inside the letterbox. Mirrored
 * the way the app showed it to the patient (front camera): x flips inside
 * the box, which is the app's `size.width - x` because the box is centred.
 */
export function toCanvas(point, box, mirrored) {
    const nx = mirrored ? 1 - point.x : point.x;
    return { x: box.x + nx * box.width, y: box.y + point.y * box.height };
}

/** Where an event sits on the scrubber, 0-100 (%), clamped to the track. */
export function markerPercent(tMs, durationMs) {
    if (durationMs <= 0) {
        return 0;
    }
    return Math.min(100, Math.max(0, (tMs / durationMs) * 100));
}

/** The newest event at or before tMs that happened within windowMs, else null (for the live caption). */
export function recentEvent(events, tMs, windowMs = 1500) {
    let found = null;
    for (const event of events) {
        if (event.t > tMs) {
            break;
        }
        if (tMs - event.t <= windowMs) {
            found = event;
        }
    }
    return found;
}
