import { afterEach, beforeAll, describe, expect, test, vi } from 'vitest';
import {
    canStillEdit,
    clearReplyTarget,
    closeMenus,
    copyMessage,
    initChatActions,
    openEditDialog,
    openMenu,
    restoreReplyTarget,
    scrollToMessage,
    setReplyTarget,
    snippet,
} from '../../resources/js/chat-actions.js';
import { installDialogPolyfill } from './dialog.js';

beforeAll(installDialogPolyfill);

// The conversation page as Blade renders it (messages/show + _list + _message_menu).
function page({ editUntil = Date.now() + 60_000, replyToId = '' } = {}) {
    document.body.innerHTML = `
        <div id="messageList">
            <div class="d-flex flex-column chat-row" id="msg-m1" data-chat-row data-message-id="m1"
                 data-sender="Anna Cruz" data-text="My knee   hurts&#10;after squats">
                <div class="chat-line">
                    <div class="chat-bubble">My knee hurts</div>
                    <div class="chat-actions">
                        <button type="button" data-chat-menu-toggle aria-expanded="false">⋮</button>
                        <div data-chat-menu hidden>
                            <button type="button" data-chat-reply>Reply</button>
                            <button type="button" data-chat-copy>Copy</button>
                        </div>
                    </div>
                </div>
            </div>
            <div class="d-flex flex-column chat-row" id="msg-s1" data-chat-row data-message-id="s1"
                 data-sender="Dr. Reyes" data-text="Do 10 squats."
                 data-edit-url="/messages/pAnna/s1/edit" data-edit-until="${editUntil}">
                <div class="chat-line">
                    <div class="chat-bubble"><button type="button" class="chat-quote" data-chat-scroll-to="m1">quote</button>Do 10 squats.</div>
                    <div class="chat-actions">
                        <button type="button" data-chat-menu-toggle aria-expanded="false">⋮</button>
                        <div data-chat-menu hidden>
                            <button type="button" data-chat-reply>Reply</button>
                            <button type="button" data-chat-edit>Edit</button>
                            <button type="button" data-chat-copy>Copy</button>
                        </div>
                    </div>
                </div>
            </div>
            <button type="button" id="jumpOld" data-chat-scroll-to="gone">pinned</button>
        </div>
        <div data-reply-preview hidden>
            <span data-reply-preview-sender></span><span data-reply-preview-text></span>
            <button type="button" data-reply-cancel>x</button>
        </div>
        <form data-chat-composer>
            <input type="hidden" name="_token" value="csrf-123">
            <input type="hidden" name="reply_to_id" value="${replyToId}" data-reply-to-id>
            <textarea name="text"></textarea>
        </form>`;

    return {
        row: (id) => document.getElementById(`msg-${id}`),
        composer: document.querySelector('[data-chat-composer]'),
        preview: document.querySelector('[data-reply-preview]'),
    };
}

const click = (el) => el.dispatchEvent(new MouseEvent('click', { bubbles: true }));

// initChatActions() listens on document; each test removes its listeners again.
let cleanups = [];
const init = () => cleanups.push(initChatActions());

afterEach(() => {
    cleanups.forEach((stop) => stop());
    cleanups = [];
    vi.unstubAllGlobals();
    vi.useRealTimers();
    document.body.replaceChildren();
});

describe('snippet', () => {
    test('puts the text on one line', () => {
        expect(snippet('  a \n b\t c ')).toBe('a b c');
    });

    test('shortens long text with an ellipsis', () => {
        const short = snippet('x'.repeat(300), 10);
        expect(short).toHaveLength(10);
        expect(short.endsWith('…')).toBe(true);
    });

    test('copes with missing text', () => {
        expect(snippet(undefined)).toBe('');
    });
});

describe('canStillEdit', () => {
    test('only before the end of the edit window', () => {
        const { row } = page({ editUntil: 1000 });
        expect(canStillEdit(row('s1'), 999)).toBe(true);
        expect(canStillEdit(row('s1'), 1000)).toBe(false);
    });

    test('never for a message without an edit URL', () => {
        const { row } = page();
        expect(canStillEdit(row('m1'))).toBe(false);
    });
});

describe('menus', () => {
    test('opening one closes the others and hides Edit once time is up', () => {
        const { row } = page({ editUntil: 5000 });
        const first = row('m1').querySelector('[data-chat-menu-toggle]');
        const second = row('s1').querySelector('[data-chat-menu-toggle]');

        openMenu(first);
        const menu = openMenu(second, 6000);

        expect(row('m1').querySelector('[data-chat-menu]').hidden).toBe(true);
        expect(first.getAttribute('aria-expanded')).toBe('false');
        expect(menu.hidden).toBe(false);
        expect(second.getAttribute('aria-expanded')).toBe('true');
        expect(menu.querySelector('[data-chat-edit]').hidden).toBe(true);

        closeMenus();
        expect(menu.hidden).toBe(true);
    });

    test('clicking ⋮ toggles, and clicking elsewhere or Escape closes', () => {
        const { row } = page();
        init();
        const toggle = row('s1').querySelector('[data-chat-menu-toggle]');
        const menu = row('s1').querySelector('[data-chat-menu]');

        click(toggle);
        expect(menu.hidden).toBe(false);
        expect(menu.querySelector('[data-chat-edit]').hidden).toBe(false);
        click(toggle);
        expect(menu.hidden).toBe(true);

        click(toggle);
        click(document.body);
        expect(menu.hidden).toBe(true);

        click(toggle);
        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
        expect(menu.hidden).toBe(true);
    });
});

