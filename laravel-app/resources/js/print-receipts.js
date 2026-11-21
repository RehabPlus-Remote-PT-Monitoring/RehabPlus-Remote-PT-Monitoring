/*
 * Prints receipts instead of the whole page:
 *
 *   <button data-print>                                prints every receipt, one per page
 *   <button data-print data-print-receipt="receipt-1"> prints just that one
 *   <article class="receipt" id="receipt-1" data-receipt>
 *
 * The styles in rehabplus-dashboard.css hide everything else while body has
 * the printing-receipts class. Ctrl+P still prints the page as it is.
 */
export function printReceipts(onlyId) {
    for (const receipt of document.querySelectorAll('[data-receipt]')) {
        receipt.hidden = Boolean(onlyId) && receipt.id !== onlyId;
    }

    document.body.classList.add('printing-receipts');
    window.addEventListener('afterprint', () => document.body.classList.remove('printing-receipts'), { once: true });
    window.print();
}
