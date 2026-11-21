/*
 * Changing a staff role: picking a different role asks first, because the account
 * gains or loses access straight away. Cancel puts the previous role back.
 *
 *   <select data-role-change data-current="admin" data-current-label="Administrator"
 *           data-name="Andrew" data-self="0">
 */

import { askToProceed } from './confirm.js';

/** The notice for a role change, in plain professional wording. */
export function roleChangeNotice({ name, self, to }) {
    const who = self ? 'your own role' : `the role of ${name}`;
    const subject = self ? 'you' : name;

    if (to === 'Administrator') {
        return `You are changing ${who} to Administrator. After saving, ${subject} will have access to all patients and to administrator features, including Staff Accounts.`;
    }

    return `You are changing ${who} to Physical Therapist. After saving, ${subject} will lose access to administrator features, including Staff Accounts, and will see only ${self ? 'your' : 'their'} own patients.`;
}

/** Asks before a role change is kept. Cancel puts the previous role back in the list. */
export async function confirmRoleChange(select) {
    // The current role is not in the list any more, so an empty value means nothing new was picked.
    if (select.value === '') {
        return;
    }

    const to = select.selectedOptions[0].text.trim();

    const proceed = await askToProceed({
        title: 'Change role?',
        message: roleChangeNotice({
            name: select.dataset.name,
            self: select.dataset.self === '1',
            to,
        }),
        danger: to !== 'Administrator',
    });

    if (!proceed) {
        select.value = ''; // back to the current role
    }
}
