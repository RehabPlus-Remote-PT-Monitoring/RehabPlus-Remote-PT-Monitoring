// Builds replay chunk payloads (base64) in the app's byte layout for the replay tests.
const FRAME_BYTES = 171;

/**
 * frames: [{t, angle (degrees or null), points: [{x, y, c} | null] (33, missing = null)}].
 * Without points every landmark gets a plausible confident position.
 */
export function encodeFrames(frames) {
    const bytes = new Uint8Array(frames.length * FRAME_BYTES);
    const view = new DataView(bytes.buffer);

    frames.forEach((frame, f) => {
        const at = f * FRAME_BYTES;
        view.setUint32(at, frame.t, true);
        view.setUint16(at + 4, frame.angle === null || frame.angle === undefined ? 0xffff : Math.round(frame.angle * 10), true);
        for (let i = 0; i < 33; i++) {
            const p = frame.points ? frame.points[i] ?? null : { x: 0.3 + (i % 5) * 0.1, y: 0.1 + i * 0.025, c: 0.9 };
            const o = at + 6 + i * 5;
            view.setUint16(o, p ? Math.round(p.x * 10000) : 0xffff, true);
            view.setUint16(o + 2, p ? Math.round(p.y * 10000) : 0xffff, true);
            view.setUint8(o + 4, p ? Math.round(p.c * 255) : 0);
        }
    });

    let binary = '';
    bytes.forEach((b) => { binary += String.fromCharCode(b); });
    return btoa(binary);
}
