import { describe, expect, test, vi } from 'vitest';
import { applyTimeOffType, handleCalendarKey } from '../../resources/js/schedule-form.js';

function timeOffForm(type = 'Full day') {
    const form = document.createElement('form');
    form.innerHTML = `
        <select data-time-off-type>
            <option value="Full day">Full day</option>
            <option value="Specific time">Specific time</option>
        </select>
        <select data-time-off-time>
            <option value="">Select time</option>
            <option value="09:00 - 13:00">09:00 - 13:00</option>
        </select>`;
    form.querySelector('[data-time-off-type]').value = type;

    return { type: form.querySelector('[data-time-off-type]'), time: form.querySelector('[data-time-off-time]') };
}

describe('applyTimeOffType', () => {
    test('a specific time needs the Time dropdown', () => {
        const { type, time } = timeOffForm('Specific time');
        applyTimeOffType(type);

        expect(time.disabled).toBe(false);
        expect(time.required).toBe(true);
    });

    test('a full day turns it off and clears it', () => {
        const { type, time } = timeOffForm('Specific time');
        applyTimeOffType(type);
        time.value = '09:00 - 13:00';

        type.value = 'Full day';
        applyTimeOffType(type);

        expect(time.disabled).toBe(true);
        expect(time.required).toBe(false);
        expect(time.value).toBe('');
    });
});

describe('handleCalendarKey', () => {
    const press = (key) => {
        const input = document.createElement('input');
        input.showPicker = vi.fn();
        const event = { key, target: input, preventDefault: vi.fn() };
        handleCalendarKey(event);

        return { typed: !event.preventDefault.mock.calls.length, opened: input.showPicker.mock.calls.length > 0 };
    };

    test('digits and letters cannot be typed', () => {
        expect(press('5')).toEqual({ typed: false, opened: false });
        expect(press('a')).toEqual({ typed: false, opened: false });
    });

    test('Tab still moves to the next field', () => {
        expect(press('Tab')).toEqual({ typed: true, opened: false });
    });

    test('Enter and Space open the calendar', () => {
        expect(press('Enter').opened).toBe(true);
        expect(press(' ').opened).toBe(true);
    });
});
