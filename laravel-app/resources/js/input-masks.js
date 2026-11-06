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
 *   <div data-phone-group>
 *     <span data-phone-iso></span>
 *     <select data-phone-country>...</select>
 *     <div data-phone-box>
 *       <span data-phone-dial></span>
 *       <input data-phone-number data-digits-only>
 *     </div>
 *     <div data-phone-error hidden></div>
 *     <div data-phone-hint></div>
 *   </div>
 */

export const PHONE_FORMAT_MESSAGE = 'This phone number is either invalid or in the wrong format.';

/** Shows the selected country's short code on the picker and its dial code in the number box. */
export function showPhoneCountry(select, iso, dial) {
    const option = select.selectedOptions[0];

    iso.textContent = option.value;
    dial.textContent = `+${option.dataset.dial}`;
}

/** Whether the number has the right length for the country. Empty is fine: "required" handles that. */
export function phoneIsValid(option, number) {
    if (number === '') {
        return true;
    }

    // No leading 0: the country code replaces it, and a text can't reach the number with both.
    return /^[1-9]\d*$/.test(number)
        && number.length >= Number(option.dataset.min)
        && number.length <= Number(option.dataset.max);
}

/** Shows the error under the field when the number is wrong, and the hint when it isn't. */
export function refreshPhoneProblem(field) {
    const select = field.querySelector('[data-phone-country]');
    const valid = phoneIsValid(select.selectedOptions[0], field.querySelector('[data-phone-number]').value);
    const error = field.querySelector('[data-phone-error]');

    field.querySelector('[data-phone-box]').classList.toggle('is-invalid', !valid);
    field.querySelector('[data-phone-hint]').hidden = !valid;
    error.hidden = valid;
    error.textContent = valid ? '' : PHONE_FORMAT_MESSAGE;
}

/** Limits the number to the selected country's length and updates the placeholder and hint. */
export function applyPhoneLimits(select, input, hint) {
    const option = select.selectedOptions[0];

    input.maxLength = Number(option.dataset.max);
    input.placeholder = option.dataset.example;

    if (hint) {
        hint.textContent = `Enter ${option.dataset.digits} without the country code.`;
    }
}
