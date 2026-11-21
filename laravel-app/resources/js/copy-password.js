/*
 * The Copy button beside a temporary password:
 *
 *   <div data-temporary-password>
 *     <code data-copy-source>StretchBalance4821</code>
 *     <button data-copy-password>Copy</button>
 *   </div>
 */

/** Copies the password and says so on the button. If the browser refuses, the button says what to do instead. */
export async function copyPassword(button) {
    const source = button.closest('[data-temporary-password]').querySelector('[data-copy-source]');

    try {
        await navigator.clipboard.writeText(source.textContent.trim());
        button.textContent = 'Copied';
    } catch (error) {
        button.textContent = "Couldn't copy. Select the password instead.";
    }
}
