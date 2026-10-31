import { describe, expect, test } from 'vitest';
import { applyRoleDefaults } from '../../resources/js/role-defaults.js';

describe('applyRoleDefaults', () => {
    function staffForm(role = 'staff', name = '', email = '') {
        const form = document.createElement('form');
        const select = document.createElement('select');
        for (const [value, label] of [['admin', 'Administrator'], ['staff', 'Front Desk Staff']]) {
            const option = new Option(label, value);
            Object.assign(option.dataset, { name: label, email: `${value}@rehabplus.com` });
            select.append(option);
        }
        select.value = role;

        const nameInput = Object.assign(document.createElement('input'), { name: 'name', value: name });
        const emailInput = Object.assign(document.createElement('input'), { name: 'email', value: email });
        form.append(select, nameInput, emailInput);
        document.body.append(form);

        return { select, nameInput, emailInput };
    }

    test('shows the picked role as the name and email placeholders', () => {
        const { select, nameInput, emailInput } = staffForm('admin');

        applyRoleDefaults(select);

        expect(nameInput.placeholder).toBe('Administrator');
        expect(emailInput.placeholder).toBe('admin@rehabplus.com');
    });

    test('changes the placeholders when the role changes', () => {
        const { select, nameInput, emailInput } = staffForm('staff');

        select.value = 'admin';
        applyRoleDefaults(select);

        expect(nameInput.placeholder).toBe('Administrator');
        expect(emailInput.placeholder).toBe('admin@rehabplus.com');
    });

    test('never changes what the admin typed', () => {
        const { select, nameInput, emailInput } = staffForm('admin', 'Dr. Reyes', 'reyes@rehabplus.com');

        applyRoleDefaults(select);

        expect(nameInput.value).toBe('Dr. Reyes');
        expect(emailInput.value).toBe('reyes@rehabplus.com');
    });
});
