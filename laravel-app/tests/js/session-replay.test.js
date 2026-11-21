import { afterEach, beforeAll, beforeEach, describe, expect, test, vi } from 'vitest';
import { encodeFrames } from './replay-fixture.js';

let createPlayer;
let ctx;
let rafQueue;

/** A 2D context that only records what was drawn (jsdom has no canvas). */
function fakeContext() {
    const calls = [];
    const record = (name) => (...args) => calls.push([name, ...args]);
    return {
        calls,
        clearRect: record('clearRect'), fillRect: record('fillRect'), beginPath: record('beginPath'),
        moveTo: record('moveTo'), lineTo: record('lineTo'), stroke: record('stroke'),
        arc: record('arc'), fill: record('fill'),
    };
}

/** The player markup patients/replay.blade.php renders, with a data block. */
function mount(data, { events = true } = {}) {
    const root = document.createElement('div');
    root.className = 'replay-player';
    root.dataset.replay = '';
    root.tabIndex = 0;
    root.innerHTML = `
        <script type="application/json" data-replay-data></script>
        <div class="replay-stage">
            <canvas></canvas>
            <div data-replay-out-of-frame hidden>Out of frame</div>
            <div data-replay-caption></div>
        </div>
        <div data-replay-controls></div>
        <p data-replay-error hidden>Could not play</p>
        ${events ? '<button type="button" data-replay-seek="1500">Rep counted</button>' : ''}`;
    root.querySelector('script').textContent = typeof data === 'string' ? data : JSON.stringify(data);
    document.body.replaceChildren(root);
    return root;
}

const twoSeconds = () => encodeFrames(Array.from({ length: 21 }, (_, i) => ({ t: i * 100, angle: 90 + i })));

function replayData(overrides = {}) {
    return {
        chunks: [twoSeconds()],
        aspect: 0.5625,
        mirrored: false,
        fps: 10,
        angleLabel: 'Knee angle',
        events: [
            { t: 500, kind: 'counted', note: '' },
            { t: 1000, kind: 'rejected', note: 'Knees past toes' },
            { t: 1500, kind: 'hold', note: '' },
        ],
        ...overrides,
    };
}

function runFrame(now) {
    const queued = rafQueue;
    rafQueue = [];
    queued.forEach((cb) => cb(now));
}

const key = (root, k, target = root) => target.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true }));

beforeAll(async () => {
    window.requestAnimationFrame = (cb) => { rafQueue.push(cb); return rafQueue.length; };
    window.cancelAnimationFrame = () => { rafQueue = []; };
    HTMLCanvasElement.prototype.getContext = () => ctx;
    rafQueue = [];
    ({ createPlayer } = await import('../../resources/js/session-replay.js'));
});

beforeEach(() => {
    ctx = fakeContext();
    rafQueue = [];
});

afterEach(() => {
    vi.restoreAllMocks();
    document.body.replaceChildren();
});

