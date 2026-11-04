/*
 * Highlights the welcome page's nav link for the section the reader is in.
 * At the top of the page no link is highlighted.
 *
 *   <a href="#visit" data-section="visit">Visit us</a>
 *   <div id="visit">...</div>
 */

/**
 * The id of the section being read, or null.
 *
 * It is the section that spans the reading line. If no section spans it (a
 * short gap between two sections), it is the last section whose top has passed
 * the line, so the highlight doesn't flicker off between sections.
 * `sections` is [{id, top, bottom}] in page order, with top and bottom as
 * distances from the top of the viewport.
 */
export function currentSection(sections, readingLine) {
    const spanning = sections.find((section) => section.top <= readingLine && section.bottom > readingLine);
    if (spanning) {
        return spanning.id;
    }

    let last = null;
    for (const section of sections) {
        if (section.top <= readingLine) {
            last = section.id;
        }
    }

    return last;
}

/** Keeps the nav link for the section in view highlighted, as the page scrolls. */
export function initPublicNav(doc = document, win = window) {
    const links = [...doc.querySelectorAll('[data-section]')];
    if (links.length === 0) {
        return;
    }

    const update = () => {
        // The reading line sits a little way below the nav bar, where the eye is.
        const nav = doc.querySelector('.public-nav');
        const readingLine = (nav ? nav.getBoundingClientRect().bottom : 0) + 120;
        const sections = links
            .map((link) => doc.getElementById(link.dataset.section))
            .filter(Boolean)
            .map((el) => {
                const box = el.getBoundingClientRect();

                return { id: el.id, top: box.top, bottom: box.bottom };
            });

        // A page without these sections (such as Remote Monitoring) keeps the highlight it was given.
        if (sections.length === 0) {
            return;
        }

        const active = currentSection(sections, readingLine);
        for (const link of links) {
            link.classList.toggle('is-active', link.dataset.section === active);
        }
    };

    win.addEventListener('scroll', update, { passive: true });
    win.addEventListener('resize', update);
    update();
}

initPublicNav();
