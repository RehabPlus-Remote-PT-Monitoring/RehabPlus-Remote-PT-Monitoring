# RehabPlus clinic dashboard (Laravel app)

This folder is the Laravel 12 app behind the RehabPlus clinic dashboard. For
what it does, how to run it, and how it deploys, see the
[repository README](../README.md).

Quick reference, run from this folder:

```bash
composer run setup   # install dependencies, create .env, build assets
composer run dev     # web server, log viewer, and Vite
composer test        # PHPUnit tests
npm test             # Vitest tests
```

More notes:

- [docs/MESSAGING.md](docs/MESSAGING.md): patient messaging setup.
- [docs/DIAGNOSTICS.md](docs/DIAGNOSTICS.md): diagnostics and troubleshooting.
