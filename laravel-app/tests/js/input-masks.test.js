import { describe, expect, test } from 'vitest';
import { digitsOnly, keepDigitsOnly } from '../../resources/js/input-masks.js';

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
