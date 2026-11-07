/*
 * Add time off on the Staff Schedule page:
 *
 *   <select data-time-off-type>    the Time dropdown only applies to "Specific time"
 *   <select data-time-off-time>
 *
 * And on any page:
 *
 *   <input type="date" data-calendar-only>   picked from the calendar, not typed
 *
 * The server still checks every value, so this only guides the person filling it in.
 */

/** Turns the Time dropdown on for "Specific time", and off and empty for a full day. */
export function applyTimeOffType(typeSelect) {
    const time = typeSelect.form?.querySelector('[data-time-off-time]');
    if (!time) {
        return;
    }

    const specific = typeSelect.value === 'Specific time';
    time.disabled = !specific;
    time.required = specific;
    if (!specific) {
        time.value = '';
    }
}

/** Opens the calendar. Older browsers without showPicker still have the calendar icon. */
export function openCalendar(input) {
    try {
        input.showPicker?.();
    } catch {
        // The browser refused; the calendar icon still works.
    }
}

/** Stops typing in the date box. Tab still moves on; Enter and Space open the calendar. */
export function handleCalendarKey(event) {
    if (event.key === 'Tab') {
        return;
    }

    event.preventDefault();
    if (event.key === 'Enter' || event.key === ' ') {
        openCalendar(event.target);
    }
}

export function initScheduleForm() {
    document.querySelectorAll('[data-time-off-type]').forEach(applyTimeOffType);

    document.addEventListener('change', (event) => {
        if (event.target.matches?.('[data-time-off-type]')) {
            applyTimeOffType(event.target);
        }
    });

    document.addEventListener('click', (event) => {
        if (event.target.matches?.('[data-calendar-only]')) {
            openCalendar(event.target);
        }
    });

    document.addEventListener('keydown', (event) => {
        if (event.target.matches?.('[data-calendar-only]')) {
            handleCalendarKey(event);
        }
    });
}
