# Handoff: RehabPlus patient app and clinic dashboard

_Last updated: 18 Oct 2026_

## 1. Goal

This is the capstone project **"Mobile-Based Camera-Assisted Remote Physical Therapy Monitoring System"** for Rehab Plus Physiotherapy. It has three parts:

- **Patient app:** a Flutter Android app, on branch `camera/monitoring` of `paulirichmond/RehabPlus-Remote-PT-Monitoring` (checkout: `~/Documents/RehabPlus-Remote-PT-Monitoring-camera-monitoring`).
  - Patients sign in, see the exercises their therapist prescribed, and do them in front of the camera. Pose detection (ML Kit / BlazePose) counts the reps and scores compliance.
  - After each session the patient logs a pain level.
  - The app also tracks progress and lets the patient message their therapist and the clinic.
- **Clinic dashboard:** Laravel 12, in `laravel-app/` on branch `web/messaging` of the same GitHub repo (worktree: `~/Documents/RehabPlus-web-messaging`).
  - It is built on Rodel/sekendd's `updated-admin-dashboard` branch, **not** on `sekendd/rehabplus2` (an older copy set up for hosted MySQL).
  - Therapists add patients, assign exercises, review sessions, record assessments, goals and notes, and reply to messages.
- **Database:** Firebase project **`rehabplus-80675`** on the Spark (free) plan.
  - Uses Auth, Firestore and Cloud Messaging.
  - **No Cloud Functions**, so anything server-side (pushes, account creation) runs from Laravel. The Node scripts in `tool/seed/` remain for testing.

[API_CONTRACT.md](API_CONTRACT.md) is the agreement between the app and Laravel. It covers the Firestore schema, roles, the exercise type codes, how the dashboard metrics are calculated, and the push notification rules. Read it before touching data.

## 2. Current state

Everything is **committed and pushed**:
- `camera/monitoring` at `931abdc` (patient app).
- `web/messaging` at `8250d5a` (dashboard).

Neither branch is merged into `main`.

### Patient app

| Area | Status |
|---|---|
| Android package `com.rehabplus.app`, minSdk 28, Kotlin 2.3.0 | ✅ Builds |
| Firebase sign-in (patients only, checked with `users/{uid}.role == 'patient'`) and forgot password (reset email) | ✅ Working |
| Prescriptions loaded from `patients/{uid}/prescriptions` (active only) into the exercise list | ✅ Working |
| Sessions saved to Firestore: full sessions after the pain dialog, partial ones (`endedEarly`) when the patient backs out | ✅ Working |
| Profile: real data; phone and date of birth editable; Sign Out unregisters the push token | ✅ Working |
| Dashboard: real name, therapist, weekly dots, 7/30/90-day stats with trend arrows | ✅ Working |
| Messaging: therapist and clinic threads, unread badges, "call clinic" button | ✅ Working |
| Push notifications on the "chat_messages" high-importance channel | ✅ Tested end to end on the phone |
| Notifications page backed by Firestore, unread bell badge on the dashboard and Exercises page | ✅ Built, analyze clean, tests pass. **Not yet tested on the phone** |
| Exercises page "Today's Plan" checklist sheet and its badge | ✅ Built. **Not yet tested on the phone** |
| Exercises page split into "Your Plan" (prescriptions, with weekly progress bar) and "All Exercises" (rest of the 17-exercise catalog, no bar, saved with `prescriptionId: null`) | ✅ Built, analyze clean. **Not yet tested on the phone** |
| 5 new exercises: Mini Squat, Standing Hip Abduction, Standing Hamstring Curl, Marching in Place, Overhead Arm Raise (geometry in `lib/services/exercise_geometry.dart`, unit-tested; dashboard `ExerciseCatalog` updated) | ✅ Built, tests pass. **Angles not yet tuned on the phone** |
| Firestore security rules | ✅ Deployed |
| `flutter analyze`: no issues. `flutter test`: 9 passing | ✅ |

### Clinic dashboard (`laravel-app/`)

