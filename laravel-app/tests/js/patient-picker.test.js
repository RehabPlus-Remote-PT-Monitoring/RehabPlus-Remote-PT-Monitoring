import { describe, expect, test } from 'vitest';
import { choosePatient, filterPatientOptions, matchesSearch, setPatientMenuOpen } from '../../resources/js/patient-picker.js';

describe('matchesSearch', () => {
    test('ignores case and surrounding spaces', () => {
        expect(matchesSearch('Emily Johnson', '  emily ')).toBe(true);
        expect(matchesSearch('Emily Johnson', 'lee')).toBe(false);
    });

    test('an empty search matches everything', () => {
        expect(matchesSearch('Emily Johnson', '')).toBe(true);
    });
});

describe('patient picker', () => {
    function picker(names = ['Emily Johnson', 'Mark Reyes']) {
        const root = document.createElement('div');
        root.dataset.patientPicker = '';
        root.innerHTML = `
            <input data-patient-name value="">
            <button data-patient-toggle></button>
            <div data-patient-menu class="dropdown-menu">
                <input data-patient-search>
                ${names.map((name) => `<button data-patient-option data-name="${name}" data-search="${name}"></button>`).join('')}
                <div data-patient-empty hidden></div>
            </div>`;
        document.body.append(root);

        return root;
    }

    test('filtering hides the options that do not match', () => {
        const root = picker();

        filterPatientOptions(root, 'mark');

        const [emily, mark] = root.querySelectorAll('[data-patient-option]');
        expect(emily.hidden).toBe(true);
        expect(mark.hidden).toBe(false);
        expect(root.querySelector('[data-patient-empty]').hidden).toBe(true);
    });

    test('shows the no-match message when nothing matches', () => {
        const root = picker();

        filterPatientOptions(root, 'zzz');

        expect(root.querySelector('[data-patient-empty]').hidden).toBe(false);
    });

    test('opening the list clears the search and shows every patient', () => {
        const root = picker();
        const search = root.querySelector('[data-patient-search]');
        search.value = 'mark';
        filterPatientOptions(root, 'mark');

        setPatientMenuOpen(root, true);

        expect(root.querySelector('[data-patient-menu]').classList.contains('show')).toBe(true);
        expect(search.value).toBe('');
        expect([...root.querySelectorAll('[data-patient-option]')].every((o) => !o.hidden)).toBe(true);
    });

    test('choosing a patient fills the name and closes the list', () => {
        const root = picker();
        setPatientMenuOpen(root, true);

        choosePatient(root, 'Mark Reyes');

        expect(root.querySelector('[data-patient-name]').value).toBe('Mark Reyes');
        expect(root.querySelector('[data-patient-menu]').classList.contains('show')).toBe(false);
    });
});
