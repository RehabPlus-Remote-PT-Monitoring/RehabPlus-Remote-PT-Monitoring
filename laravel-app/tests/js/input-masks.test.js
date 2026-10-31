import { describe, expect, test } from 'vitest';
import { applyPhoneLimits, digitsOnly, keepDigitsOnly } from '../../resources/js/input-masks.js';

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
