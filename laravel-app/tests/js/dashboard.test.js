// Behaviour tests for resources/js/rehabplus-dashboard.js in a fake browser
// (jsdom). The script wires itself to the page when imported, so the page is
// built once and the script imported once; beforeEach resets the state.
import { afterEach, beforeAll, beforeEach, describe, expect, test, vi } from 'vitest';

const WIDTH = 280;
let phoneLayoutListener;

beforeAll(async () => {
    document.head.innerHTML = '<meta name="theme-color" id="themeColor" content="">';
    document.body.innerHTML = `
        <header id="topbar"><button id="navToggle" aria-expanded="false">Menu</button>
            <button id="themeToggle"></button></header>
        <div id="sidebarScrim"></div>
        <nav id="sidebar" tabindex="-1"><button id="navClose">Close</button><a id="link" href="#x">Patients</a></nav>
        <main id="mainContent">
            <input id="patientSearch">
            <table id="patientsTable"><tbody>
                <tr><td>Olive One</td></tr><tr><td>Bob Two</td></tr>
            </tbody></table>
            <form id="confirmForm" data-confirm="Delete this?"></form>
            <form id="autoForm"><select id="auto" data-autosubmit><option>a</option></select></form>
            <button id="printBtn" data-print></button>
            <button id="swapBtn" data-show="panelB" data-hide="panelA extra"></button>
            <div id="panelA"></div><div id="panelB" hidden></div><div id="extra"></div>
        </main>`;
    Object.defineProperty(document.getElementById('sidebar'), 'offsetWidth', { value: WIDTH });
    // jsdom has no layout, so no innerText; textContent is the same for these rows.
    Object.defineProperty(HTMLElement.prototype, 'innerText', {
        configurable: true,
        get() {
            return this.textContent;
        },
    });
    document.getElementById('sidebar').setPointerCapture = vi.fn();
    window.matchMedia = vi.fn((query) => ({
        matches: false,
        media: query,
        addEventListener: (type, listener) => {
            if (query.includes('max-width')) {
                phoneLayoutListener = listener;
            }
        },
    }));
    await import('../../resources/js/rehabplus-dashboard.js');
});

const $ = (id) => document.getElementById(id);
const sidebar = () => $('sidebar');
const isOpen = () => document.documentElement.classList.contains('nav-open');

function pointer(type, target, { id = 1, x = 0, y = 0, kind = 'touch' } = {}) {
    const event = new Event(type, { bubbles: true, cancelable: true });
    Object.assign(event, { pointerId: id, clientX: x, clientY: y, pointerType: kind });
    target.dispatchEvent(event);
}

// A finger swipe on the open drawer: down at 200, moves through `xs`, lifts.
function swipe(xs, { y = 100, kind = 'touch', lift = true } = {}) {
    pointer('pointerdown', sidebar(), { x: 200, y: 100, kind });
    for (const x of xs) {
        pointer('pointermove', sidebar(), { x, y, kind });
    }
    if (lift) {
        pointer('pointerup', sidebar(), { x: xs.at(-1), y, kind });
    }
}

beforeEach(() => {
    $('navToggle').click(); // open the drawer
    vi.spyOn(performance, 'now').mockReturnValue(0);
});

afterEach(() => {
    if (isOpen()) {
        $('navClose').click();
    }
    vi.restoreAllMocks();
});

