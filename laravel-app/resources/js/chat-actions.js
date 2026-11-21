/*
 * Chat bubble actions on the conversation page (resources/views/messages):
 *
 *   <div data-chat-row data-message-id data-sender data-text
 *        [data-edit-url data-edit-until="<ms>"]>          one message
 *     <button data-chat-menu-toggle>⋮</button>
 *     <div data-chat-menu hidden>                         its menu
 *       <button data-chat-reply> / data-chat-edit / data-chat-copy
 *       <form> Pin / Unpin / Unsend (plain POSTs; Unsend has data-confirm)
 *   <button data-chat-scroll-to="<id>">                   reply quote, pinned banner
 *   <div data-reply-preview> + <form data-chat-composer>  "Replying to …" above the box
 *
 * Which items a menu has is decided on the server (MessagePresenter::withActions)
 * and checked again when a form is posted; this file only runs them. Copy never
 * calls the server. Everything is built with textContent, because message text
 * is typed by patients and staff.
 */

/** Characters of the quoted message shown above the reply box. */
export const PREVIEW_LENGTH = 120;

/** Message text on one line, shortened for a preview. */
export function snippet(text, max = PREVIEW_LENGTH) {
    const clean = String(text ?? '').replace(/\s+/g, ' ').trim();
    return clean.length > max ? `${clean.slice(0, max - 1)}…` : clean;
}

/**
 * Whether Edit may still be offered for this row. The server sent the end of
 * the 15-minute window; a page left open longer must stop offering Edit (the
 * server would refuse it anyway).
 */
export function canStillEdit(row, now = Date.now()) {
    const until = Number(row.dataset.editUntil);
    return Boolean(row.dataset.editUrl) && Number.isFinite(until) && now < until;
}

/** Close every open bubble menu. */
export function closeMenus(root = document) {
    root.querySelectorAll('[data-chat-menu]:not([hidden])').forEach((menu) => {
        menu.hidden = true;
        menu.closest('.chat-actions')?.querySelector('[data-chat-menu-toggle]')?.setAttribute('aria-expanded', 'false');
    });
}

/** Open the menu next to this "⋮" button (closing any other), with Edit hidden once its time is up. */
export function openMenu(toggle, now = Date.now()) {
    const menu = toggle.closest('.chat-actions').querySelector('[data-chat-menu]');
    const row = toggle.closest('[data-chat-row]');
    closeMenus(toggle.ownerDocument);

    const edit = menu.querySelector('[data-chat-edit]');
    if (edit) {
        edit.hidden = !canStillEdit(row, now);
    }

    menu.hidden = false;
    toggle.setAttribute('aria-expanded', 'true');
    menu.querySelector('button:not([hidden])')?.focus();
    return menu;
}

/** Show "Replying to <sender>" above the reply box and send the message id with the next reply. */
export function setReplyTarget(composer, preview, row) {
    composer.querySelector('[data-reply-to-id]').value = row.dataset.messageId;
    preview.querySelector('[data-reply-preview-sender]').textContent = row.dataset.sender || 'message';
    preview.querySelector('[data-reply-preview-text]').textContent = snippet(row.dataset.text) || 'Shared session';
    preview.hidden = false;
    composer.querySelector('textarea')?.focus();
}

/** Remove the reply preview: the next message is a normal one. */
export function clearReplyTarget(composer, preview) {
    composer.querySelector('[data-reply-to-id]').value = '';
    preview.hidden = true;
}

/**
 * After a failed send the page comes back with the reply id still in the
 * form (Laravel's old input): show its preview again, or drop it if that
 * message is no longer on the page.
 */
export function restoreReplyTarget(doc, composer, preview) {
    const id = composer.querySelector('[data-reply-to-id]')?.value;
    if (!id) {
        return;
    }
    const row = doc.getElementById(`msg-${id}`);
    if (row) {
        setReplyTarget(composer, preview, row);
    } else {
        clearReplyTarget(composer, preview);
    }
}

/** Copy the message text; resolves true when the browser allowed it. */
export async function copyMessage(row) {
    try {
        await navigator.clipboard.writeText(row.dataset.text ?? '');
        return true;
    } catch (error) {
        console.error('Copy failed', error);
        return false;
    }
}

/** A short note at the bottom of the screen ("Copied"), announced to screen readers. */
export function showToast(doc, text) {
    doc.querySelector('.chat-toast')?.remove();
    const toast = doc.createElement('div');
    toast.className = 'chat-toast';
    toast.setAttribute('role', 'status');
    toast.textContent = text;
    doc.body.append(toast);
    setTimeout(() => toast.remove(), 1800);
    return toast;
}

