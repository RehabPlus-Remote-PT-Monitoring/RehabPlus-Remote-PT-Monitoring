/*
 * "Do you want to proceed?" pop-up for forms that change something important
 * (see the submit handler in rehabplus-dashboard.js):
 *
 *   <form data-confirm="Archive this patient? ...">   asks with that message
 *   <form data-confirm-danger ...>                     red Proceed button
 *   <form data-confirm-changes="Save these changes?">  also lists every field
 *                                                      changed since the page loaded
 *
 * Built as a native <dialog> (focus stays inside, Escape cancels) from text
 * nodes only, so names typed into a form can't inject markup.
 */

const MAX_SHOWN = 80; // characters of a long value shown in the list

/**
 * Fields of the form whose value differs from when the page loaded, as
 * { label, from, to }. Passwords are never listed (their values stay hidden).
 */
export function formChanges(form) {
    const changes = [];
    for (const field of form.elements) {
        if (!isListable(field)) {
            continue;
        }
        const from = initialValue(field);
        const to = currentValue(field);
        if (from !== to) {
            changes.push({ label: labelFor(form, field), from, to });
        }
    }
    return changes;
}

function isListable(field) {
    const skipped = ['hidden', 'password', 'submit', 'button', 'reset', 'file'];
    return Boolean(field.name) && !field.disabled && !skipped.includes(field.type);
}

function initialValue(field) {
    // data-initial: the saved value, for pages re-shown with the user's input
    // after a validation error (where the field's default is that input).
    const saved = field.dataset.initial;
    if (field.tagName === 'SELECT') {
        const option = saved !== undefined
            ? [...field.options].find((o) => o.value === saved)
            : [...field.options].find((o) => o.defaultSelected) ?? field.options[0];
        return option?.text.trim() ?? '';
    }
    if (field.type === 'checkbox' || field.type === 'radio') {
        return field.defaultChecked ? 'Yes' : 'No';
    }
    return (saved ?? field.defaultValue).trim();
}

function currentValue(field) {
    if (field.tagName === 'SELECT') {
        return field.selectedOptions[0]?.text.trim() ?? '';
    }
    if (field.type === 'checkbox' || field.type === 'radio') {
        return field.checked ? 'Yes' : 'No';
    }
    return field.value.trim();
}

function labelFor(form, field) {
    const label = field.id ? form.querySelector(`label[for="${CSS.escape(field.id)}"]`) : null;
    return label?.textContent.trim() || field.name;
}

function shorten(value) {
    if (value === '') {
        return '(empty)';
    }
    return value.length > MAX_SHOWN ? `${value.slice(0, MAX_SHOWN - 1)}…` : value;
}

function element(tag, className, text) {
    const node = document.createElement(tag);
    node.className = className;
    if (text !== undefined) {
        node.textContent = text;
    }
    return node;
}

function changeList(changes) {
    const list = element('ul', 'confirm-changes');
    for (const change of changes) {
        const item = element('li', '');
        item.append(
            element('span', 'confirm-field', change.label),
            element('span', 'confirm-from', shorten(change.from)),
            element('span', 'confirm-arrow', '→'),
            element('span', 'confirm-to', shorten(change.to)),
        );
        list.append(item);
    }
    return list;
}

/**
 * Shows the pop-up and resolves true if the user chose Proceed.
 * With onlyClose there's just a Close button (always resolves false).
 */
export function askToProceed({ title = 'Do you want to proceed?', message = '', changes = [], danger = false, onlyClose = false }) {
    const dialog = element('dialog', 'confirm-dialog');
    dialog.setAttribute('aria-labelledby', 'confirmDialogTitle');

    const heading = element('h2', 'confirm-title', title);
    heading.id = 'confirmDialogTitle';
    dialog.append(heading);
    if (message) {
        dialog.append(element('p', 'confirm-message', message));
    }
    if (changes.length) {
        dialog.append(changeList(changes));
    }

    // method="dialog": the clicked button's value becomes dialog.returnValue.
    const buttons = element('form', 'confirm-buttons');
    buttons.method = 'dialog';
    const cancel = element('button', 'btn btn-light', onlyClose ? 'Close' : 'Cancel');
    cancel.value = 'cancel';
    cancel.autofocus = true; // the safe choice has focus
    buttons.append(cancel);
    if (!onlyClose) {
        const proceed = element('button', danger ? 'btn btn-danger' : 'btn btn-primary', 'Proceed');
        proceed.value = 'proceed';
        buttons.append(proceed);
    }
    dialog.append(buttons);

    document.body.append(dialog);
    return new Promise((resolve) => {
        dialog.addEventListener('close', () => {
            dialog.remove();
            resolve(dialog.returnValue === 'proceed');
        });
        dialog.showModal();
    });
}

/** Whether this form asks before submitting. */
export function needsConfirmation(form) {
    return form.dataset?.confirm !== undefined || form.dataset?.confirmChanges !== undefined;
}

/** Asks the question the form declares; resolves true to go ahead. */
export async function confirmSubmit(form) {
    if (form.dataset.confirmChanges === undefined) {
        return askToProceed({ message: form.dataset.confirm, danger: form.dataset.confirmDanger !== undefined });
    }
    const changes = formChanges(form);
    if (changes.length === 0) {
        await askToProceed({ title: 'Nothing to save', message: "You haven't changed anything yet.", onlyClose: true });
        return false;
    }
    return askToProceed({ message: form.dataset.confirmChanges || 'Save these changes?', changes });
}
