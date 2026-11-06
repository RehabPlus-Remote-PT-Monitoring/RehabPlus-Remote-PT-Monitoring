import { beforeAll, beforeEach, describe, expect, test } from 'vitest';
import { askToProceed, confirmSubmit, formChanges, needsConfirmation } from '../../resources/js/confirm.js';
import { answer, installDialogPolyfill, openDialog } from './dialog.js';

beforeAll(installDialogPolyfill);

// The patient edit form as Blade renders it: data-initial holds the saved values.
function editForm() {
    document.body.innerHTML = `
        <form id="f" data-confirm-changes="Save these changes to Olive's profile?">
            <input type="hidden" name="_token" value="t">
            <label for="name">Full name</label>
            <input id="name" name="name" value="Olive One" data-initial="Olive One">
            <label for="phone">Phone</label>
            <input id="phone" name="phone" value="" data-initial="">
            <label for="therapist_id">Assigned therapist</label>
            <select id="therapist_id" name="therapist_id" data-initial="thA">
                <option value="">Unassigned</option>
                <option value="thA" selected>Dr. Ana</option>
                <option value="thB">Dr. Ben</option>
            </select>
            <label for="plan">Therapy plan</label>
            <textarea id="plan" name="therapy_plan" data-initial="Stretch daily">Stretch daily</textarea>
            <input id="pw" type="password" name="password" value="">
            <input id="nolabel" name="note" value="a">
            <input name="off" value="x" disabled>
            <input type="checkbox" id="cb" name="cb">
            <label for="cb">Urgent</label>
        </form>`;
    return document.getElementById('f');
}

beforeEach(() => {
    openDialog()?.remove();
});

describe('formChanges', () => {
    test('nothing changed: empty list', () => {
        expect(formChanges(editForm())).toEqual([]);
    });

    test('lists each changed field with its label, old and new value', () => {
        const form = editForm();
        form.elements.name.value = 'Olive Renamed';
        form.elements.phone.value = '0917';
        form.elements.therapist_id.value = 'thB';
        form.elements.therapy_plan.value = 'Stretch daily ';  // only whitespace: not a change
        form.elements.note.value = 'b';
        form.elements.cb.checked = true;
        form.elements.password.value = 'secret123';           // never listed

        expect(formChanges(form)).toEqual([
            { label: 'Full name', from: 'Olive One', to: 'Olive Renamed' },
            { label: 'Phone', from: '', to: '0917' },
            { label: 'Assigned therapist', from: 'Dr. Ana', to: 'Dr. Ben' },
            { label: 'note', from: 'a', to: 'b' },
            { label: 'Urgent', from: 'No', to: 'Yes' },
        ]);
    });

    test('compares with the saved value, not input re-shown after a validation error', () => {
        const form = editForm();
        form.elements.name.defaultValue = 'Typed before the error'; // what old() puts back
        form.elements.name.value = 'Typed before the error';
        expect(formChanges(form)).toEqual([{ label: 'Full name', from: 'Olive One', to: 'Typed before the error' }]);
    });

    test('without data-initial it compares with what the page loaded with', () => {
        document.body.innerHTML = `<form id="g"><select name="s"><option>A</option><option>B</option></select>
            <input name="t" value="x"></form>`;
        const form = document.getElementById('g');
        form.elements.s.value = 'B';
        form.elements.t.value = 'y';
        expect(formChanges(form)).toEqual([
            { label: 's', from: 'A', to: 'B' },
            { label: 't', from: 'x', to: 'y' },
        ]);
    });
});

describe('askToProceed', () => {
    test('shows the question and resolves true on Proceed', async () => {
        const result = askToProceed({ message: 'Archive Olive?', danger: true });
        const dialog = openDialog();
        expect(dialog.open).toBe(true);
        expect(dialog.querySelector('h2').textContent).toBe('Do you want to proceed?');
        expect(dialog.querySelector('p').textContent).toBe('Archive Olive?');
        expect(dialog.querySelector('.btn-danger').textContent).toBe('Proceed');
        expect(dialog.querySelector('button[autofocus]').textContent).toBe('Cancel');
        answer('proceed');
        await expect(result).resolves.toBe(true);
        expect(openDialog()).toBeNull(); // removed again
    });

    test('Cancel or Escape resolves false', async () => {
        const cancelled = askToProceed({ message: 'x' });
        answer('cancel');
        await expect(cancelled).resolves.toBe(false);

        const escaped = askToProceed({ message: 'x' });
        openDialog().close(); // Escape closes with no value
        await expect(escaped).resolves.toBe(false);
    });

    test('lists changes as text, so typed markup is not rendered', async () => {
        const long = 'x'.repeat(200);
        const result = askToProceed({ changes: [
            { label: 'Full name', from: 'Olive', to: '<img src=x onerror=alert(1)>' },
            { label: 'Therapy plan', from: '', to: long },
        ] });
        const items = openDialog().querySelectorAll('.confirm-changes li');
        expect(items).toHaveLength(2);
        expect(openDialog().querySelector('img')).toBeNull();
        expect(items[0].querySelector('.confirm-to').textContent).toBe('<img src=x onerror=alert(1)>');
        expect(items[1].querySelector('.confirm-from').textContent).toBe('(empty)');
        expect(items[1].querySelector('.confirm-to').textContent).toHaveLength(80);
        expect(openDialog().querySelector('.btn-primary')).not.toBeNull();
        answer('cancel');
        await result;
    });

    test('onlyClose shows a single Close button', async () => {
        const result = askToProceed({ title: 'Nothing to save', onlyClose: true });
        const buttons = openDialog().querySelectorAll('button');
        expect([...buttons].map((b) => b.textContent)).toEqual(['Close']);
        answer('cancel');
        await expect(result).resolves.toBe(false);
    });
});

describe('confirmSubmit', () => {
    test('needsConfirmation spots data-confirm and data-confirm-changes', () => {
        document.body.innerHTML = '<form id="a" data-confirm="?"></form><form id="b" data-confirm-changes></form><form id="c"></form>';
        expect(needsConfirmation(document.getElementById('a'))).toBe(true);
        expect(needsConfirmation(document.getElementById('b'))).toBe(true);
        expect(needsConfirmation(document.getElementById('c'))).toBe(false);
    });

    test('an edit form with no changes says so and does not submit', async () => {
        const result = confirmSubmit(editForm());
        expect(openDialog().querySelector('h2').textContent).toBe('Nothing to save');
        answer('cancel');
        await expect(result).resolves.toBe(false);
    });

    test('an edit form with changes asks with its own question and the list', async () => {
        const form = editForm();
        form.elements.name.value = 'Olive Renamed';
        const result = confirmSubmit(form);
        expect(openDialog().querySelector('p').textContent).toBe("Save these changes to Olive's profile?");
        expect(openDialog().querySelectorAll('.confirm-changes li')).toHaveLength(1);
        answer('proceed');
        await expect(result).resolves.toBe(true);
    });

    test('a data-confirm form asks its message', async () => {
        document.body.innerHTML = '<form id="p" data-confirm="Set a new app password for Olive?"></form>';
        const result = confirmSubmit(document.getElementById('p'));
        expect(openDialog().querySelector('p').textContent).toBe('Set a new app password for Olive?');
        expect(openDialog().querySelector('.btn-danger')).toBeNull();
        answer('proceed');
        await expect(result).resolves.toBe(true);
    });
});
