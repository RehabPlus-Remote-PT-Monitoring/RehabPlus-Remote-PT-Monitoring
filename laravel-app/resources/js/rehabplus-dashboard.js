import { confirmSubmit, needsConfirmation } from './confirm.js';
import { copyPassword } from './copy-password.js';
import { dismissFlashMessages } from './flash-messages.js';
import { applyPhoneLimits, keepDigitsOnly, refreshPhoneProblem, showPhoneCountry } from './input-masks.js';
import { initPatientPickers } from './patient-picker.js';
import { applyRoleDefaults } from './role-defaults.js';
import { dragOffset, swipeCloses, swipeGesture } from './swipe.js';

dismissFlashMessages();

const searchInput = document.getElementById('patientSearch');
const rows = document.querySelectorAll('#patientsTable tbody tr');

function filterPatientRows() {
    const search = searchInput.value.toLowerCase();

    rows.forEach((row) => {
        row.style.display = row.innerText.toLowerCase().includes(search) ? '' : 'none';
    });
}

if (searchInput) {
    searchInput.addEventListener('keyup', filterPatientRows);

    document.getElementById('patientSearchButton')?.addEventListener('click', () => {
        filterPatientRows();
        searchInput.focus();
    });
}

const chartData = window.rehabPlusDashboardData || {};
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

// Charts use the dashboard's font and muted greys instead of Chart.js defaults,
// and a shorter draw-in so the page settles quickly.
if (window.Chart) {
    const dark = document.documentElement.classList.contains('dark-mode');
    Chart.defaults.font.family = "'Inter', system-ui, sans-serif";
    Chart.defaults.color = dark ? '#94a3b8' : '#64748b';
    Chart.defaults.borderColor = dark ? 'rgba(148,163,184,.15)' : 'rgba(15,23,42,.06)';
    Chart.defaults.plugins.legend.labels.usePointStyle = true;
    Chart.defaults.plugins.tooltip.cornerRadius = 8;
    Chart.defaults.plugins.tooltip.padding = 10;
    Chart.defaults.animation.duration = reduceMotion ? 0 : 500;
}

const recoveryChart = document.getElementById('recoveryChart');

if (recoveryChart && chartData.recoveryLabels && chartData.recoveryValues) {
    new Chart(recoveryChart, {
        type: 'line',
        data: {
            labels: chartData.recoveryLabels,
            datasets: [{
                label: 'Recovery Progress',
                data: chartData.recoveryValues,
                borderColor: '#14b8a6',
                backgroundColor: 'rgba(20,184,166,.12)',
                borderWidth: 2,
                pointRadius: 3,
                pointHoverRadius: 5,
                fill: true,
                tension: .4,
            }],
        },
    });
}

const conditionChart = document.getElementById('conditionChart');

if (conditionChart && chartData.conditionLabels && chartData.conditionValues) {
    new Chart(conditionChart, {
        type: 'doughnut',
        data: {
            labels: chartData.conditionLabels,
            datasets: [{
                data: chartData.conditionValues,
                backgroundColor: ['#14b8a6', '#0ea5e9', '#8b5cf6', '#f59e0b'],
                borderWidth: 0,
                spacing: 2,
            }],
        },
        options: { cutout: '68%' },
    });
}

const themeToggle = document.getElementById('themeToggle');
const themeColor = document.getElementById('themeColor');
const applyTheme = (dark) => {
    document.documentElement.classList.toggle('dark-mode', dark);
    document.body.classList.toggle('dark-mode', dark);
    // Phone status bar / browser chrome matches the top bar.
    if (themeColor) {
        themeColor.content = dark ? '#10172a' : '#f6f8fb';
    }
    themeToggle.innerHTML = dark
        ? '<i class="bi bi-sun-fill"></i>'
        : '<i class="bi bi-moon-fill"></i>';
};

if (themeToggle) {
    applyTheme(localStorage.getItem('rehabplus-theme') === 'dark');
    themeToggle.addEventListener('click', () => {
        const dark = !document.body.classList.contains('dark-mode');
        localStorage.setItem('rehabplus-theme', dark ? 'dark' : 'light');

        // Cross-fade between light and dark instead of an abrupt brightness jump.
        if (!document.startViewTransition || reduceMotion) {
            applyTheme(dark);
            return;
        }
        document.documentElement.classList.add('theme-switching');
        document.startViewTransition(() => applyTheme(dark)).finished
            .finally(() => document.documentElement.classList.remove('theme-switching'));
    });
}

