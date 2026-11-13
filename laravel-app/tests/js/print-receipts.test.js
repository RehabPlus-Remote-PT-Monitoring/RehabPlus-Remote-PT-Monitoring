import { beforeEach, describe, expect, test, vi } from 'vitest';
import { printReceipts } from '../../resources/js/print-receipts.js';

describe('printReceipts', () => {
    const shown = () => [...document.querySelectorAll('[data-receipt]')].filter((r) => !r.hidden).map((r) => r.id);

    beforeEach(() => {
        document.body.className = '';
        document.body.innerHTML = '<article id="r1" data-receipt></article><article id="r2" data-receipt></article>';
        window.print = vi.fn();
    });

    test('one payment prints only its own receipt', () => {
        printReceipts('r2');

        expect(shown()).toEqual(['r2']);
        expect(window.print).toHaveBeenCalledOnce();
    });

    test('printing all shows every receipt, even after printing one', () => {
        printReceipts('r2');
        printReceipts();

        expect(shown()).toEqual(['r1', 'r2']);
    });

    test('the page goes back to normal after printing', () => {
        printReceipts();
        expect(document.body.classList.contains('printing-receipts')).toBe(true);

        window.dispatchEvent(new Event('afterprint'));
        expect(document.body.classList.contains('printing-receipts')).toBe(false);
    });
});
