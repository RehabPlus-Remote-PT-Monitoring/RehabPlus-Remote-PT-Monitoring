import { describe, expect, test } from 'vitest';
import { currentSection } from '../../resources/js/public-nav.js';

describe('currentSection', () => {
    const sections = [
        { id: 'visit', top: 130, bottom: 380 },
        { id: 'announcements', top: 420, bottom: 1400 },
        { id: 'patients', top: 1450, bottom: 2100 },
        { id: 'services', top: 2150, bottom: 2600 },
    ];

    test('is null at the top of the page, above the first section', () => {
        expect(currentSection([{ id: 'visit', top: 700, bottom: 1000 }], 220)).toBeNull();
    });

    test('is the section that spans the reading line', () => {
        expect(currentSection(sections, 220)).toBe('visit');
        expect(currentSection(sections, 800)).toBe('announcements');
        expect(currentSection(sections, 1800)).toBe('patients');
    });

    test('a section that starts just under the reading line still counts once it spans it', () => {
        expect(currentSection([{ id: 'about', top: 150, bottom: 900 }], 220)).toBe('about');
    });

    test('in a gap between two sections, the last one that has passed the line stays highlighted', () => {
        expect(currentSection(sections, 400)).toBe('visit');
    });

    test('is null with no sections', () => {
        expect(currentSection([], 220)).toBeNull();
    });
});