/*
 * Phone menu: the sidebar slides in as a drawer. Opens from the menu button;
 * closes on the scrim, the close button, Escape, or a swipe to the left.
 * The swipe tracks the finger 1:1, and a quick flick closes it even if it
 * hasn't been dragged far.
 */
const sidebar = document.getElementById('sidebar');
const navToggle = document.getElementById('navToggle');
const navClose = document.getElementById('navClose');
const scrim = document.getElementById('sidebarScrim');
const phoneLayout = window.matchMedia('(max-width: 767.98px)');

if (sidebar && navToggle) {
    const behind = [document.getElementById('topbar'), document.getElementById('mainContent')];

    const setOpen = (open) => {
        document.documentElement.classList.toggle('nav-open', open);
        navToggle.setAttribute('aria-expanded', String(open));
        // Keep keyboard and screen readers inside the open drawer.
        behind.forEach((el) => el?.toggleAttribute('inert', open));
        if (open) {
            sidebar.focus({ preventScroll: true }); // the next Tab lands on the first link
        } else if (sidebar.contains(document.activeElement)) {
            navToggle.focus({ preventScroll: true });
        }
    };
    const isOpen = () => document.documentElement.classList.contains('nav-open');

    navToggle.addEventListener('click', () => setOpen(true));
    navClose?.addEventListener('click', () => setOpen(false));
    scrim?.addEventListener('click', () => setOpen(false));
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && isOpen()) {
            setOpen(false);
        }
    });
    // Rotating or resizing up to the desktop layout drops the drawer state.
    phoneLayout.addEventListener('change', (event) => {
        if (!event.matches && isOpen()) {
            setOpen(false);
        }
    });
    // Leaving the page from the drawer: close it so Back doesn't return to an open menu.
    window.addEventListener('pagehide', () => setOpen(false));

    // Swipe left to close.
    let drag = null;

    // One finger only: mouse drags and extra touches mid-drag are ignored.
    const canStartDrag = (event) => isOpen() && event.pointerType !== 'mouse' && !drag?.active;
    const ownsPointer = (event) => drag !== null && event.pointerId === drag.id;

    sidebar.addEventListener('pointerdown', (event) => {
        if (canStartDrag(event)) {
            drag = { id: event.pointerId, x: event.clientX, y: event.clientY, dx: 0, t: performance.now(), active: false };
        }
    });

    sidebar.addEventListener('pointermove', (event) => {
        if (!ownsPointer(event)) {
            return;
        }
        if (!drag.active) {
            const gesture = swipeGesture(event.clientX - drag.x, event.clientY - drag.y);
            if (gesture === 'scroll') {
                drag = null;
            }
            if (gesture !== 'swipe') {
                return;
            }
            startSwipe(event);
        }
        followFinger(event.clientX);
    });

    const startSwipe = (event) => {
        drag.active = true;
        drag.x = event.clientX; // start tracking from here: no jump
        drag.t = performance.now();
        sidebar.setPointerCapture(event.pointerId);
        sidebar.classList.add('is-dragging');
    };

    const followFinger = (clientX) => {
        const width = sidebar.offsetWidth;
        drag.dx = dragOffset(clientX - drag.x, width);
        sidebar.style.transform = `translateX(${drag.dx}px)`;
        if (scrim) {
            scrim.style.transition = 'none';
            scrim.style.opacity = String(1 + Math.min(drag.dx, 0) / width);
        }
    };

    // Hand back to the CSS transition, which picks up from where the finger left it.
    const releaseSidebar = () => {
        sidebar.classList.remove('is-dragging');
        sidebar.style.transform = '';
        if (scrim) {
            scrim.style.transition = '';
            scrim.style.opacity = '';
        }
    };

    const endDrag = (event) => {
        if (!ownsPointer(event)) {
            return;
        }
        const { active, dx, t } = drag;
        drag = null;
        if (!active) {
            return;
        }
        sidebar.dataset.justDragged = '1';
        setTimeout(() => delete sidebar.dataset.justDragged, 0);
        const close = swipeCloses(dx, performance.now() - t, sidebar.offsetWidth);
        releaseSidebar();
        if (close) {
            setOpen(false);
        }
    };

    // On window, so a finger lifted over the scrim still ends the drag.
    window.addEventListener('pointerup', endDrag);
    window.addEventListener('pointercancel', endDrag);

    // A link tapped right after a swipe shouldn't navigate.
    sidebar.addEventListener('click', (event) => {
        if (sidebar.dataset.justDragged) {
            event.preventDefault();
        }
    }, true);
}

