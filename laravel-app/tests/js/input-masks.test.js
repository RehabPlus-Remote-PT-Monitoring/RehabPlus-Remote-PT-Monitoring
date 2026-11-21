import { describe, expect, test } from 'vitest';
import {
    applyPhoneLimits,
    digitsOnly,
    keepDigitsOnly,
    keepPercent,
    PHONE_FORMAT_MESSAGE,
    phoneIsValid,
    refreshPhoneProblem,
    showPhoneCountry,
} from '../../resources/js/input-masks.js';

describe('keepPercent', () => {
    const typed = (value) => {
        const input = document.createElement('input');
        input.type = 'number';
        input.value = value;
        keepPercent(input);

        return input.value;
    };

    test('caps anything above 100', () => {
        expect(typed('101')).toBe('100');
        expect(typed('300000000000000000000')).toBe('100');
        expect(typed('1e5')).toBe('100');
    });

    test('keeps whole numbers from 0 to 100', () => {
        expect(typed('0')).toBe('0');
        expect(typed('85')).toBe('85');
        expect(typed('100')).toBe('100');
    });

    test('removes minus signs, decimals and leading zeros', () => {
        expect(typed('-5')).toBe('5');
        expect(typed('5.5')).toBe('5');
        expect(typed('007')).toBe('7');
    });

    test('leaves an empty box empty so it can be retyped', () => {
        expect(typed('')).toBe('');
    });
});

describe('phone field', () => {
    function field(value = '', iso = 'PH') {
        const root = document.createElement('div');
        root.innerHTML = `
            <span data-phone-code></span>
            <select data-phone-country>
                <option value="PH" data-dial="63" data-min="10" data-max="10" data-pattern="9\\d{9}|8(?:13|9[5-9])\\d{7}">+63 Philippines</option>
                <option value="NZ" data-dial="64" data-min="8" data-max="10">+64 New Zealand</option>
            </select>
            <div data-phone-box><input data-phone-number></div>
            <div data-phone-error hidden></div>
            <div data-phone-hint></div>`;
        root.querySelector('select').value = iso;
        root.querySelector('input').value = value;

        return root;
    }

    test('shows the short code and dial code of the selected country', () => {
        const root = field('', 'NZ');

        showPhoneCountry(root.querySelector('select'), root.querySelector('[data-phone-code]'));

        expect(root.querySelector('[data-phone-code]').textContent).toBe('NZ +64');
    });

    test('checks the length against the country', () => {
        const [ph] = field().querySelectorAll('option');

        expect(phoneIsValid(ph, '9171234567')).toBe(true);
        expect(phoneIsValid(ph, '917123')).toBe(false);
        expect(phoneIsValid(ph, '0917123456')).toBe(false);
    });

    test('a random number of the right length is not valid', () => {
        const [ph, nz] = field().querySelectorAll('option');

        expect(phoneIsValid(ph, '1234567890')).toBe(false);
        expect(phoneIsValid(ph, '5551234567')).toBe(false);
        expect(phoneIsValid(ph, '9999999999')).toBe(false);
        expect(phoneIsValid(ph, '9876543210')).toBe(false);
        expect(phoneIsValid(ph, '8131234567')).toBe(true);
        expect(phoneIsValid(ph, '9175550101')).toBe(true);
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
