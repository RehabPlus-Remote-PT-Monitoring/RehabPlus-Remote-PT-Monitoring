# Handoff: RehabPlus patient app (branch `camera/monitoring`)

_Last updated: 18 Oct 2026_

## 1. Goal

This is the capstone project **"Mobile-Based Camera-Assisted Remote Physical Therapy Monitoring System"** for Rehab Plus Physiotherapy. It has three parts:

- **Patient app (this repo):** a Flutter Android app.
  - Patients sign in, see the exercises their therapist prescribed, and do them in front of the camera. Pose detection (ML Kit / BlazePose) counts the reps and scores compliance.
  - After each session the patient logs a pain level.
  - The app also tracks progress and lets the patient message their therapist and the clinic.
- **Web admin:** Laravel, in a separate repo (`sekendd/rehabplus2`). It still uses SQLite and has to be moved to Firestore. Therapists will use it to assign prescriptions, review sessions and reply to messages.
- **Database:** Firebase project **`rehabplus-80675`** on the Spark (free) plan.
  - Uses Auth, Firestore and Cloud Messaging.
  - **No Cloud Functions**, so anything server-side runs from Laravel. For now it runs from the Node scripts in `tool/seed/`.

[API_CONTRACT.md](API_CONTRACT.md) is the agreement between the app and Laravel. It covers the Firestore schema, the exercise type codes, how the dashboard metrics are calculated, and the push notification rules. Read it before touching data.

## 2. Current state

**Nothing in this list has been committed yet.** All of it is uncommitted on `camera/monitoring`.

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
| Exercises page split into "Your Plan" (prescriptions, with weekly progress bar) and "All Exercises" (rest of the 12-exercise catalog, no bar, saved with `prescriptionId: null`) | ✅ Built, analyze clean. **Not yet tested on the phone** |
| Firestore security rules | ✅ Deployed |
| `flutter analyze`: no issues. `flutter test`: 9 passing | ✅ |

**Test data**
- Patient `rob@rehabplus.com` (uid `pVRhO9k4pybGItH5IyAJbV0f8aC3`) is seeded. He has 3 prescriptions: kneeExtension, bicepCurl and sideRaise.
- A second account, "kenji", exists in Auth but **may not be seeded yet**.

**Test phone:** OPPO/OnePlus CPH2773 (ColorOS, Android 14), connected over adb.

**Service-account key:** stored at `~/keys/rehabplus-80675-firebase-adminsdk-fbsvc-<id>.json`, **outside the repo**.
- Never commit it.
- `.gitignore` also blocks `*service-account*.json` and `*-firebase-adminsdk-*.json`.

## 3. Files being worked on

**New (untracked)**
- `lib/core/app_keys.dart`: the global navigator and ScaffoldMessenger keys, so push handlers can show UI.
- `lib/models/chat.dart` and `lib/services/chat_service.dart`: the message threads and messages.
- `lib/models/app_notification.dart` and `lib/services/notification_service.dart`: the notifications list, unread count, mark read, and the session-completed log.
- `lib/services/push_service.dart`: FCM permission, token registration, and the foreground and tap handlers.
- `lib/services/progress_stats.dart`: pure helpers for the dashboard and checklist stats. These are unit tested.
- `lib/widgets/unread_badge.dart`: the `UnreadNotifications` builder (live unread count).
- `lib/widgets/today_checklist_sheet.dart`: the "Today's Plan" bottom sheet.
- `test/progress_stats_test.dart`.
- `tool/seed/reply.mjs`: sends a staff reply (message, thread update, notification doc and FCM push).

**Modified**
- **App wiring:** `lib/main.dart` and `lib/services/app_provider.dart`.
- **Screens:** `lib/screens/` dashboard, exercise_page, notification_page, messages_screen, profile, edit_profile and login_page.
- **Models and services:** `lib/models/prescription.dart` and `lib/services/profile_service.dart`.
- **Firebase:** `firestore.rules` and `firebase.json`.
- **Android:** `AndroidManifest.xml` (tel: dial query, default notification channel) and `MainActivity.kt` (creates the `chat_messages` channel).
- **Tooling and docs:** `tool/seed/seed.mjs`, `API_CONTRACT.md`, `pubspec.yaml` / `pubspec.lock`, and `.gitignore`.
- **Generated:** the plugin registrants for linux, macos and windows. These are generated files; commit them along with the pubspec changes.