| Area | Status |
|---|---|
| Staff login with Firebase Auth; role from `users/{uid}`: `admin`, `therapist` or `staff` (front desk). No SQL users table | ✅ Tests pass. **No staff account exists yet** (see next steps) |
| Patients: add (also creates the app login with a temporary password), edit, archive (disables the login), reset password. Therapists only see their own patients | ✅ Tests pass. Not yet tried live (would create a real account) |
| Assign exercises (12 app types, reps/holds, sessions per week, days/hours, instructions), stop/resume; sends an `exercise_assigned` notification and push | ✅ Tests pass. Not yet tried live (would notify Rob's phone) |
| Patient profile: weekly adherence, accuracy, pain, 14-day pain chart, recent sessions, goals, assessments, notes | ✅ Checked live (read-only) with Rob's data |
| Assessments & Goals and Therapy Notes pages (clinic-only Firestore records) | ✅ Tests pass, pages load live |
| Staff Accounts page (create, rename, change role, disable) and `php artisan rehab:make-admin` | ✅ Tests pass |
| Dashboard, analytics and Patient Statistics (CSV/PDF export) computed from Firestore | ✅ Checked live |
| Messaging: inbox, conversation, reply with notification and push | ✅ Tests pass; earlier live check |
| Dark mode, including the chat bubbles | ✅ Checked |
| Friendly "can't reach Firebase" page / form error instead of a 500 | ✅ Seen live during a network blip |
| Appointments, billing, inventory, staff schedule | Still on SQL (SQLite locally; the team uses MySQL/XAMPP). Therapist and staff names come from Firebase |
| `php artisan test`: 73 passing (all against an in-memory Firebase fake, no network) | ✅ |

**Test data**
- Patient `rob@rehabplus.com` (uid `pVRhO9k4pybGItH5IyAJbV0f8aC3`) is seeded. He has 3 prescriptions: kneeExtension, bicepCurl and sideRaise. He has no therapist assigned and no sessions yet.
- A second account, "kenji", exists in Auth but **may not be seeded yet**.
- Firebase has **no staff accounts**. The only `users` docs are the 2 patients.

**Test phone:** OPPO/OnePlus CPH2773 (ColorOS, Android 14), connected over adb.

**Service-account key:** stored at `~/keys/rehabplus-80675-firebase-adminsdk-fbsvc-<id>.json`, **outside the repo**.
- Never commit it.
- `.gitignore` also blocks `*service-account*.json` and `*-firebase-adminsdk-*.json`.
- The dashboard points to it from `laravel-app/.env` (`FIREBASE_CREDENTIALS`, git-ignored). `.env` also needs `FIREBASE_PROJECT_ID` and `FIREBASE_API_KEY` (the public Web API key from `google-services.json`, used to check staff passwords), with `SESSION_DRIVER=file` and `CACHE_STORE=file`.

## 3. Where things are

**Patient app**
- `lib/core/app_keys.dart`: the global navigator and ScaffoldMessenger keys, so push handlers can show UI.
- `lib/models/chat.dart` and `lib/services/chat_service.dart`: the message threads and messages.
- `lib/models/app_notification.dart` and `lib/services/notification_service.dart`: the notifications list, unread count, mark read, and the session-completed log.
- `lib/services/push_service.dart`: FCM permission, token registration, and the foreground and tap handlers.
- `lib/services/progress_stats.dart`: pure helpers for the dashboard and checklist stats (unit tested in `test/progress_stats_test.dart`).
- `lib/widgets/unread_badge.dart` and `lib/widgets/today_checklist_sheet.dart`.
- `tool/seed/seed.mjs` (test patient) and `tool/seed/reply.mjs` (staff reply with notification and push).
- `firestore.rules`, `API_CONTRACT.md`.

**Dashboard (`laravel-app/`)**
- `app/Auth/`: `StaffUser` (roles and permissions) and `FirebaseUserProvider` (loads `users/{uid}` per request, cached 2 min).
- `app/Services/Firebase/`: `FirestoreClient` (REST, including collection-group queries), `FirebaseAdmin` (Auth accounts, password check, FCM), `PatientNotifier` (notification doc and push).
- `app/Services/Patient/`: `PatientService` (access rules, create/edit/archive), `PrescriptionService`, `PatientProgress` (session metrics), `ClinicalRecordService` (assessments, goals, notes), `ExerciseCatalog` (must match the app's `ExerciseType`).
- `app/Services/User/UserService.php` (staff accounts), `app/Services/Messaging/MessagingService.php`.
- `app/Console/Commands/MakeAdmin.php` (`rehab:make-admin`).
- `bootstrap/app.php`: Firebase errors become a 503 page (GET) or a flash message (forms).
- `tests/Support/FakeFirebase.php`: in-memory Firestore/Auth/FCM used by every feature test.

## 4. What changed (by feature)

1. **Backend wiring (app)**
   - FirebaseAuth sign-in replaced the sample account.
   - `SessionStorage`, `ProfileService` and `PrescriptionService` now read and write Firestore.
   - Writes are *not awaited*: Firestore's offline cache acts as the write queue, so the UI never blocks on the network.
2. **Sessions**
   - New fields: `painLevel`, `painNote`, `rejectedReps`, `prescriptionId`, `outsideSchedule` and `endedEarly`.
   - A pain slider appears on the completion dialog, and the patient is asked to confirm before ending early.
3. **App dashboard**
   - All stats come from `ProgressStats` over `sessionHistory`.
   - Sessions with `endedEarly` don't count as "done".
4. **Messaging**
   - Data lives at `patients/{uid}/threads/{therapist|clinic}/messages`.
   - Unread counters are kept for both sides.
   - Clinic prompt chips: book visit, home visit, report a problem.
   - On the dashboard, therapists answer the `therapist` thread of their own patients; admins and front desk answer the `clinic` thread.
5. **Push**
   - The device token is saved to `patients/{uid}/devices/{token}`.
   - Foreground messages show a SnackBar; tapping a chat push opens the chat.
   - The dashboard sends `data: {type: 'chat', thread}` for replies and `{type: 'exercise_assigned'}` for new exercises.
6. **Notifications page**
   - Live from `patients/{uid}/notifications`.
   - All / Read / Unread filters, mark all read, and tapping a message opens its chat.
   - **Where entries come from:**
     - The dashboard (and `reply.mjs`) writes one doc for every push: `message` and `exercise_assigned`.
     - The app logs `session_completed` docs, saved already read.
     - `seed.mjs` writes `exercise_assigned` docs.
7. **Exercises page**
   - The bell opens Notifications (with the real badge), and ✅ opens Today's Plan.
   - The date is the real date, and the dead "+" button is gone.
8. **Security rules**
   - Patients can only create their own sessions and edit only phone and date of birth on their profile.
   - In notifications, a patient can only create `session_completed` docs and can only change `read` to true.
   - Staff access is limited to the patients they care for (`caresFor`); admins can read everything.
   - Assessments, goals and notes have no rule, so the app can't read them (clinic-only).
9. **Dashboard moved to Firebase**
   - Accounts: a patient is a Firebase Auth login, plus `users/{uid}` (role `patient`) and `patients/{uid}`. A staff member is a login plus `users/{uid}` with their role.
   - New patient fields: `email`, `archived`, `createdBy`, `updatedAt`. New `users` field: `active`.
   - New clinic-only collections: `patients/{uid}/assessments`, `/goals` and `/notes` (schema in API_CONTRACT.md).
   - Nothing is deleted: patients are archived and staff are disabled, because sessions, notes and messages refer to their uid.
   - Removed: the SQL `User`/`Patient`/`ExerciseRecord` models, manual exercise records and the web patient portal (patients use the app).
10. **Terms and Conditions + Privacy Policy (app)**
   - The documents are `assets/legal/terms_and_conditions.md` and `assets/legal/privacy_policy.md`, written for the Philippine Data Privacy Act (RA 10173) and the E-Commerce Act (RA 8792). Clinic details are `{{TOKENS}}` filled from `lib/legal/legal_info.dart`.
   - After sign-in, `ConsentScreen` blocks the app until the patient ticks three boxes (terms, health-data consent, camera) and taps **Accept and continue**. Declining signs them out.
   - Acceptance is an append-only record at `patients/{uid}/consents/{version}` (schema in API_CONTRACT.md). Bumping `LegalInfo.version` makes everyone accept again.
   - Profile > **Privacy & Legal** opens a page with three choices: **Account Info** (name, email, phone, date of birth, with an "Update account information" button), **Terms and Conditions** and **Privacy Policy**.
   - **Progress report** (app): Home has a "How you're doing" card under Weekly Progress (follows the 7/30/90 selector), and "See full report" / the Progress chip open `ProgressReportScreen`: a verdict (Doing great / On track / Needs attention), plain-language findings, key numbers, sessions / form score / pain charts (fl_chart) and a per-exercise breakdown. The logic is pure and unit-tested in `lib/services/progress_report.dart`; plan adherence uses the active prescriptions' `frequencyPerWeek` from their `createdAt`. High or rising pain always gives "Needs attention" and tells the patient to contact their therapist.
   - Profile > **Settings** (`lib/screens/settings_screen.dart`): rep sound, vibration, spoken cues (flutter_tts), start countdown, default camera, show/flip skeleton, daily reminder (flutter_local_notifications, scheduled on the phone), push preferences (`patients/{uid}/preferences/notifications`, honoured by the dashboard's `PatientNotifier`), text size, change password, camera access, Help & Support, call the clinic, report a problem (sent to the clinic chat with recent errors) and app version. Phone-only settings are in `lib/services/app_settings.dart` (SharedPreferences).
   - Patients can now edit their own name as well as phone and date of birth (`patients/{uid}.name`, rules allow 1–100 chars). The email stays clinic-managed because it is the login. `users/{uid}.name` is not updated by the app.
   - Settings > Account > **App lock** (optional, off by default): a 4-digit PIN, with fingerprint/face as a shortcut, asked before the dashboard when the app opens (`main.dart` shows `AppLockScreen.startup` instead of the consent gate) and when coming back after 1+ minute in the background (`AppLockRouter` pushes `AppLockScreen.resume`). Phone-only: a salted, stretched SHA-256 hash in flutter_secure_storage, nothing in Firestore. 5 wrong PINs in a row (count survives restarts) or "Forgot PIN" signs the patient out; signing out also removes the PIN. Turning it off or changing the PIN asks for the current one first. When the lock is off, `ConsentScreen.gate()` / accept show `AppLockOfferScreen` before the dashboard (after sign-in, and once at startup for existing users): Set up PIN, then Use fingerprint if the phone has one, or "Not now", remembered per uid on the phone and kept across sign-out. Code: `lib/services/app_lock_service.dart`, `lib/screens/app_lock_screen.dart`, `lib/screens/app_lock_settings_screen.dart`; tests in `test/app_lock_test.dart`. `MainActivity` is now a `FlutterFragmentActivity` (needed by local_auth).
   - The rule was checked against the Firestore emulator (11 cases: only the patient can create it, all three consents required, server time only, no edits or deletes).

## 5. What was tried and failed (and the fix)

- **Kotlin metadata error from firebase_auth:** fixed by bumping Kotlin to 2.3.0. That broke `jvmTarget = "17"` (a String); fixed by moving to `kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }`. I also removed a forced kotlin-stdlib 1.9.0.
- **Push "delivered" but nothing appeared on the phone:**
  - The logs showed it went to `fcm_fallback_notification_channel` at importance 3. ColorOS hides banners on that channel.
  - Fixed by creating a high-importance `chat_messages` channel in `MainActivity` and making it the default in the manifest. The server also sends `android.notification.channelId = chat_messages`.
- **FCM token API:** `getToken`, `onTokenRefresh` and `deleteToken` are deprecated in firebase_messaging 17. They are kept on purpose because firebase-admin can't yet send to the replacement API. Each use has a `// ignore: deprecated_member_use` with that reason.
- **Widget smoke test failing (it was failing before this work):**
  - Fixed by passing `signedIn` into `RehabPlusApp` from `main()`, making `SessionStorage._db` lazy, and using `pumpAndSettle`.
- **Dashboard showed "Rob Thomas" after signing in as kenji:**
  - The name was hardcoded, and the provider state wasn't cleared on sign-out.
  - Fixed: the name comes from the profile, and `signOut()` clears all state.
- **`firebase deploy` printed "unexpected error"/timeout:** the rules release actually succeeded (HTTP 200). Check the console before redeploying.
- **`adb install` hung:** the phone was waiting for the "Install via USB" prompt to be approved on screen.
- **Dashboard: patient chat bubble unreadable in dark mode:** Bootstrap's `bg-body-secondary` isn't themed by the dark CSS. Fixed with dedicated `.chat-bubble-*` classes.
- **Dashboard tests: every fake request ran twice:** Laravel calls `setUp<TraitName>()` on test traits automatically, so calling `setUpFakeFirebase()` again registered the fake twice. Don't call it yourself.
- **Renaming a patient reported an error although it saved:** the Auth display-name sync ran after the Firestore write. It is now best-effort (logged, not shown).
- **Older seeded patients have no `email` field:** the profile falls back to `users/{uid}.email`.
- **Process slips to avoid repeating:**
  - An accidental `git stash` (restored with `git stash pop --index`).
  - `dart format` touched an unrelated file (reverted). Pint's default preset does the same in Laravel; only run it on files you changed.
  - A bulk `rm` was blocked; the user deleted the legacy files manually.
  - The browser-automation tool shares the user's real browser. An open dashboard tab that polls messages overwrote the test session; use an isolated browser session.

## 6. What to do next

1. **Create the first dashboard admin** (the password is typed by you):
   - `cd ~/Documents/RehabPlus-web-messaging/laravel-app && php artisan rehab:make-admin <email> "<name>"`
   - Then sign in at `http://127.0.0.1:8000` and add a therapist under Staff Accounts.
2. **End-to-end test with the phone:**
   - Assign Rob to the therapist (edit Rob as admin), then sign in as the therapist.
   - Assign an exercise: check the push and the Notifications entry on the phone, and that it appears in Your Plan.
   - Do a session on the phone: check it shows on Rob's profile (adherence, accuracy, pain).
   - Reply to a message from the dashboard: check the bell badge, the Notifications entry, and that tapping opens the chat.
   - Finish an exercise and check for the "Exercise Completed" entry and the tick in Today's Plan.
   - Add a test patient from the dashboard and sign in with it on the phone, then archive it (the login should stop working).
3. **Seed kenji, if needed:**
   - Run `node seed.mjs <key> <kenji-email> [therapist-email]`.
   - ⚠️ `seed.mjs` overwrites the patient's phone and date of birth, so don't re-run it on accounts with real data.
   - Or just add kenji's patient profile from the dashboard instead.
4. **Repo housekeeping:**
   - Decide whether to commit `lib/firebase_options.dart`. It is gitignored right now; committing it is recommended, because it holds no secrets and teammates need it to build.
   - In the dashboard worktree, a root `package.json` / `package-lock.json` change and `node_modules/` (dependency `headroom-ai`) appeared from outside this work and are uncommitted. Remove them or add `node_modules/` to `.gitignore`.
   - Ask sekendd/Rodel to push their latest local code: their database dump has a `drop_super_admins_table` migration that isn't on GitHub. Rebase `web/messaging` on it. Decide which dashboard copy is the main one (`updated-admin-dashboard` vs `sekendd/rehabplus2`).
   - Open pull requests for `camera/monitoring` and `web/messaging`.
5. **Dashboard follow-ups:**
   - Move appointments, billing, inventory and the staff schedule to Firestore too (the user chose "later").
   - The patient profile takes about 2 s to load (6 sequential Firestore reads). Batch or parallelise them if it matters.
   - Optionally let patients see their goals in the app: add a read rule for `goals` and an app screen.
6. **Dark mode:** the Settings page has no theme option yet, because the screens hard-code light colours (about 600 places). The app is locked to light mode (`themeMode: ThemeMode.light` in `lib/main.dart`) until every screen is restyled.
7. **Before patients use the app (legal):**
   - Fill in the placeholders in `lib/legal/legal_info.dart`: clinic address, Data Protection Officer name and email, city for disputes, record-retention period.
   - Have a lawyer or the clinic's DPO review both documents. Register with the National Privacy Commission if the clinic's processing requires it.
   - Show the consent status on the dashboard's patient profile (see API_CONTRACT.md).
8. **Smaller items:**
   - Remove the unused `uuid` dependency (app).
   - Add exercise reminders (`reminder` type). These would need a scheduler on the Laravel side, since there are no Cloud Functions.
   - Seed `settings/clinic.phone` with the real clinic number (set the `CLINIC_PHONE` environment variable). The dashboard has no settings page for it yet.
