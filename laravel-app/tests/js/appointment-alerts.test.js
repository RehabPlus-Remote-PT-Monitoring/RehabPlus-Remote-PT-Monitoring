import { beforeEach, describe, expect, test, vi } from 'vitest';
import { initAppointmentAlerts, markAlertsSeen, showUnseenCount } from '../../resources/js/appointment-alerts.js';

function bell(ids, key = 'appt-alerts-seen:th1', notices = 0) {
    const root = document.createElement('details');
    root.dataset.apptAlerts = '';
    root.dataset.seenKey = key;
    root.dataset.noticeCount = String(notices);
    root.innerHTML = `<summary><span data-appt-alerts-count hidden></span></summary>
        ${ids.map((id) => `<a data-appt-alert-id="${id}"></a>`).join('')}`;
    document.body.replaceChildren(root);

    return root;
}

const count = (root) => root.querySelector('[data-appt-alerts-count]');

describe('appointment bell', () => {
    beforeEach(() => localStorage.clear());

    test('counts every appointment the first time', () => {
        const root = bell(['a', 'b']);
        showUnseenCount(root);

        expect(count(root).textContent).toBe('2');
        expect(count(root).hidden).toBe(false);
    });

    test('opening it clears the number', () => {
        const root = bell(['a', 'b']);
        showUnseenCount(root);
        markAlertsSeen(root);

        expect(count(root).hidden).toBe(true);
    });

    test('the number stays gone on the next page', () => {
        markAlertsSeen(bell(['a', 'b']));

        const next = bell(['a', 'b']);
        showUnseenCount(next);

        expect(count(next).hidden).toBe(true);
    });

    test('a new appointment brings back a count of just the new one', () => {
        markAlertsSeen(bell(['a', 'b']));

        const next = bell(['a', 'b', 'c']);
        showUnseenCount(next);

        expect(count(next).textContent).toBe('1');
        expect(count(next).hidden).toBe(false);
    });

    test('another therapist on the same browser has their own count', () => {
        markAlertsSeen(bell(['a'], 'appt-alerts-seen:th1'));

        const other = bell(['a'], 'appt-alerts-seen:th2');
        showUnseenCount(other);

        expect(count(other).textContent).toBe('1');
    });

    test('still shows the count when browser storage is blocked', () => {
        const blocked = vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
            throw new Error('blocked');
        });
        const root = bell(['a']);
        showUnseenCount(root);
        blocked.mockRestore();

        expect(count(root).textContent).toBe('1');
    });

    test('unopened notices add to the count', () => {
        const root = bell(['a'], 'appt-alerts-seen:th1', 2);
        showUnseenCount(root);

        expect(count(root).textContent).toBe('3');
    });

    test('notices alone show a count', () => {
        const root = bell([], 'appt-alerts-seen:th1', 1);
        showUnseenCount(root);

        expect(count(root).textContent).toBe('1');
        expect(count(root).hidden).toBe(false);
    });

    test('opening the bell clears the appointments but not the notices', () => {
        const root = bell(['a'], 'appt-alerts-seen:th1', 2);
        showUnseenCount(root);
        markAlertsSeen(root);

        expect(count(root).textContent).toBe('2');
        expect(count(root).hidden).toBe(false);
    });

    test('nothing to show when no notices and every appointment is seen', () => {
        markAlertsSeen(bell(['a']));
        const next = bell(['a'], 'appt-alerts-seen:th1', 0);
        showUnseenCount(next);

        expect(count(next).hidden).toBe(true);
    });

    test('opening the bell on the page marks them seen', () => {
        const root = bell(['a']);
        initAppointmentAlerts();
        expect(count(root).hidden).toBe(false);

        root.open = true;
        root.dispatchEvent(new Event('toggle'));

        expect(count(root).hidden).toBe(true);
    });
});
