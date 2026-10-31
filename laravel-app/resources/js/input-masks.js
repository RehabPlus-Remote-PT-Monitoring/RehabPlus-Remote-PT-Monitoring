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

/*
 * Phone fields: the country <select> decides how many digits the number has.
 * The option's data-max, data-digits and data-example come from App\Helpers\PhoneNumber.
 *
 *   <div data-phone-field>
 *     <select data-phone-country>...</select>
 *     <input data-phone-number data-digits-only>
 *     <div data-phone-hint></div>
 *   </div>
 */

/** Limits the number to the selected country's length and updates the placeholder and hint. */
export function applyPhoneLimits(select, input, hint) {
    const option = select.selectedOptions[0];

    input.maxLength = Number(option.dataset.max);
    input.placeholder = option.dataset.example;

    if (hint) {
        hint.textContent = `Enter ${option.dataset.digits} without the country code.`;
    }
}
