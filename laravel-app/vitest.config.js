import { defineConfig } from 'vitest/config';

// Tests for the browser scripts in resources/js (run: npm test; with
// coverage: npm run coverage). Separate from vite.config.js so the Laravel
// plugin isn't loaded for tests.
export default defineConfig({
    test: {
        environment: 'jsdom',
        include: ['tests/js/**/*.test.js'],
        coverage: {
            provider: 'v8',
            include: ['resources/js/**/*.js'],
            // coverage-final.json is what `fallow health` reads (see /.fallowrc.jsonc).
            reporter: ['text', 'json'],
            reportsDirectory: 'coverage',
        },
    },
});
