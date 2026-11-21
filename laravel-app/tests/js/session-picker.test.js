import { describe, expect, test } from 'vitest';
import { fillSessions, initSessionPickers } from '../../resources/js/session-picker.js';

function billingForm(selected = '') {
    const form = document.createElement('form');
    form.innerHTML = `
        <select data-session-patient>
            <option value="">Select patient</option>
            <option value="Emily Johnson" data-sessions='["Knee rehab","Massage"]'>Emily Johnson</option>
            <option value="Mark Reyes" data-sessions='["Stretching"]'>Mark Reyes</option>
        </select>
        <select data-session-select data-selected="${selected}" disabled></select>`;
    document.body.replaceChildren(form);

    return {
        patient: form.querySelector('[data-session-patient]'),
        session: form.querySelector('[data-session-select]'),
    };
}

const labels = (select) => [...select.options].map((option) => option.textContent);

describe('fillSessions', () => {
    test('stays disabled until a patient is chosen', () => {
        const { patient, session } = billingForm();
        fillSessions(patient, session);

        expect(labels(session)).toEqual(['Select a patient first']);
        expect(session.disabled).toBe(true);
    });

    test('lists only the chosen patient\'s sessions', () => {
        const { patient, session } = billingForm();
        patient.value = 'Emily Johnson';
        fillSessions(patient, session);

        expect(labels(session)).toEqual(['Select session', 'Knee rehab', 'Massage']);
        expect(session.value).toBe('');
        expect(session.disabled).toBe(false);
    });

    test('session text is never treated as HTML', () => {
        const { patient, session } = billingForm();
        patient.options[1].dataset.sessions = JSON.stringify(['<b>Rehab</b>']);
        patient.value = 'Emily Johnson';
        fillSessions(patient, session);

        expect(session.options[1].textContent).toBe('<b>Rehab</b>');
        expect(session.querySelector('b')).toBeNull();
    });
});

describe('initSessionPickers', () => {
    test('restores the choice after a failed save, and changing patient clears it', () => {
        const { patient, session } = billingForm('Massage');
        patient.value = 'Emily Johnson';

        initSessionPickers();
        expect(session.value).toBe('Massage');

        patient.value = 'Mark Reyes';
        patient.dispatchEvent(new Event('change', { bubbles: true }));
        expect(labels(session)).toEqual(['Select session', 'Stretching']);
        expect(session.value).toBe('');
    });
});
