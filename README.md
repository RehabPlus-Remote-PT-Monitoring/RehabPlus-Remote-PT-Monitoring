# RehabPlus clinic dashboard

The web dashboard of the capstone project "Mobile-Based Camera-Assisted Remote
Physical Therapy Monitoring System" for Rehab+ Physiotherapy & Pilates. Clinic
staff use it to manage patients, prescribe home exercises, review the sessions
patients record with the RehabPlus phone app, and reply to their messages.

This branch (`web/messaging`) holds the dashboard, a Laravel 12 app in
[`laravel-app/`](laravel-app/). The patient app is a separate Flutter app on
the `camera/monitoring` branch.

## What the dashboard does

- Public site: home page, Remote Monitoring page, FAQ, Terms, and Privacy
  Policy.
- Staff sign-in for two roles, `admin` and `therapist`, with password reset.
- Patients: add, edit, archive, restore, and permanently delete; phone fields
  with a country code; give a patient a temporary password; see the
  patient's Terms and Privacy Policy consent.
- Exercise prescriptions, assessments, goals, and clinical notes. Patients
  are notified in the app when their care plan changes.
- Session review: compliance, pain levels, and progress from the sessions the
  patient app uploads.
- Messages: reply to each patient's therapist thread and clinic thread.
- Appointments, staff schedules and time off, billing with printable
  receipts, and inventory.
- Announcements to patients (archive, restore, and delete), a notification
  bell with upcoming appointments for therapists, and reports with CSV and
  PDF export (admin only).
- Staff accounts with photos (admin only), and My Profile for every staff
  member.
- Evening exercise reminders: a scheduled GitHub Action calls
  `POST /cron/exercise-reminders`, and the dashboard pushes a reminder to
  patients who haven't done today's exercises.
- Dark mode. Times are shown in Philippine time.

## How it fits together

The dashboard and the patient app never call each other. Both read and write
the same Firebase project (`rehabplus-80675`): Firebase Auth for accounts,
Cloud Firestore for all data, and Firebase Cloud Messaging for pushes. There
is no SQL database.

- The dashboard calls Firestore over its REST API with a service account, so
  it runs on Vercel without the gRPC PHP extension.
- A service account skips Firestore security rules, so the dashboard checks
  permissions in PHP: role middleware on routes, and a check that a
  therapist only reaches their own patients.
- The Firebase project is on the free Spark plan with no Cloud Functions, so
  the dashboard sends every push notification.

`API_CONTRACT.md` on the `camera/monitoring` branch lists every Firestore path
and field, and which program writes it.

## Project structure

```
laravel-app/
  app/Http/Controllers/  One controller per area (patients, messages, billing, ...)
  app/Services/          Business logic and Firestore access, by area
  app/Services/Firebase/ Firestore REST client, Auth, push, access tokens
  resources/views/       Blade templates
  resources/js/, css/    Dashboard scripts and styles (built by Vite)
  routes/web.php         Every URL and the roles allowed to use it
  config/clinic.php      Clinic name, address, and footer pages
  tests/                 PHPUnit tests (Feature, Unit) and Vitest tests (js)
  api/index.php          Vercel entry point
  vercel.json            Vercel build and routing
  docs/                  MESSAGING.md and DIAGNOSTICS.md
.github/workflows/vercel-deploy.yml  Deploys laravel-app/ on every push
diagrams/                Firestore schema diagram
docs/                    Capstone Chapters 1 and 2
```

The other files at the repository root (`app/`, `spark`, `public/`,
`composer.json`, and so on) are an earlier CodeIgniter 4 prototype. They
aren't built or deployed.

## Run it locally

Before you begin, install PHP 8.2 or later, Composer, and Node.js 22, and get
a service-account key for the Firebase project from a team member. Keep the
key outside the repository and never commit it.

1. Install the dependencies and create `.env`:

   ```bash
   cd laravel-app
   composer run setup
   ```

2. In `laravel-app/.env`, set `FIREBASE_API_KEY` and either
   `FIREBASE_CREDENTIALS` (the path to the key file) or
   `FIREBASE_CREDENTIALS_JSON` (the key's contents). `.env.example` explains
   each variable.

3. Start the web server, the log viewer, and Vite together:

   ```bash
   composer run dev
   ```

4. Open http://localhost:8000 and sign in with a staff account.

## Test

To run the PHP tests and the JavaScript tests from `laravel-app/`:

```bash
composer test
npm test
```

## Deploy

Pushing to `web/messaging` runs `.github/workflows/vercel-deploy.yml`, which
deploys `laravel-app/` to Vercel. The workflow file lists the repository
secrets it needs. `APP_KEY` and the `FIREBASE_*` variables are set in the
Vercel project.

## Team

- Pauli, Richmond (paulirichmond)
- Alberto, Kenji (Keshin0)
- Combes, Clarence Izaac (rarararlll)
- Torrecampo, Rodel II (sekendd)
- Pomarejos, Rob Thomas (Haddeessss)