describe('session replay player', () => {
    test('builds its controls from the data block', () => {
        const root = mount(replayData());
        const player = createPlayer(root, { reduceMotion: true });

        expect(player.frames).toHaveLength(21);
        expect(root.querySelector('.replay-play').textContent).toBe('Play');
        expect([...root.querySelectorAll('[data-speed]')].map((b) => b.textContent)).toEqual(['0.5×', '1×', '2×']);
        expect(root.querySelector('[data-speed="1"]').getAttribute('aria-pressed')).toBe('true');

        const scrubber = root.querySelector('input[type="range"]');
        expect(scrubber.max).toBe('2000');
        expect(scrubber.value).toBe('0');

        const markers = [...root.querySelectorAll('.replay-marker')];
        expect(markers.map((m) => m.className)).toEqual([
            'replay-marker replay-marker--counted',
            'replay-marker replay-marker--rejected',
            'replay-marker replay-marker--hold',
        ]);
        expect(markers[1].style.left).toBe('50%');
        expect(markers[1].title).toBe('0:01 · Rep not counted: Knees past toes');
        expect(root.querySelector('.replay-time').textContent).toBe('0:00 / 0:02');
        expect(root.querySelector('.replay-angle').textContent).toBe('Knee angle: 90°');
    });

    test('plays by itself unless the user prefers reduced motion', () => {
        expect(createPlayer(mount(replayData()), { reduceMotion: true }).playing).toBe(false);
        expect(createPlayer(mount(replayData()), { reduceMotion: false }).playing).toBe(true);
    });

    test('playback advances with the clock and the chosen speed, and stops at the end', () => {
        const root = mount(replayData());
        const player = createPlayer(root, { reduceMotion: true });

        player.play();
        runFrame(1000);          // first tick only sets the clock
        runFrame(1200);
        runFrame(1400);
        expect(player.time).toBe(400);

        root.querySelector('[data-speed="2"]').click();
        runFrame(1500);
        expect(player.time).toBe(600);
        expect(root.querySelector('.replay-angle').textContent).toBe('Knee angle: 96°');

        // A tab coming back after a long pause moves at most 250 ms (x speed), not the whole gap.
        runFrame(9000);
        expect(player.time).toBe(1100);

        for (let now = 9200; now <= 10200; now += 200) {
            runFrame(now);
        }
        expect(player.time).toBe(2000);
        expect(player.playing).toBe(false);
        expect(root.querySelector('.replay-play').textContent).toBe('Play');
    });

    test('Space toggles play, arrow keys step one frame', () => {
        const root = mount(replayData());
        const player = createPlayer(root, { reduceMotion: true });

        key(root, ' ');
        expect(player.playing).toBe(true);
        key(root, ' ');
        expect(player.playing).toBe(false);

        key(root, 'ArrowRight');
        key(root, 'ArrowRight');
        expect(player.time).toBe(200);
        key(root, 'ArrowLeft');
        expect(player.time).toBe(100);

        // On the scrubber too: arrows step a frame instead of 1 ms.
        key(root, 'ArrowRight', root.querySelector('input[type="range"]'));
        expect(player.time).toBe(200);
    });

    test('the event list and the markers seek there', () => {
        const root = mount(replayData());
        const player = createPlayer(root, { reduceMotion: true });

        root.querySelector('[data-replay-seek="1500"]').click();
        expect(player.time).toBe(1500);
        expect(root.querySelector('[data-replay-caption]').textContent).toBe('Hold');

        root.querySelectorAll('.replay-marker')[1].click();
        expect(player.time).toBe(1000);
        expect(root.querySelector('[data-replay-caption]').textContent).toBe('Rep not counted: Knees past toes');
        expect(root.querySelector('[data-replay-caption]').dataset.kind).toBe('rejected');
    });

    test('scrubbing moves the time', () => {
        const root = mount(replayData());
        const player = createPlayer(root, { reduceMotion: true });
        const scrubber = root.querySelector('input[type="range"]');

        scrubber.value = '1234';
        scrubber.dispatchEvent(new Event('input'));
        expect(player.time).toBe(1234);
        expect(root.querySelector('.replay-time').textContent).toBe('0:01 / 0:02');
    });

    test('draws the skeleton, skipping low-confidence joints; shows "Out of frame" for an empty frame', () => {
        const all = Array.from({ length: 33 }, (_, i) => ({ x: 0.5, y: i / 40, c: 0.9 }));
        const weakElbow = all.map((p, i) => (i === 13 ? { ...p, c: 0.1 } : p));
        const chunk = encodeFrames([
            { t: 0, angle: 90, points: all },
            { t: 100, angle: 90, points: weakElbow },
            { t: 200, angle: null, points: [] },
        ]);
        const root = mount(replayData({ chunks: [chunk], events: [] }));
        const player = createPlayer(root, { reduceMotion: true });
        const overlay = root.querySelector('[data-replay-out-of-frame]');
        const strokes = () => ctx.calls.filter((c) => c[0] === 'stroke').length;

        expect(strokes()).toBe(12 + 1);           // 12 bones + the head ring
        expect(overlay.hidden).toBe(true);

        ctx.calls.length = 0;
        player.seek(100);
        expect(strokes()).toBe(10 + 1);           // both left-elbow bones dropped

        ctx.calls.length = 0;
        player.seek(200);
        expect(strokes()).toBe(0);
        expect(overlay.hidden).toBe(false);
        expect(root.querySelector('.replay-angle').textContent).toBe('Knee angle: —');
    });

    test('mirrored replays draw x flipped inside the letterbox', () => {
        const points = Array.from({ length: 33 }, () => ({ x: 0.25, y: 0.5, c: 1 }));
        const draw = (mirrored) => {
            ctx = fakeContext();
            const root = mount(replayData({ chunks: [encodeFrames([{ t: 0, points }])], mirrored, aspect: 1, events: [] }));
            const canvas = root.querySelector('canvas');
            Object.defineProperty(canvas, 'clientWidth', { value: 200 });
            Object.defineProperty(canvas, 'clientHeight', { value: 100 });
            createPlayer(root, { reduceMotion: true });
            return ctx.calls.find((c) => c[0] === 'moveTo')[1];
        };

        // 200x100 canvas, square recording: box x 50..150.
        expect(draw(false)).toBe(75);
        expect(draw(true)).toBe(125);
    });

    test('notes are shown as text, never as HTML', () => {
        const root = mount(replayData({ events: [{ t: 0, kind: 'rejected', note: '<img src=x onerror=alert(1)>' }] }));
        createPlayer(root, { reduceMotion: true });

        expect(root.querySelector('img')).toBeNull();
        expect(root.querySelector('[data-replay-caption]').textContent).toBe('Rep not counted: <img src=x onerror=alert(1)>');
    });

    test('unreadable data shows the error instead of a player', () => {
        const error = vi.spyOn(console, 'error').mockImplementation(() => {});

        const broken = mount('{not json');
        expect(createPlayer(broken, { reduceMotion: true })).toBeNull();
        expect(broken.querySelector('[data-replay-error]').hidden).toBe(false);
        expect(error).toHaveBeenCalled();

        const empty = mount(replayData({ chunks: [] }));
        expect(createPlayer(empty, { reduceMotion: true })).toBeNull();
        expect(empty.querySelector('[data-replay-error]').hidden).toBe(false);
    });
});
