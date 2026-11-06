import { describe, expect, test } from 'vitest';
import {
    applyPhoneLimits,
    digitsOnly,
    keepDigitsOnly,
    PHONE_FORMAT_MESSAGE,
    phoneIsValid,
    refreshPhoneProblem,
    showPhoneCountry,
} from '../../resources/js/input-masks.js';

describe('phone field', () => {
    function field(value = '', iso = 'PH') {
        const root = document.createElement('div');
        root.innerHTML = `
            <span data-phone-iso></span>
            <select data-phone-country>
                <option value="PH" data-dial="63" data-min="10" data-max="10">+63 Philippines</option>
                <option value="NZ" data-dial="64" data-min="8" data-max="10">+64 New Zealand</option>
            </select>
            <div data-phone-box><span data-phone-dial></span><input data-phone-number></div>
            <div data-phone-error hidden></div>
            <div data-phone-hint></div>`;
        root.querySelector('select').value = iso;
        root.querySelector('input').value = value;

        return root;
    }

    test('shows the short code and dial code of the selected country', () => {
        const root = field('', 'NZ');

        showPhoneCountry(root.querySelector('select'), root.querySelector('[data-phone-iso]'), root.querySelector('[data-phone-dial]'));

        expect(root.querySelector('[data-phone-iso]').textContent).toBe('NZ');
        expect(root.querySelector('[data-phone-dial]').textContent).toBe('+64');
    });

    test('checks the length against the country', () => {
        const [ph, nz] = field().querySelectorAll('option');

        expect(phoneIsValid(ph, '9171234567')).toBe(true);
        expect(phoneIsValid(ph, '917123')).toBe(false);
        expect(phoneIsValid(ph, '0917123456')).toBe(false);
        expect(phoneIsValid(nz, '21234567')).toBe(true);
        expect(phoneIsValid(ph, '')).toBe(true);
    });

    test('a wrong number shows the error instead of the hint', () => {
        const root = field('917');

        refreshPhoneProblem(root);

        expect(root.querySelector('[data-phone-box]').classList.contains('is-invalid')).toBe(true);
        expect(root.querySelector('[data-phone-error]').hidden).toBe(false);
        expect(root.querySelector('[data-phone-error]').textContent).toBe(PHONE_FORMAT_MESSAGE);
        expect(root.querySelector('[data-phone-hint]').hidden).toBe(true);
    });

    test('correcting the number clears the error', () => {
        const root = field('917');
        refreshPhoneProblem(root);

        root.querySelector('input').value = '9171234567';
        refreshPhoneProblem(root);

        expect(root.querySelector('[data-phone-box]').classList.contains('is-invalid')).toBe(false);
        expect(root.querySelector('[data-phone-error]').hidden).toBe(true);
        expect(root.querySelector('[data-phone-hint]').hidden).toBe(false);
    });
});

describe('digitsOnly', () => {
    test('keeps only 0-9', () => {
        expect(digitsOnly('0917-555 0101')).toBe('09175550101');
        expect(digitsOnly('+63 (917) abc')).toBe('63917');
    });

    test('leaves an all-digit value alone', () => {
        expect(digitsOnly('09175550101')).toBe('09175550101');
    });
});

describe('keepDigitsOnly', () => {
    test('rewrites the input value without letters', () => {
        const input = document.createElement('input');
        input.value = '09a17b';

        keepDigitsOnly(input);

        expect(input.value).toBe('0917');
    });
});

describe('applyPhoneLimits', () => {
    function phoneField(selectedIso) {
        const select = document.createElement('select');
        for (const [iso, max, digits, example] of [
            ['PH', 10, '10 digits', '9171234567'],
            ['AU', 9, '9 digits', '412345678'],
        ]) {
            const option = new Option(iso, iso);
            Object.assign(option.dataset, { max: String(max), digits, example });
            select.append(option);
        }
        select.value = selectedIso;

        const input = document.createElement('input');
        const hint = document.createElement('div');

        return { select, input, hint };
    }

    test('sets the length, placeholder and hint for the selected country', () => {
        const { select, input, hint } = phoneField('AU');

        applyPhoneLimits(select, input, hint);

        expect(input.maxLength).toBe(9);
        expect(input.placeholder).toBe('412345678');
        expect(hint.textContent).toBe('Enter 9 digits without the country code.');
    });

    test('follows the country when it changes', () => {
        const { select, input, hint } = phoneField('PH');
        applyPhoneLimits(select, input, hint);
        expect(input.maxLength).toBe(10);

        select.value = 'AU';
        applyPhoneLimits(select, input, hint);

        expect(input.maxLength).toBe(9);
        expect(input.placeholder).toBe('412345678');
    });
});
