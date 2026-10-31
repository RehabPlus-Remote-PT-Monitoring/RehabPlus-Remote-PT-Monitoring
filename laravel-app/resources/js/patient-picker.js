/*
 * Patient name on the appointment form: a text box with a list of active
 * patients beside it. Picking a patient fills the box, and the name can
 * still be typed by hand. The list has its own search box.
 *
 *   <div data-patient-picker>
 *     <input data-patient-name>
 *     <button data-patient-toggle>
 *     <div data-patient-menu class="dropdown-menu">
 *       <input data-patient-search>
 *       <button data-patient-option data-name="Emily Johnson" data-search="Emily Johnson Knee rehab">
 *       <div data-patient-empty hidden>
 *     </div>
 *   </div>
 */

/** Whether the search text is part of the option's text, ignoring case. */
export function matchesSearch(text, query) {
    return text.toLowerCase().includes(query.trim().toLowerCase());
}

/** Shows only the options that match the query, and the no-match message when none do. */
export function filterPatientOptions(picker, query) {
    let shown = 0;

    for (const option of picker.querySelectorAll('[data-patient-option]')) {
        const match = matchesSearch(option.dataset.search, query);
        option.hidden = !match;
        shown += match ? 1 : 0;
    }

    picker.querySelector('[data-patient-empty]')?.toggleAttribute('hidden', shown > 0);
}

/** Opens or closes the list. Opening clears the search and puts the cursor in it. */
export function setPatientMenuOpen(picker, open) {
    picker.querySelector('[data-patient-menu]').classList.toggle('show', open);
    picker.querySelector('[data-patient-toggle]')?.setAttribute('aria-expanded', String(open));

    const search = picker.querySelector('[data-patient-search]');
    if (open && search) {
        search.value = '';
        filterPatientOptions(picker, '');
        search.focus();
    }
}

/** Puts the picked patient's name in the box and closes the list. */
export function choosePatient(picker, name) {
    picker.querySelector('[data-patient-name]').value = name;
    setPatientMenuOpen(picker, false);
}

/** Wires up every patient picker on the page (one listener for all of them). */
export function initPatientPickers() {
    document.addEventListener('click', (event) => {
        const picker = event.target.closest?.('[data-patient-picker]');

        if (event.target.closest?.('[data-patient-option]')) {
            choosePatient(picker, event.target.closest('[data-patient-option]').dataset.name);
            return;
        }

        if (event.target.closest?.('[data-patient-toggle]')) {
            setPatientMenuOpen(picker, !picker.querySelector('[data-patient-menu]').classList.contains('show'));
            return;
        }

        // A click anywhere else closes the lists that are open.
        for (const menu of document.querySelectorAll('[data-patient-picker] [data-patient-menu].show')) {
            if (!menu.closest('[data-patient-picker]').contains(event.target)) {
                setPatientMenuOpen(menu.closest('[data-patient-picker]'), false);
            }
        }
    });

    document.addEventListener('input', (event) => {
        if (event.target.matches?.('[data-patient-search]')) {
            filterPatientOptions(event.target.closest('[data-patient-picker]'), event.target.value);
        }
    });

    document.addEventListener('keydown', (event) => {
        // Enter in the list's search box would submit the whole form.
        if (event.target.matches?.('[data-patient-search]') && event.key === 'Enter') {
            event.preventDefault();
        }

        if (event.key === 'Escape') {
            for (const menu of document.querySelectorAll('[data-patient-picker] [data-patient-menu].show')) {
                setPatientMenuOpen(menu.closest('[data-patient-picker]'), false);
            }
        }
    });
}
