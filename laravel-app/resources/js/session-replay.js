/**
 * Movement replay player (patients/replay.blade.php): plays a session's saved
 * pose points as a stick figure on a canvas. The data comes from a
 * <script type="application/json"> block (CSP-safe: no inline code); the
 * decoding and maths live in replay-format.js.
 *
 * Controls (built here): play/pause, speed 0.5x/1x/2x, a scrubber with the
 * session's rep events as coloured markers, time and angle readouts.
 * Keyboard on the player: Space plays/pauses, Left/Right step one frame.
 * The server-rendered event list (buttons with data-replay-seek) jumps there.
 * Under prefers-reduced-motion nothing starts by itself.
 */
import {
    BONES, FACE_LANDMARKS, HEAD,
    decodeChunks, formatAngle, formatTime, frameIndexAt, isOutOfFrame, isVisible,
    letterbox, markerPercent, recentEvent, toCanvas,
} from './replay-format.js';

const SPEEDS = [0.5, 1, 2];

/** Longest step one animation tick may advance: a tab coming back from the background doesn't jump ahead. */
const MAX_TICK_MS = 250;

export const EVENT_LABELS = { counted: 'Rep counted', rejected: 'Rep not counted', hold: 'Hold' };

/** "Rep not counted: knees too far forward" (label plus the note the patient saw, if any). */
export function eventText(event) {
    const label = EVENT_LABELS[event.kind] ?? event.kind;
    return event.note ? `${label}: ${event.note}` : label;
}

function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) {
        node.className = className;
    }
    if (text !== undefined) {
        node.textContent = text; // never innerHTML: notes come from the patient's phone
    }
    return node;
}

/** Drawing colours from the theme's CSS variables, so light and dark mode both read well. */
function themeColours(stage) {
    const style = getComputedStyle(stage);
    const read = (name, fallback) => style.getPropertyValue(name).trim() || fallback;
    return {
        box: read('--replay-box', '#f1f5f9'),
        bone: read('--replay-bone', '#0d9488'),
        joint: read('--replay-joint', '#0f766e'),
    };
}

/**
 * Build one player inside root ([data-replay]). Returns a small API (used by
 * tests and the keyboard handler); null when the data block is missing or
 * holds no frames.
 */
