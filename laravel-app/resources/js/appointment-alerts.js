/*
 * The bell at the top of the dashboard. The red number is the notices not yet
 * opened (data-notice-count, from the server) plus the appointments not seen
 * yet. Opening the bell clears the appointment part only; a notice clears when
 * it's clicked. What's been seen is remembered in this browser.
 *
 *   <details data-appt-alerts data-notice-count="2" data-seen-key="appt-alerts-seen:uid">
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

/** Shows the notices not yet opened plus the appointments not yet seen, or nothing when there are none. */
export function showUnseenCount(bell) {
    const seen = seenIds(bell.dataset.seenKey);
    const unseenAppointments = alertIds(bell).filter((id) => !seen.includes(id)).length;
    const notices = Number(bell.dataset.noticeCount || 0);
    const total = notices + unseenAppointments;
    const count = bell.querySelector('[data-appt-alerts-count]');

    count.textContent = String(total);
    count.hidden = total === 0;
}

/** Remembers the listed appointments as seen. Notices stay counted until they're opened. */
export function markAlertsSeen(bell) {
    try {
        localStorage.setItem(bell.dataset.seenKey, JSON.stringify(alertIds(bell)));
    } catch {
        // Not remembered, so the number returns on the next page.
    }

    showUnseenCount(bell);
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