**Deleted earlier by the user (legacy):** home_screen, new_home_screen, exercise_card, compliance_meter, exercise.dart, pose_data, compliance_tracker and pose_estimation_service.

## 4. What changed (by feature)

1. **Backend wiring**
   - FirebaseAuth sign-in replaced the sample account.
   - `SessionStorage`, `ProfileService` and `PrescriptionService` now read and write Firestore.
   - Writes are *not awaited*: Firestore's offline cache acts as the write queue, so the UI never blocks on the network.
2. **Sessions**
   - New fields: `painLevel`, `painNote`, `rejectedReps`, `prescriptionId`, `outsideSchedule` and `endedEarly`.
   - A pain slider appears on the completion dialog, and the patient is asked to confirm before ending early.
3. **Dashboard**
   - All stats come from `ProgressStats` over `sessionHistory`.
   - Sessions with `endedEarly` don't count as "done".
4. **Messaging**
   - Data lives at `patients/{uid}/threads/{therapist|clinic}/messages`.
   - Unread counters are kept for both sides.
   - Clinic prompt chips: book visit, home visit, report a problem.
5. **Push**
   - The device token is saved to `patients/{uid}/devices/{token}`.
   - Foreground messages show a SnackBar; tapping a push opens the chat.
6. **Notifications page**
   - Live from `patients/{uid}/notifications`.
   - All / Read / Unread filters, mark all read, and tapping a message opens its chat.
   - **Where entries come from:**
     - `reply.mjs` (Laravel later) writes one doc for every push.
     - The app logs `session_completed` docs, saved already read.
     - `seed.mjs` writes `exercise_assigned` docs.
7. **Exercises page**
   - The bell opens Notifications (with the real badge), and ✅ opens Today's Plan.
   - The date is the real date, and the dead "+" button is gone.
8. **Security rules**
   - Patients can only create their own sessions and edit only phone and date of birth on their profile.
   - In notifications, a patient can only create `session_completed` docs and can only change `read` to true.
   - Staff access is limited to the patients they care for (`caresFor`); admins can read everything.

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
- **Process slips to avoid repeating:**
  - An accidental `git stash` (restored with `git stash pop --index`).
  - `dart format` touched an unrelated file (reverted).
  - A bulk `rm` was blocked; the user deleted the legacy files manually.

## 6. What to do next

1. **Test on the phone:**
   - Build and install with `flutter run`.
   - Then: `cd tool/seed && node reply.mjs ~/keys/rehabplus-80675-firebase-adminsdk-*.json rob@rehabplus.com therapist "test"`.
   - Check that the bell badge lights up, that the entry shows on the Notifications page, and that tapping it opens the chat.
   - Finish an exercise and check for the "Exercise Completed" entry and the tick in Today's Plan.
2. **Seed kenji, if needed:**
   - Run `node seed.mjs <key> <kenji-email> [therapist-email]`.
   - ⚠️ `seed.mjs` overwrites the patient's phone and date of birth, so don't re-run it on accounts with real data.
3. **Commit, but only when the user asks:**
   - Don't commit: the service-account key, or any Claude `settings.json`.
   - Decide whether to commit `lib/firebase_options.dart`. It is gitignored right now; committing it is recommended, because it holds no secrets and teammates need it to build.
4. **Laravel admin (`sekendd/rehabplus2`):** move it from SQLite to Firestore using `kreait/laravel-firebase`, following [API_CONTRACT.md](API_CONTRACT.md):
   - Staff accounts: `users/{uid}` with role `therapist` or `admin`, and `patients.therapistId` for the `caresFor` rule.
   - Create and edit prescriptions. Write an `exercise_assigned` notification each time and send a push.
   - A session review screen (compliance, pain, ended-early).
   - Message replies, following what `reply.mjs` does: message, then thread update with `unreadForPatient`, then notification doc, then FCM v1 push with `channel_id: chat_messages`, then delete dead tokens.
5. **Smaller items:**
   - Remove the unused `uuid` dependency.
   - Add exercise reminders (`reminder` type). These would need a scheduler on the Laravel side, since there are no Cloud Functions.
   - Seed `settings/clinic.phone` with the real clinic number (set the `CLINIC_PHONE` environment variable).
