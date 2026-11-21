import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { dismissFlashMessages, FLASH_FADE_MS, FLASH_VISIBLE_MS } from '../../resources/js/flash-messages.js';

describe('dismissFlashMessages', () => {
    beforeEach(() => {
        vi.useFakeTimers();
        document.body.innerHTML = `
            <div id="success" class="alert alert-success">Saved</div>
            <div id="error" class="alert alert-danger">Failed</div>
            <div id="info" class="alert alert-info">No patients yet</div>
            <div id="kept" class="alert alert-danger" data-keep>Could not load</div>`;
    });

    afterEach(() => {
        vi.useRealTimers();
        document.body.replaceChildren();
    });

    test('stays visible for one second', () => {
        dismissFlashMessages();

        vi.advanceTimersByTime(FLASH_VISIBLE_MS - 1);

        expect(FLASH_VISIBLE_MS).toBe(1000);
        expect(document.getElementById('success').style.opacity).toBe('');
    });

    test('removes success and error messages after the fade', () => {
        dismissFlashMessages();

        vi.advanceTimersByTime(FLASH_VISIBLE_MS + FLASH_FADE_MS);

        expect(document.getElementById('success')).toBeNull();
        expect(document.getElementById('error')).toBeNull();
    });

    test('leaves info notes and data-keep alerts in place', () => {
        dismissFlashMessages();

        vi.advanceTimersByTime(FLASH_VISIBLE_MS + FLASH_FADE_MS);

        expect(document.getElementById('info')).not.toBeNull();
        expect(document.getElementById('kept')).not.toBeNull();
    });
});