describe('phone menu', () => {
    test('opens from the menu button and closes from close, scrim and Escape', () => {
        expect(isOpen()).toBe(true);
        expect($('navToggle').getAttribute('aria-expanded')).toBe('true');
        expect($('mainContent').hasAttribute('inert')).toBe(true);

        $('navClose').click();
        expect(isOpen()).toBe(false);
        expect($('mainContent').hasAttribute('inert')).toBe(false);

        $('navToggle').click();
        $('sidebarScrim').click();
        expect(isOpen()).toBe(false);

        $('navToggle').click();
        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
        expect(isOpen()).toBe(false);
    });

    test('closing moves focus from the drawer back to the menu button', () => {
        $('link').focus();
        $('navClose').click();
        expect(document.activeElement).toBe($('navToggle'));
    });

    test('widening to the desktop layout or leaving the page closes it', () => {
        phoneLayoutListener({ matches: true });
        expect(isOpen()).toBe(true);
        phoneLayoutListener({ matches: false });
        expect(isOpen()).toBe(false);

        $('navToggle').click();
        window.dispatchEvent(new Event('pagehide'));
        expect(isOpen()).toBe(false);
    });

    test('a long swipe left closes it and follows the finger on the way', () => {
        swipe([185, 150], { lift: false });
        expect(sidebar().classList.contains('is-dragging')).toBe(true);
        expect(sidebar().setPointerCapture).toHaveBeenCalledWith(1);
        expect(sidebar().style.transform).toBe('translateX(-35px)'); // tracked from where the swipe began
        expect($('sidebarScrim').style.opacity).toBe(String(1 - 35 / WIDTH));

        performance.now.mockReturnValue(5000); // slow: closes on distance alone
        pointer('pointermove', sidebar(), { x: 60, y: 100 });
        pointer('pointerup', sidebar(), { x: 60, y: 100 });
        expect(isOpen()).toBe(false);
        expect(sidebar().classList.contains('is-dragging')).toBe(false);
        expect(sidebar().style.transform).toBe('');
    });

    test('a short slow swipe springs back open', () => {
        swipe([185], { lift: false });
        performance.now.mockReturnValue(5000);
        pointer('pointermove', sidebar(), { x: 160, y: 100 });
        pointer('pointerup', sidebar(), { x: 160, y: 100 });
        expect(isOpen()).toBe(true);
    });

    test('a quick short flick closes it', () => {
        swipe([185], { lift: false });
        performance.now.mockReturnValue(100);
        pointer('pointermove', sidebar(), { x: 150, y: 100 });
        pointer('pointerup', sidebar(), { x: 150, y: 100 });
        expect(isOpen()).toBe(false);
    });

    test('tiny moves, vertical scrolls and mouse drags do not drag', () => {
        swipe([195]);
        swipe([195, 190], { y: 160 });
        swipe([100], { kind: 'mouse' });
        expect(sidebar().classList.contains('is-dragging')).toBe(false);
        expect(isOpen()).toBe(true);
    });

    test('a second finger mid-swipe is ignored', () => {
        swipe([185], { lift: false });
        pointer('pointerdown', sidebar(), { id: 2, x: 10 });
        pointer('pointermove', sidebar(), { id: 2, x: 0 });
        pointer('pointerup', sidebar(), { id: 2, x: 0 });
        expect(sidebar().classList.contains('is-dragging')).toBe(true);
        pointer('pointercancel', sidebar(), { x: 185 });
        expect(sidebar().classList.contains('is-dragging')).toBe(false);
    });

    test('a tap on a link right after a swipe does not follow it', async () => {
        swipe([185, 170]);
        const click = new MouseEvent('click', { bubbles: true, cancelable: true });
        $('link').dispatchEvent(click);
        expect(click.defaultPrevented).toBe(true);

        await new Promise((resolve) => setTimeout(resolve, 0));
        const later = new MouseEvent('click', { bubbles: true, cancelable: true });
        $('link').dispatchEvent(later);
        expect(later.defaultPrevented).toBe(false);
    });

    test('pointer events while closed are ignored', () => {
        $('navClose').click();
        swipe([185, 60]);
        expect(sidebar().style.transform).toBe('');
    });
});

describe('page actions', () => {
    test('data-confirm asks before submitting', () => {
        window.confirm = vi.fn(() => false);
        const blocked = new Event('submit', { bubbles: true, cancelable: true });
        $('confirmForm').dispatchEvent(blocked);
        expect(window.confirm).toHaveBeenCalledWith('Delete this?');
        expect(blocked.defaultPrevented).toBe(true);

        window.confirm = vi.fn(() => true);
        const allowed = new Event('submit', { bubbles: true, cancelable: true });
        $('confirmForm').dispatchEvent(allowed);
        expect(allowed.defaultPrevented).toBe(false);
    });

    test('data-autosubmit submits its form when changed', () => {
        const submit = vi.spyOn($('autoForm'), 'requestSubmit').mockImplementation(() => {});
        $('auto').dispatchEvent(new Event('change', { bubbles: true }));
        expect(submit).toHaveBeenCalled();
    });

    test('data-show / data-hide swap panels, data-print prints', () => {
        $('swapBtn').click();
        expect($('panelA').hidden).toBe(true);
        expect($('extra').hidden).toBe(true);
        expect($('panelB').hidden).toBe(false);

        window.print = vi.fn();
        $('printBtn').click();
        expect(window.print).toHaveBeenCalled();
    });

    test('other clicks do nothing', () => {
        window.print = vi.fn();
        $('mainContent').click();
        expect(window.print).not.toHaveBeenCalled();
    });
});

describe('patient search and theme', () => {
    test('typing filters the patient table', () => {
        const search = $('patientSearch');
        search.value = 'olive';
        search.dispatchEvent(new KeyboardEvent('keyup'));
        const rows = document.querySelectorAll('#patientsTable tbody tr');
        expect(rows[0].style.display).toBe('');
        expect(rows[1].style.display).toBe('none');
    });

    test('the theme button switches dark mode and remembers it', () => {
        const wasDark = document.body.classList.contains('dark-mode');
        $('themeToggle').click();
        expect(document.body.classList.contains('dark-mode')).toBe(!wasDark);
        expect(localStorage.getItem('rehabplus-theme')).toBe(wasDark ? 'light' : 'dark');
        $('themeToggle').click();
        expect(document.body.classList.contains('dark-mode')).toBe(wasDark);
    });
});
