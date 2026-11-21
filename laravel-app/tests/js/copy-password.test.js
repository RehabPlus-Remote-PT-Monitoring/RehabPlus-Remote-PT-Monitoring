import { afterEach, describe, expect, test, vi } from 'vitest';
import { copyPassword } from '../../resources/js/copy-password.js';

describe('copyPassword', () => {
    function panel() {
        document.body.innerHTML = `
            <div data-temporary-password>
                <code data-copy-source> StretchBalance4821 </code>
                <button data-copy-password>Copy</button>
            </div>`;

        return document.querySelector('[data-copy-password]');
    }

    afterEach(() => {
        vi.unstubAllGlobals();
        document.body.replaceChildren();
    });

    test('copies just the password and confirms on the button', async () => {
        const writeText = vi.fn().mockResolvedValue();
        vi.stubGlobal('navigator', { clipboard: { writeText } });
        const button = panel();

        await copyPassword(button);

        expect(writeText).toHaveBeenCalledWith('StretchBalance4821');
        expect(button.textContent).toBe('Copied');
    });

    test('says what to do when the browser refuses', async () => {
        vi.stubGlobal('navigator', { clipboard: { writeText: vi.fn().mockRejectedValue(new Error('denied')) } });
        const button = panel();

        await copyPassword(button);

        expect(button.textContent).toContain('Select the password');
    });
});
