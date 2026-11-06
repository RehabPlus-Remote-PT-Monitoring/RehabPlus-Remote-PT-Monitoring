/*
 * Success and error messages disappear on their own shortly after the page loads.
 * Add data-keep to an alert that has to stay, such as one standing in for page content.
 */

export const FLASH_VISIBLE_MS = 1000;
export const FLASH_FADE_MS = 200;

const FLASH_SELECTOR = '.alert-success:not([data-keep]), .alert-danger:not([data-keep])';

/** Fades out and removes every success and error message under root. */
export function dismissFlashMessages(root = document) {
    for (const message of root.querySelectorAll(FLASH_SELECTOR)) {
        setTimeout(() => {
            message.style.transition = `opacity ${FLASH_FADE_MS}ms`;
            message.style.opacity = '0';
            setTimeout(() => message.remove(), FLASH_FADE_MS);
        }, FLASH_VISIBLE_MS);
    }
}
