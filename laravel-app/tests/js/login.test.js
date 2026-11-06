// Behaviour tests for resources/js/rehabplus-login.js (login and
// forgot-password pages) in a fake browser (jsdom).
import { afterEach, describe, expect, test, vi } from 'vitest';

async function loadPage(html) {
    document.body.innerHTML = html;
    vi.resetModules(); // the script wires itself up on import
    await import('../../resources/js/rehabplus-login.js');
}

afterEach(() => {
    vi.useRealTimers();
});

describe('show / hide password', () => {
    const page = `
        <input id="passwordInput" type="password">
        <span id="passwordToggle" tabindex="0"><i id="eyeIcon" class="bi bi-eye"></i></span>`;

    test('clicking toggles between hidden and shown', async () => {
        await loadPage(page);
        const input = document.getElementById('passwordInput');
        const icon = document.getElementById('eyeIcon');

        document.getElementById('passwordToggle').click();
        expect(input.type).toBe('text');
        expect(icon.classList.contains('bi-eye-slash')).toBe(true);

        document.getElementById('passwordToggle').click();
        expect(input.type).toBe('password');
        expect(icon.classList.contains('bi-eye')).toBe(true);
    });

    test('Enter and Space toggle it from the keyboard; other keys do not', async () => {
        await loadPage(page);
        const toggle = document.getElementById('passwordToggle');
        const input = document.getElementById('passwordInput');

        const enter = new KeyboardEvent('keydown', { key: 'Enter', cancelable: true });
        toggle.dispatchEvent(enter);
        expect(input.type).toBe('text');
        expect(enter.defaultPrevented).toBe(true);

        toggle.dispatchEvent(new KeyboardEvent('keydown', { key: ' ' }));
        expect(input.type).toBe('password');

        toggle.dispatchEvent(new KeyboardEvent('keydown', { key: 'a' }));
        expect(input.type).toBe('password');
    });

    test('does nothing if the password field is missing', async () => {
        await loadPage('<span id="passwordToggle"></span>');
        expect(() => document.getElementById('passwordToggle').click()).not.toThrow();
    });
});

describe('resend code countdown', () => {
    test('counts down each second, then enables the button', async () => {
        vi.useFakeTimers();
        await loadPage('<button id="resendButton" data-resend-in="2">Resend code</button>');
        const button = document.getElementById('resendButton');

        expect(button.disabled).toBe(true);
        expect(button.textContent).toBe('Resend in 2s');
        vi.advanceTimersByTime(1000);
        expect(button.textContent).toBe('Resend in 1s');
        vi.advanceTimersByTime(1000);
        expect(button.disabled).toBe(false);
        expect(button.textContent).toBe('Resend code');
    });

    test('is enabled straight away when there is no cooldown', async () => {
        await loadPage('<button id="resendButton" data-resend-in="">Resend code</button>');
        expect(document.getElementById('resendButton').disabled).toBe(false);
    });
});
