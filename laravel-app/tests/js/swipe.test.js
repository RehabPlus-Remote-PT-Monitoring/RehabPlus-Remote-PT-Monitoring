import { describe, expect, test } from 'vitest';
import { dragOffset, swipeCloses, swipeGesture } from '../../resources/js/swipe.js';

describe('swipeGesture', () => {
    test('waits until the finger has moved about 10px', () => {
        expect(swipeGesture(0, 0)).toBe('wait');
        expect(swipeGesture(-9, 9)).toBe('wait');
    });

    test('mostly vertical movement is a scroll', () => {
        expect(swipeGesture(-10, 30)).toBe('scroll');
        expect(swipeGesture(3, -12)).toBe('scroll');
    });

    test('moving right is left to the browser', () => {
        expect(swipeGesture(15, 2)).toBe('scroll');
    });

    test('moving left is a swipe', () => {
        expect(swipeGesture(-15, 2)).toBe('swipe');
        expect(swipeGesture(-10, -10)).toBe('swipe');
    });
});

describe('dragOffset', () => {
    test('follows the finger to the left, but not past fully closed', () => {
        expect(dragOffset(-50, 280)).toBe(-50);
        expect(dragOffset(-400, 280)).toBe(-280);
    });

    test('resists when pulled right past the open edge', () => {
        expect(dragOffset(50, 280)).toBe(10);
    });
});

describe('swipeCloses', () => {
    test('dragging a third of the width closes, even slowly', () => {
        expect(swipeCloses(-100, 2000, 280)).toBe(true);
        expect(swipeCloses(-90, 2000, 280)).toBe(false);
    });

    test('a quick short flick closes', () => {
        expect(swipeCloses(-30, 100, 280)).toBe(true);
        expect(swipeCloses(-30, 1000, 280)).toBe(false);
    });

    test('never closes when let go at or right of the open edge', () => {
        expect(swipeCloses(0, 10, 280)).toBe(false);
        expect(swipeCloses(20, 10, 280)).toBe(false);
    });
});