describe('reply preview', () => {
    test('sets and clears the quoted message', () => {
        const { row, composer, preview } = page();

        setReplyTarget(composer, preview, row('m1'));
        expect(composer.querySelector('[data-reply-to-id]').value).toBe('m1');
        expect(preview.hidden).toBe(false);
        expect(preview.querySelector('[data-reply-preview-sender]').textContent).toBe('Anna Cruz');
        expect(preview.querySelector('[data-reply-preview-text]').textContent).toBe('My knee hurts after squats');
        expect(document.activeElement).toBe(composer.querySelector('textarea'));

        clearReplyTarget(composer, preview);
        expect(composer.querySelector('[data-reply-to-id]').value).toBe('');
        expect(preview.hidden).toBe(true);
    });

    test('shows text, not markup, from the message', () => {
        const { row, composer, preview } = page();
        row('m1').dataset.text = '<img src=x onerror=alert(1)>';

        setReplyTarget(composer, preview, row('m1'));

        expect(preview.querySelector('img')).toBeNull();
        expect(preview.querySelector('[data-reply-preview-text]').textContent).toContain('<img');
    });

    test('Reply in the menu and the × button drive it', () => {
        const { row, composer, preview } = page();
        init();

        click(row('s1').querySelector('[data-chat-menu-toggle]'));
        click(row('s1').querySelector('[data-chat-reply]'));
        expect(composer.querySelector('[data-reply-to-id]').value).toBe('s1');
        expect(row('s1').querySelector('[data-chat-menu]').hidden).toBe(true);

        click(preview.querySelector('[data-reply-cancel]'));
        expect(preview.hidden).toBe(true);
    });

    test('comes back after a failed send, or is dropped if the message is gone', () => {
        let { composer, preview } = page({ replyToId: 'm1' });
        restoreReplyTarget(document, composer, preview);
        expect(preview.hidden).toBe(false);

        ({ composer, preview } = page({ replyToId: 'missing' }));
        restoreReplyTarget(document, composer, preview);
        expect(preview.hidden).toBe(true);
        expect(composer.querySelector('[data-reply-to-id]').value).toBe('');
    });
});

describe('copy', () => {
    test('copies the message text without calling the server', async () => {
        const writeText = vi.fn().mockResolvedValue();
        const fetch = vi.fn();
        vi.stubGlobal('navigator', { clipboard: { writeText } });
        vi.stubGlobal('fetch', fetch);
        const { row } = page();

        expect(await copyMessage(row('s1'))).toBe(true);
        expect(writeText).toHaveBeenCalledWith('Do 10 squats.');
        expect(fetch).not.toHaveBeenCalled();
    });

    test('reports a refusal instead of failing silently', async () => {
        vi.stubGlobal('navigator', { clipboard: { writeText: vi.fn().mockRejectedValue(new Error('denied')) } });
        const error = vi.spyOn(console, 'error').mockImplementation(() => {});
        const { row } = page();

        expect(await copyMessage(row('s1'))).toBe(false);
        expect(error).toHaveBeenCalled();
        error.mockRestore();
    });

    test('Copy in the menu shows a short note', async () => {
        vi.stubGlobal('navigator', { clipboard: { writeText: vi.fn().mockResolvedValue() } });
        const { row } = page();
        init();

        click(row('s1').querySelector('[data-chat-copy]'));
        await vi.waitFor(() => expect(document.querySelector('.chat-toast')?.textContent).toBe('Copied'));
    });
});

describe('edit dialog', () => {
    test('posts the new text to the message edit URL with the CSRF token', () => {
        const { row } = page();

        const dialog = openEditDialog(document, row('s1'), 'csrf-123');
        const form = dialog.querySelector('form');

        expect(dialog.open).toBe(true);
        expect(form.getAttribute('action')).toBe('/messages/pAnna/s1/edit');
        expect(form.method).toBe('post');
        expect(form.querySelector('input[name="_token"]').value).toBe('csrf-123');
        expect(form.querySelector('textarea[name="text"]').value).toBe('Do 10 squats.');
        expect(form.querySelector('textarea').maxLength).toBe(1000);

        dialog.querySelector('button[type="button"]').click(); // Cancel
        expect(document.querySelector('.chat-edit-dialog')).toBeNull();
    });

    test('Edit in the menu opens it only inside the time window', () => {
        const { row } = page();
        init();
        click(row('s1').querySelector('[data-chat-edit]'));
        expect(document.querySelector('.chat-edit-dialog')).not.toBeNull();
        expect(document.querySelector('.chat-edit-dialog input[name="_token"]').value).toBe('csrf-123');
    });

    test('a page left open too long says why instead', () => {
        const { row } = page({ editUntil: Date.now() - 1 });
        init();
        click(row('s1').querySelector('[data-chat-edit]'));
        expect(document.querySelector('.chat-edit-dialog')).toBeNull();
        expect(document.querySelector('.chat-toast').textContent).toContain('15 minutes');
    });
});

describe('scroll to a quoted or pinned message', () => {
    test('scrolls to and flashes a message on the page', () => {
        vi.useFakeTimers();
        const { row } = page();
        const scroll = vi.fn();
        row('m1').scrollIntoView = scroll;

        expect(scrollToMessage(document, 'm1')).toBe(true);
        expect(scroll).toHaveBeenCalled();
        expect(row('m1').classList.contains('chat-row-flash')).toBe(true);
        vi.advanceTimersByTime(2000);
        expect(row('m1').classList.contains('chat-row-flash')).toBe(false);
    });

    test('says so when the message is older than the page', () => {
        page();
        init();
        click(document.getElementById('jumpOld'));
        expect(document.querySelector('.chat-toast').textContent).toContain('older');
    });
});
