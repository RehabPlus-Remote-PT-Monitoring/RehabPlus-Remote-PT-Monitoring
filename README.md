# RehabPlus patient app

The Android app of the capstone project "Mobile-Based Camera-Assisted Remote
Physical Therapy Monitoring System" for Rehab+ Physiotherapy & Pilates.
Patients sign in, do the exercises their therapist prescribed in front of the
phone camera, and the app counts reps, checks form, and uploads each session
for the therapist to review.

This branch (`camera/monitoring`) holds the Flutter app. The clinic dashboard
that therapists use is a separate Laravel app on the `web/messaging` branch.
iPhone builds are being tested on the `iphone-testing` branch.

## What the app does

- Sign in with the account the clinic created. Change the password in
  Settings, or reset a forgotten one with a temporary password from the
  therapist.
- Show today's prescribed exercises with demo videos.
- Track an exercise live with the camera. ML Kit Pose Detection gives 33 body
  landmarks per frame, and the app turns them into joint angles, rep counts,
  hold timers, and form warnings, with voice and sound feedback.
- Mirror the exercise screen to a TV or laptop with the **Cast** button.
- Log a pain level after each session and upload the session to Firestore.
  Sessions done offline upload later.
- Show progress charts, goals, and a progress report.
- Chat with the therapist and with the clinic, receive push notifications,
  and get a daily exercise reminder scheduled on the phone.
- Settings: dark mode, notification preferences, app lock (PIN or
  fingerprint/face), and Terms and Privacy Policy consent.
- Phone and tablet layouts. Tablets get a sidebar and split views.

Supported exercises: knee extension, straight leg raise, knee flexion, heel
slides, sit-to-stand, glute bridge, bicep curl, forward raise, side raise,
forward push, single-leg balance, wall sit, mini squat, standing hip
abduction, standing hamstring curl, marching in place, and overhead arm
raise. Their codes are listed in [API_CONTRACT.md](API_CONTRACT.md#exercise-types).

## How it fits together

The app and the dashboard never call each other. Both read and write the same
Firebase project (`rehabplus-80675`):

- **Firebase Auth**: patient and staff accounts.
- **Cloud Firestore**: profiles, prescriptions, sessions, messages, goals, and
  notifications. The phone talks to Firestore directly, so `firestore.rules`
  limits every patient to their own documents and checks field types and
  sizes.
- **Firebase Cloud Messaging**: push notifications. The project is on the
  free Spark plan with no Cloud Functions, so the dashboard sends the pushes.

[API_CONTRACT.md](API_CONTRACT.md) is the agreement between the two programs:
every Firestore path and field, who writes it, and who reads it. Read it
before you change any data. [handoff.md](handoff.md) records the project's
status.

## Project structure

```
lib/
  main.dart              App entry point
  firebase_options.dart  Firebase client config (public, committed)
  core/                  Palette, responsive layout, diagnostics
  models/                Exercise, session, prescription, chat, goal models
  screens/               One file per screen (login, dashboard, exercise,
                         pose detector, history, messages, settings, ...)
  services/              Auth, Firestore access, pose geometry, form checks,
                         push, reminders, cast, app lock
  widgets/               Shared UI: charts, sidebar, pose painter
  legal/                 Terms and Privacy Policy text
test/                    Unit and widget tests
tool/rules-test/         Firestore rules tests (emulator)
tool/seed/               Node scripts that seed test data
tool/backfill-phone/     One-off script that fills in patient phone numbers
android/                 Android project (package com.rehabplus.app, minSdk 28)
firestore.rules          Security rules for the app's Firestore access
API_CONTRACT.md          Data contract shared with the dashboard
handoff.md               Project status and notes
```

## Run the app

Before you begin, install Flutter (the team uses 3.41.2) and connect a phone
running Android 9 or later with USB debugging on. The camera features need a
real device.

```bash
flutter pub get
flutter run
```

The Firebase client config is committed, so a fresh clone builds without extra
setup. Sign in with a patient account created from the clinic dashboard.

## Test

To run the Dart tests and the analyzer:

```bash
flutter test
flutter analyze
```

To test `firestore.rules` against the Firestore emulator (needs Node.js and the
Firebase CLI):

```bash
cd tool/rules-test
npm install
npm test
```

To deploy changed rules:

```bash
firebase deploy --only firestore:rules --project rehabplus-80675
```

## Team

- Pauli, Richmond (paulirichmond)
- Alberto, Kenji (Keshin0)
- Combes, Clarence Izaac (rarararlll)
- Torrecampo, Rodel II (sekendd)
- Pomarejos, Rob Thomas (Haddeessss)