/*
 * Page actions declared with data- attributes. The Content-Security-Policy
 * blocks inline handlers (onclick="..."), so views use these instead:
 *
 *   <form data-confirm="Delete this?">      asks "Do you want to proceed?" first
 *   <form data-confirm-changes>              same, listing the changed fields (confirm.js)
 *   <select data-autosubmit>                 submits its form when changed
 *   <button data-print>                      opens the print dialog
 *   <button data-show="id" data-hide="id">   shows / hides elements by id
 */
document.addEventListener('submit', async (event) => {
    const form = event.target;
    if (!needsConfirmation(form)) {
        return;
    }
    if (form.dataset.confirmed) {
        delete form.dataset.confirmed; // the user already said yes: let it through once
        return;
    }
    event.preventDefault();
    const submitter = event.submitter;
    if (await confirmSubmit(form)) {
        form.dataset.confirmed = '1';
        form.requestSubmit(submitter);
    }
});

document.addEventListener('input', (event) => {
    if (event.target.matches?.('[data-digits-only]')) {
        keepDigitsOnly(event.target);
    }

    // While typing, an error already showing clears as soon as the number is right.
    if (event.target.matches?.('[data-phone-number]')) {
        const field = event.target.closest('[data-phone-group]');
        if (field.querySelector('[data-phone-box]').classList.contains('is-invalid')) {
            refreshPhoneProblem(field);
        }
    }
});

// Leaving the box is when an unfinished number counts as wrong.
document.addEventListener('focusout', (event) => {
    if (event.target.matches?.('[data-phone-number]')) {
        refreshPhoneProblem(event.target.closest('[data-phone-group]'));
    }
});

// Phone fields: the country picked sets the code shown, length limit, placeholder and hint.
function applyPhoneField(select) {
    const field = select.closest('[data-phone-group]');
    applyPhoneLimits(select, field.querySelector('[data-phone-number]'), field.querySelector('[data-phone-hint]'));
    showPhoneCountry(select, field.querySelector('[data-phone-iso]'), field.querySelector('[data-phone-dial]'));
}

document.querySelectorAll('[data-phone-country]').forEach(applyPhoneField);

initPatientPickers();

document.addEventListener('click', (event) => {
    const button = event.target.closest?.('[data-copy-password]');
    if (button) {
        copyPassword(button);
    }
});

// Account forms: as soon as an email is typed, check whether another account already uses it.
// The browser also blocks saving while the email is taken; the server checks again on save.
function clearEmailTaken(input) {
    input.setCustomValidity('');
    const wrap = input.closest('[data-email-wrap]');
    wrap?.querySelector('[data-email-feedback]')?.replaceChildren();
    setEmailStatus(input, null);
}

// The icon at the end of the email box: a green check when the email is free, a red cross when it is taken.
function setEmailStatus(input, state) {
    const icon = input.closest('[data-email-wrap]')?.querySelector('[data-email-status]');
    if (!icon) {
        return;
    }
    if (state === 'available') {
        icon.innerHTML = '<i class="bi bi-check-circle-fill text-success" title="Available"></i>';
    } else if (state === 'taken') {
        icon.innerHTML = '<i class="bi bi-x-circle-fill text-danger" title="Already taken"></i>';
    } else {
        icon.replaceChildren();
    }
}

document.addEventListener('input', (event) => {
    if (event.target.matches?.('[data-email-check]')) {
        clearEmailTaken(event.target);
    }
});

