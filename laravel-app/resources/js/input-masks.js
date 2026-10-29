/*
 * Keeps a field to digits only (see the input handler in rehabplus-dashboard.js):
 *
 *   <input data-digits-only>   letters and symbols are removed as they're typed or pasted
 *
 * The server still validates the field, so this only saves a round trip.
 */

/** The input's value with everything except 0-9 removed. */
export function digitsOnly(value) {
    return value.replace(/\D/g, '');
}

/** Rewrites the input's value in place when it has any non-digit characters. */
export function keepDigitsOnly(input) {
    const digits = digitsOnly(input.value);

    if (input.value !== digits) {
        input.value = digits;
    }
}
