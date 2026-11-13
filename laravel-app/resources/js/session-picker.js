/*
 * Session dropdown on the billing form: lists the session types of the patient
 * chosen in the dropdown before it.
 *
 *   <form>
 *     <select data-session-patient>
 *       <option value="Emily Johnson" data-sessions='["Knee rehab"]'>
 *     <select data-session-select data-selected="Knee rehab">
 *   </form>
 */

function addOption(select, value, label) {
    const option = document.createElement('option');
    option.value = value;
    option.textContent = label;
    select.append(option);
}

/** Lists the chosen patient's sessions, selecting `selected` when it is one of them. */
export function fillSessions(patientSelect, sessionSelect, selected = '') {
    const hasPatient = patientSelect.value !== '';
    const sessions = hasPatient ? JSON.parse(patientSelect.selectedOptions[0].dataset.sessions) : [];

    sessionSelect.replaceChildren();
    addOption(sessionSelect, '', hasPatient ? 'Select session' : 'Select a patient first');
    sessions.forEach((session) => addOption(sessionSelect, session, session));

    sessionSelect.value = sessions.includes(selected) ? selected : '';
    sessionSelect.disabled = !hasPatient;
}

function sessionSelectFor(patientSelect) {
    return patientSelect.form?.querySelector('[data-session-select]');
}

export function initSessionPickers() {
    // After a failed save, the patient and session come back already chosen.
    for (const patientSelect of document.querySelectorAll('[data-session-patient]')) {
        const sessionSelect = sessionSelectFor(patientSelect);
        if (sessionSelect) {
            fillSessions(patientSelect, sessionSelect, sessionSelect.dataset.selected);
        }
    }

    document.addEventListener('change', (event) => {
        if (event.target.matches?.('[data-session-patient]')) {
            const sessionSelect = sessionSelectFor(event.target);
            if (sessionSelect) {
                fillSessions(event.target, sessionSelect);
            }
        }
    });
}