// Checked when the email box is left, so a missing or taken email is shown straight away.
document.addEventListener('focusout', (event) => {
    if (event.target.matches?.('[data-email-check]')) {
        checkEmail(event.target);
    }
});

function showEmailMessage(input, message) {
    const feedback = input.closest('[data-email-wrap]')?.querySelector('[data-email-feedback]');
    if (feedback) {
        feedback.textContent = message;
    }
}

async function checkEmail(input) {
    clearEmailTaken(input);

    const email = input.value.trim();
    if (!email) {
        showEmailMessage(input, 'Enter the email address first.');
        return;
    }
    if (!input.checkValidity()) {
        showEmailMessage(input, 'Enter a valid email address.');
        return;
    }
    if (!/@rehabplus\.com$/i.test(email)) {
        showEmailMessage(input, 'Invalid email domain. Account creation is strictly restricted to official @rehabplus.com email addresses.');
        return;
    }

    try {
        const url = new URL(input.dataset.emailCheck, window.location.origin);
        url.searchParams.set('email', email);
        const response = await fetch(url, { headers: { Accept: 'application/json' }, credentials: 'same-origin' });
        if (!response.ok) {
            return;
        }
        const { available, message } = await response.json();
        if (available === false) {
            input.setCustomValidity(message);
            input.closest('[data-email-wrap]').querySelector('[data-email-feedback]').textContent = message;
            setEmailStatus(input, 'taken');
        } else if (available === true) {
            setEmailStatus(input, 'available');
        }
    } catch (error) {
        // Couldn't check right now: the server checks again when the form is saved.
    }
}

// A locked password box explains what to do instead of doing nothing.
document.addEventListener('click', (event) => {
    const locked = event.target.closest?.('[data-password-lock]');
    if (locked?.readOnly) {
        document.querySelector('[data-password-hint]').textContent = 'Click the icon first to generate a temporary password.';
    }
});

// Add Patient: the generate button fills in a temporary password, but only once an email is entered.
document.addEventListener('click', async (event) => {
    const button = event.target.closest?.('[data-generate-password]');
    if (!button) {
        return;
    }

    const email = document.querySelector(button.dataset.emailField);
    const password = document.querySelector(button.dataset.generatePassword);
    const hint = document.querySelector('[data-password-hint]');

    if (!email.value.trim()) {
        hint.textContent = "Enter the patient's email first, then click the button again.";
        hint.classList.add('text-danger');
        email.focus();
        return;
    }
    if (!email.checkValidity()) {
        email.reportValidity();
        return;
    }

    try {
        const response = await fetch(button.dataset.generateUrl, {
            headers: { Accept: 'application/json' },
            credentials: 'same-origin',
        });
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        password.value = (await response.json()).password;
        password.readOnly = false; // from now on the staff member can edit it, or clear it and type their own
        hint.textContent = 'Copy this password now. It is shown again only after you save.';
        hint.classList.remove('text-danger');
    } catch (error) {
        hint.textContent = 'Could not generate a password. Try again.';
        hint.classList.add('text-danger');
    }
});

document.addEventListener('change', (event) => {
    if (event.target.matches?.('[data-phone-country]')) {
        applyPhoneField(event.target);
        refreshPhoneProblem(event.target.closest('[data-phone-group]'));
    }

    if (event.target.matches?.('[data-role-defaults]')) {
        applyRoleDefaults(event.target);
    }

    if (event.target.matches?.('[data-autosubmit]') && event.target.form) {
        event.target.form.requestSubmit(); // runs data-confirm and validation, unlike form.submit()
    }
});

document.addEventListener('click', (event) => {
    const button = event.target.closest?.('[data-print], [data-show], [data-hide]');
    if (!button) {
        return;
    }

    if (button.hasAttribute('data-print')) {
        window.print();
    }
    setHidden(button.dataset.hide, true);
    setHidden(button.dataset.show, false);
});

// Hides or shows the elements whose ids are listed (space-separated) in ids.
function setHidden(ids, hidden) {
    for (const id of (ids ?? '').split(' ').filter(Boolean)) {
        document.getElementById(id)?.toggleAttribute('hidden', hidden);
    }
}