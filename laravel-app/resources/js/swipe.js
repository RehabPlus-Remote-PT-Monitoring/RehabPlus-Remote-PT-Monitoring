/*
 * Swipe-to-close math for the phone menu (see rehabplus-dashboard.js).
 * Pure functions: numbers in, decision out, so they're easy to test.
 */

// A touch must move this far (px) before it counts as a swipe or a scroll.
const SLOP_PX = 10;
// Dragging the drawer at least this share of its width closes it...
const CLOSE_SHARE = 1 / 3;
// ...and so does a quick leftward flick faster than this (px per ms).
const FLICK_PX_PER_MS = 0.11;
// Pulled right past the open edge, the drawer moves this much per px (resists).
const OVERPULL = 0.2;

/**
 * What an undecided touch on the drawer is, from how far it has moved:
 * 'wait' (too small to tell), 'scroll' (mostly vertical, or to the right;
 * leave it to the browser) or 'swipe' (leftward: track it).
 */
export function swipeGesture(dx, dy) {
    if (Math.abs(dx) < SLOP_PX && Math.abs(dy) < SLOP_PX) {
        return 'wait';
    }
    if (Math.abs(dy) > Math.abs(dx)) {
        return 'scroll';
    }
    return dx > 0 ? 'scroll' : 'swipe';
}

/** Where the drawer sits for a finger that moved dx px: never past fully closed, resisting past open. */
export function dragOffset(dx, width) {
    return dx > 0 ? dx * OVERPULL : Math.max(dx, -width);
}

/** Whether letting go after dragging dx px over elapsedMs closes the drawer. */
export function swipeCloses(dx, elapsedMs, width) {
    if (dx >= 0) {
        return false;
    }
    return dx < -width * CLOSE_SHARE || -dx / elapsedMs > FLICK_PX_PER_MS;
}