/** Scroll to a message on the page and flash it; false if it isn't loaded here. */
export function scrollToMessage(doc, id) {
    const row = doc.getElementById(`msg-${id}`);
    if (!row) {
        return false;
    }
    const reduceMotion = doc.defaultView?.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    row.scrollIntoView?.({ block: 'center', behavior: reduceMotion ? 'auto' : 'smooth' });
    row.classList.add('chat-row-flash');
    setTimeout(() => row.classList.remove('chat-row-flash'), 1600);
    return true;
}

/**
 * A small pop-up to edit one's own message: a normal POST form to the
 * message's edit URL (the server re-checks owner and time window).
 */
export function openEditDialog(doc, row, csrfToken, maxLength = 1000) {
    const dialog = doc.createElement('dialog');
    dialog.className = 'confirm-dialog chat-edit-dialog';
    dialog.setAttribute('aria-labelledby', 'chatEditTitle');

    const title = doc.createElement('h2');
    title.className = 'confirm-title';
    title.id = 'chatEditTitle';
    title.textContent = 'Edit message';

    const form = doc.createElement('form');
    form.method = 'post';
    form.action = row.dataset.editUrl;

    const token = doc.createElement('input');
    token.type = 'hidden';
    token.name = '_token';
    token.value = csrfToken;

    const box = doc.createElement('textarea');
    box.name = 'text';
    box.className = 'form-control';
    box.rows = 4;
    box.maxLength = maxLength;
    box.required = true;
    box.value = row.dataset.text ?? '';
    box.setAttribute('aria-label', 'Message');

    const buttons = doc.createElement('div');
    buttons.className = 'confirm-buttons';
    const cancel = doc.createElement('button');
    cancel.type = 'button';
    cancel.className = 'btn btn-light';
    cancel.textContent = 'Cancel';
    cancel.addEventListener('click', () => dialog.close());
    const save = doc.createElement('button');
    save.type = 'submit';
    save.className = 'btn btn-primary';
    save.textContent = 'Save';
    buttons.append(cancel, save);

    form.append(token, box, buttons);
    dialog.append(title, form);
    dialog.addEventListener('close', () => dialog.remove());
    doc.body.append(dialog);
    dialog.showModal();
    box.focus();
    return dialog;
}

/**
 * Wire the conversation page. Does nothing on other pages. Returns a function
 * that removes the listeners again (used by the tests).
 */
export function initChatActions(doc = document) {
    const list = doc.getElementById('messageList');
    if (!list) {
        return () => {};
    }
    const listeners = new AbortController();
    const composer = doc.querySelector('[data-chat-composer]');
    const preview = doc.querySelector('[data-reply-preview]');
    const csrfToken = () => doc.querySelector('input[name="_token"]')?.value ?? '';

    if (composer && preview) {
        restoreReplyTarget(doc, composer, preview);
    }

    doc.addEventListener('click', async (event) => {
        const target = event.target;

        const toggle = target.closest?.('[data-chat-menu-toggle]');
        if (toggle) {
            const menu = toggle.closest('.chat-actions').querySelector('[data-chat-menu]');
            if (menu.hidden) {
                openMenu(toggle);
            } else {
                closeMenus(doc);
            }
            return;
        }

        const row = target.closest?.('[data-chat-row]');
        if (target.closest?.('[data-chat-reply]') && composer && preview) {
            closeMenus(doc);
            setReplyTarget(composer, preview, row);
            return;
        }
        if (target.closest?.('[data-chat-copy]')) {
            closeMenus(doc);
            showToast(doc, (await copyMessage(row)) ? 'Copied' : "Couldn't copy. Select the text instead.");
            return;
        }
        if (target.closest?.('[data-chat-edit]')) {
            closeMenus(doc);
            if (canStillEdit(row)) {
                openEditDialog(doc, row, csrfToken());
            } else {
                showToast(doc, 'Messages can only be edited within 15 minutes of sending.');
            }
            return;
        }
        if (target.closest?.('[data-reply-cancel]') && composer && preview) {
            clearReplyTarget(composer, preview);
            return;
        }

        const jump = target.closest?.('[data-chat-scroll-to]');
        if (jump) {
            if (!scrollToMessage(doc, jump.dataset.chatScrollTo)) {
                showToast(doc, 'That message is older than the ones shown here.');
            }
            return;
        }

        // A click anywhere else closes an open menu; clicks inside a menu
        // (its forms) or a pop-up (the Unsend confirmation) leave it alone.
        if (!target.closest?.('[data-chat-menu]') && !target.closest?.('dialog')) {
            closeMenus(doc);
        }
    }, { signal: listeners.signal });

    doc.addEventListener('keydown', (event) => {
        if (event.key !== 'Escape') {
            return;
        }
        const open = doc.querySelector('[data-chat-menu]:not([hidden])');
        if (open) {
            closeMenus(doc);
            open.closest('.chat-actions')?.querySelector('[data-chat-menu-toggle]')?.focus();
        }
    }, { signal: listeners.signal });

    return () => listeners.abort();
}
