/*
 * The therapist's appointment bell. The red number counts appointments they
 * haven't seen yet: opening the bell clears it, and it comes back only for a
 * new appointment. What's been seen is remembered in this browser.
 *
 *   <details data-appt-alerts data-seen-key="appt-alerts-seen:uid">
 *     <span data-appt-alerts-count hidden></span>
 *     <a data-appt-alert-id="abc">...</a>
 *   </details>
 */

function alertIds(bell) {
    return [...bell.querySelectorAll('[data-appt-alert-id]')].map((alert) => alert.dataset.apptAlertId);
}

function seenIds(key) {
    try {
        const seen = JSON.parse(localStorage.getItem(key));

        return Array.isArray(seen) ? seen : [];
    } catch {
        return []; // Storage is blocked or unreadable, so everything counts as new.
    }
}

/** Shows how many appointments haven't been seen, or nothing when all have. */
export function showUnseenCount(bell) {
    const seen = seenIds(bell.dataset.seenKey);
    const unseen = alertIds(bell).filter((id) => !seen.includes(id)).length;
    const count = bell.querySelector('[data-appt-alerts-count]');

    count.textContent = String(unseen);
    count.hidden = unseen === 0;
}

/** Remembers the listed appointments as seen and clears the number. */
export function markAlertsSeen(bell) {
    try {
        localStorage.setItem(bell.dataset.seenKey, JSON.stringify(alertIds(bell)));
    } catch {
        // Not remembered, so the number returns on the next page.
    }

    bell.querySelector('[data-appt-alerts-count]').hidden = true;
}

export function initAppointmentAlerts() {
    for (const bell of document.querySelectorAll('[data-appt-alerts]')) {
        showUnseenCount(bell);
        bell.addEventListener('toggle', () => {
            if (bell.open) {
                markAlertsSeen(bell);
            }
        });
    }
}