export function createPlayer(root, { reduceMotion = false } = {}) {
    const dataBlock = root.querySelector('script[type="application/json"][data-replay-data]');
    let data;
    let frames;
    try {
        data = JSON.parse(dataBlock?.textContent ?? 'null');
        frames = data ? decodeChunks(data.chunks ?? []) : [];
    } catch (error) {
        // Logged, not swallowed: the page shows the fallback message instead.
        console.error('Replay data could not be read', error);
        frames = [];
    }
    if (!data || frames.length === 0) {
        root.querySelector('[data-replay-error]')?.removeAttribute('hidden');
        return null;
    }

    const events = Array.isArray(data.events) ? data.events : [];
    const durationMs = frames[frames.length - 1].t;
    const stage = root.querySelector('.replay-stage');
    const canvas = root.querySelector('canvas');
    const overlay = root.querySelector('[data-replay-out-of-frame]');
    const caption = root.querySelector('[data-replay-caption]');
    const ctx = canvas.getContext ? canvas.getContext('2d') : null;

    const state = { time: 0, playing: false, speed: 1, shownIndex: -1, lastTick: null, raf: null };

    // ---- controls ---------------------------------------------------------

    const controls = root.querySelector('[data-replay-controls]');
    const playButton = el('button', 'btn btn-primary replay-play');
    playButton.type = 'button';

    const speedGroup = el('div', 'btn-group replay-speeds');
    speedGroup.setAttribute('role', 'group');
    speedGroup.setAttribute('aria-label', 'Playback speed');
    const speedButtons = SPEEDS.map((speed) => {
        const button = el('button', 'btn btn-outline-primary btn-sm', `${speed}×`);
        button.type = 'button';
        button.dataset.speed = String(speed);
        button.addEventListener('click', () => setSpeed(speed));
        speedGroup.append(button);
        return button;
    });

    const timeReadout = el('span', 'replay-time');
    const angleReadout = el('span', 'replay-angle');

    const track = el('div', 'replay-track');
    const markers = el('div', 'replay-markers');
    for (const event of events) {
        const marker = el('button', `replay-marker replay-marker--${event.kind}`);
        marker.type = 'button';
        marker.tabIndex = -1; // the event list below is the keyboard route; 200 tab stops here would be a trap
        marker.title = `${formatTime(event.t)} · ${eventText(event)}`;
        marker.setAttribute('aria-label', marker.title);
        marker.style.left = `${markerPercent(event.t, durationMs)}%`;
        marker.addEventListener('click', () => seek(event.t));
        markers.append(marker);
    }
    const scrubber = el('input', 'form-range replay-scrubber');
    scrubber.type = 'range';
    scrubber.min = '0';
    scrubber.max = String(durationMs);
    scrubber.step = '1';
    scrubber.setAttribute('aria-label', 'Position in the session');
    scrubber.addEventListener('input', () => seek(Number(scrubber.value)));
    track.append(markers, scrubber);

    const buttons = el('div', 'replay-buttons');
    buttons.append(playButton, speedGroup, timeReadout, angleReadout);
    controls.replaceChildren(buttons, track);

    playButton.addEventListener('click', () => toggle());

    root.querySelectorAll('[data-replay-seek]').forEach((button) => {
        button.addEventListener('click', () => {
            seek(Number(button.dataset.replaySeek));
            canvas.scrollIntoView?.({ block: 'nearest' });
        });
    });

    root.addEventListener('keydown', onKey);

    // ---- drawing ----------------------------------------------------------

    function resizeCanvas() {
        const ratio = window.devicePixelRatio || 1;
        const width = Math.max(1, Math.round(canvas.clientWidth * ratio));
        const height = Math.max(1, Math.round(canvas.clientHeight * ratio));
        if (canvas.width !== width || canvas.height !== height) {
            canvas.width = width;
            canvas.height = height;
        }
        draw();
    }

    function draw() {
        const index = frameIndexAt(frames, state.time);
        const frame = frames[index];
        state.shownIndex = index;
        overlay.hidden = !isOutOfFrame(frame);
        if (!ctx) {
            return;
        }

        const colours = themeColours(stage);
        const box = letterbox(canvas.width, canvas.height, data.aspect);
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.fillStyle = colours.box;
        ctx.fillRect(box.x, box.y, box.width, box.height);
        if (isOutOfFrame(frame)) {
            return;
        }

        const point = (i) => (isVisible(frame.points[i]) ? toCanvas(frame.points[i], box, data.mirrored) : null);
        const line = Math.max(2, box.width * 0.012);

        ctx.strokeStyle = colours.bone;
        ctx.lineWidth = line;
        ctx.lineCap = 'round';
        for (const [a, b] of BONES) {
            const p1 = point(a);
            const p2 = point(b);
            if (p1 && p2) {
                ctx.beginPath();
                ctx.moveTo(p1.x, p1.y);
                ctx.lineTo(p2.x, p2.y);
                ctx.stroke();
            }
        }

        ctx.fillStyle = colours.joint;
        frame.points.forEach((_, i) => {
            const p = FACE_LANDMARKS.has(i) ? null : point(i);
            if (p) {
                ctx.beginPath();
                ctx.arc(p.x, p.y, line * 1.2, 0, Math.PI * 2);
                ctx.fill();
            }
        });

        // A ring at the nose so the figure has a head (the app draws no face dots).
        const head = point(HEAD);
        if (head) {
            ctx.beginPath();
            ctx.arc(head.x, head.y, line * 3, 0, Math.PI * 2);
            ctx.stroke();
        }
    }

    function render() {
        // Frames are at most 10 per second: only redraw the canvas when the frame changes.
        const index = frameIndexAt(frames, state.time);
        if (index !== state.shownIndex) {
            draw();
        }
        const frame = frames[index];
        scrubber.value = String(Math.round(state.time));
        timeReadout.textContent = `${formatTime(state.time)} / ${formatTime(durationMs)}`;
        angleReadout.textContent = `${data.angleLabel}: ${formatAngle(frame.angle)}`;
        const event = recentEvent(events, state.time);
        caption.textContent = event ? eventText(event) : '';
        caption.dataset.kind = event ? event.kind : '';
        playButton.textContent = state.playing ? 'Pause' : 'Play';
        playButton.setAttribute('aria-pressed', String(state.playing));
        speedButtons.forEach((b) => {
            const chosen = Number(b.dataset.speed) === state.speed;
            b.setAttribute('aria-pressed', String(chosen));
            b.classList.toggle('active', chosen); // Bootstrap's filled look for the chosen speed
        });
    }

    // ---- playback ---------------------------------------------------------

    function tick(now) {
        if (!state.playing) {
            return;
        }
        if (state.lastTick !== null) {
            state.time += Math.min(MAX_TICK_MS, now - state.lastTick) * state.speed;
        }
        state.lastTick = now;
        if (state.time >= durationMs) {
            state.time = durationMs;
            state.playing = false;
        }
        render();
        if (state.playing) {
            state.raf = requestAnimationFrame(tick);
        }
    }

    function play() {
        if (state.time >= durationMs) {
            state.time = 0; // Play at the end starts again
        }
        state.playing = true;
        state.lastTick = null;
        render();
        state.raf = requestAnimationFrame(tick);
    }

    function pause() {
        state.playing = false;
        if (state.raf !== null) {
            cancelAnimationFrame(state.raf);
            state.raf = null;
        }
        render();
    }

    function toggle() {
        state.playing ? pause() : play();
    }

    function seek(ms) {
        state.time = Math.min(durationMs, Math.max(0, ms));
        state.lastTick = null;
        render();
    }

    function step(delta) {
        pause();
        const index = Math.min(frames.length - 1, Math.max(0, frameIndexAt(frames, state.time) + delta));
        seek(frames[index].t);
    }

    function setSpeed(speed) {
        state.speed = speed;
        render();
    }

    function onKey(event) {
        const onButton = event.target instanceof HTMLButtonElement;
        if (event.key === ' ' && !onButton) {
            // Buttons already activate on Space; everywhere else in the player it plays/pauses.
            event.preventDefault();
            toggle();
        } else if (event.key === 'ArrowRight' || event.key === 'ArrowLeft') {
            event.preventDefault(); // the scrubber would otherwise move by 1 ms
            step(event.key === 'ArrowRight' ? 1 : -1);
        }
    }

    // ---- start ------------------------------------------------------------

    if (typeof ResizeObserver === 'function') {
        new ResizeObserver(resizeCanvas).observe(canvas);
    }
    // The theme is a class on <html> (the top bar's toggle): redraw in the new colours.
    if (typeof MutationObserver === 'function') {
        new MutationObserver(draw).observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });
    }
    resizeCanvas();
    render();
    if (!reduceMotion) {
        play();
    }

    return {
        frames, events, durationMs,
        get time() { return state.time; },
        get playing() { return state.playing; },
        get speed() { return state.speed; },
        play, pause, toggle, seek, step, setSpeed,
    };
}

/** Every player on the page. */
export function initReplayPlayers(doc = document) {
    const reduceMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;
    return [...doc.querySelectorAll('[data-replay]')].map((root) => createPlayer(root, { reduceMotion }));
}

initReplayPlayers();
