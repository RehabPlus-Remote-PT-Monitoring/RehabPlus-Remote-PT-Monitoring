# RehabPlus Data Contract (Firestore)

The patient app and the Laravel admin dashboard share one Firebase project,
**`rehabplus-80675`**. There is no REST API between them. Both read and write
the same Firestore documents described here.

| Side | Talks to Firestore via | Security rules apply? |
| --- | --- | --- |
| Flutter patient app | `firebase_auth` + `cloud_firestore` | Yes ([firestore.rules](firestore.rules)) |
| Laravel dashboard | Service account (Admin SDK or Firestore REST API) | No, the service account bypasses them |

Because Laravel bypasses the rules, **Laravel must enforce its own
permissions**. For example, a therapist should only see their own patients.

---

## Accounts

Patients cannot sign up in the app. A therapist or admin creates every account
from the dashboard:

1. Create the Firebase Auth user (email + temporary password) with the Admin SDK
   (`createUser`). Its `uid` is the key for everything below.
2. Write `users/{uid}` with the role.
3. For patients, write `patients/{uid}`.

The app rejects any login whose `users/{uid}.role` isn't `patient`.
Patients reset their password from the app (Firebase emails them a link).

Dashboard staff sign in with Firebase Auth too (there is no SQL users table).
The dashboard only lets in `admin`, `therapist` and `staff` roles. The first
admin is created with `php artisan rehab:make-admin <email> "<name>"`.

Archiving a patient disables their Firebase Auth login (so the app can't sign
in) and sets `patients.archived: true`. Nothing is deleted.

---

## Collections

### `users/{uid}`: every account

| Field | Type | Notes |
| --- | --- | --- |
| `role` | string | `patient`, `therapist`, `admin` or `staff` (front desk: clinic inbox and patient contact details, no clinical records) |
| `name` | string | Display name |
| `email` | string | Same as the Auth email (lowercase) |
| `active` | bool | `false` when the login is disabled (staff disabled / patient archived) |
| `createdAt` | timestamp | |

Written by: Laravel only.

### `patients/{uid}`: patient profile (same `uid` as `users`)

| Field | Type | Notes |
| --- | --- | --- |
| `name` | string | **Patient-editable** in the app (1–100 chars). The app doesn't update `users/{uid}.name`; show this one |
| `condition` | string | e.g. "MCL sprain, post-acute" |
| `therapistId` | string \| null | `uid` of the assigned therapist |
| `therapistName` | string | Copy of the therapist's name. The app shows it, because patients can't read other users' docs. Update it if the therapist changes. |
| `medicalSummary` | string | |
| `therapyPlan` | string | |
| `phone` | string | **Patient-editable** in the app (≤ 30 chars) |
| `dob` | string | **Patient-editable** in the app (≤ 30 chars) |
| `email` | string | Login email (lowercase), shown on the dashboard |
| `archived` | bool | `true` = archived on the dashboard; the Auth login is disabled |
| `createdBy` | string | `uid` of the staff member who added the patient |
| `createdAt` | timestamp | |
| `updatedAt` | timestamp | Last dashboard edit |

Written by: Laravel (all fields); the app (only `name`, `phone`, `dob`).

### `patients/{uid}/prescriptions/{id}`: assigned exercises

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `exerciseType` | string | ✔ | One of the codes in [Exercise types](#exercise-types) |
| `targetReps` | int | ✔ | Reps per session (or number of holds) |
| `holdSeconds` | int | | Hold length for hold exercises; omit to use the default |
| `frequencyPerWeek` | int | | Sessions per week (default 3); drives the weekly progress bar |
| `schedule` | map | | When unassisted practice is allowed; omit for "any time" |
| `schedule.days` | int[] | | 1 = Mon … 7 = Sun; empty/omitted = any day |
| `schedule.startHour` | int | | 0–23, inclusive, phone's local time |
| `schedule.endHour` | int | | 0–24, exclusive |
| `notes` | string | | Instructions shown to the patient |
| `active` | bool | ✔ | The app only loads `active == true` |
| `assignedBy` | string | | Therapist `uid` |
| `createdAt` | timestamp | | |
| `updatedAt` | timestamp | | Last dashboard edit |

`holdSeconds`, `schedule` and `notes` may be `null` (same as omitted).
Assigning a prescription also writes an `exercise_assigned` notification doc
and sends a push with `data: {type: 'exercise_assigned'}`.

Written by: Laravel only. To stop an exercise, set `active: false` (don't
delete it, because old sessions still reference its id).

Joint angles are **not** set here. Each exercise type's detection angles are
calibrated in the app (`lib/models/exercise_model.dart`).

### `patients/{uid}/sessions/{id}`: completed exercise sessions

Created by the app when the patient finishes (or ends early) and submits the
pain check-in. **Never updated or deleted.**

| Field | Type | Notes |
| --- | --- | --- |
| `exerciseId` | string | Exercise type code, e.g. `kneeExtension` |
| `exerciseName` | string | e.g. "Knee Extension" |
| `prescriptionId` | string \| null | Prescription doc id it was done for |
| `startTime` | timestamp | |
| `endTime` | timestamp | |
| `createdAt` | timestamp | Server time when received |
| `completedReps` | int | Reps that passed form checks |
| `rejectedReps` | int | Attempts rejected (bad form, short range, too fast) |
| `targetReps` | int | |
| `completedSets` | int | 1 if finished, 0 if ended early |
| `targetSets` | int | |
| `repComplianceScores` | double[] | One per attempt: 1.0 counted, 0.0 rejected |
| `overallCompliance` | double | Mean of the above, 0–1 ("accuracy") |
| `painLevel` | int | 0 (none) – 10 (worst), reported after the session |
| `painNote` | string \| null | Optional note to the therapist (≤ 300 chars) |
| `notes` | string \| null | App-generated summary |
| `outsideSchedule` | bool | Done outside the prescription's `schedule` |
| `endedEarly` | bool | Patient stopped before `targetReps` |

Sessions done offline are uploaded when the phone reconnects, so `createdAt`
can be much later than `startTime`. Use `startTime` for reports.

### `patients/{uid}/threads/{threadId}`: conversation summary

Each patient has two conversations: `threadId` is **`therapist`** (their
assigned therapist) or **`clinic`** (front desk: clinic visits, home-visit
requests, app problems). The doc is created on the first message.

| Field | Type | Notes |
| --- | --- | --- |
| `lastMessage` | string | Preview text of the newest message |
| `lastMessageAt` | timestamp | |
| `lastSenderRole` | string | `patient` or `staff` |
| `unreadForPatient` | int | The app shows this as a badge and resets it to 0 when opened |
| `unreadForStaff` | int | The app adds 1 per patient message; **the dashboard resets it to 0** when staff read the thread |

### `patients/{uid}/threads/{threadId}/messages/{id}`: messages

| Field | Type | Notes |
| --- | --- | --- |
| `text` | string | 1–1000 chars |
| `senderId` | string | Sender's `uid` |
| `senderRole` | string | `patient` or `staff` |
| `sentAt` | timestamp | Sender's clock; **order by this** |
| `createdAt` | timestamp | Server time |

Messages are never edited or deleted.

**When staff reply from the dashboard**, write both in one batch:

1. Add a message with `senderRole: 'staff'`, `senderId: <staff uid>`, `sentAt`
   and `createdAt` set to now.
2. Update the thread: `lastMessage`, `lastMessageAt`,
   `lastSenderRole: 'staff'`, and `unreadForPatient` incremented by 1.

To list conversations needing a reply, query the `threads` collection group
for `unreadForStaff > 0`. The first time, Firestore returns an error with a
link to create the collection-group index this needs. Open it once. Appointment and home-visit requests arrive as
messages in the `clinic` thread.

### Clinic-only records (the app can't read these)

The security rules don't list these subcollections, so the app is denied.
Only the dashboard (service account) reads and writes them. Each record also
stores `therapistId`, `therapistName` (who wrote it) and `createdAt`.

| Path | Fields |
| --- | --- |
| `patients/{uid}/assessments/{id}` | `type` string (≤ 60, e.g. "Range of motion"), `score` int 0–100, `assessedAt` timestamp (start of the day), `notes` string (≤ 1000) |
| `patients/{uid}/goals/{id}` | `title` string (≤ 150), `details` string, `targetDate` timestamp \| null, `status` `active` \| `achieved` \| `discontinued`, `progress` int 0–100 (100 when achieved), `achievedAt` timestamp \| null, `updatedAt` timestamp |
| `patients/{uid}/notes/{id}` | `topic` string (≤ 100), `text` string (≤ 2000), `noteDate` timestamp (start of the day) |

If patients should see their goals in the app later, add a read rule for
`goals` (and an app screen); nothing else needs to change.

### `settings/clinic`: clinic contact details

| Field | Type | Notes |
| --- | --- | --- |
| `name` | string | e.g. "Rehab Plus Physiotherapy" |
| `phone` | string | Number the app's call button dials. If it's empty, the button shows "not set up yet". |

Written by: Laravel only. All signed-in users can read it.

### `patients/{uid}/notifications/{id}`: the app's Notifications page

| Field | Type | Notes |
| --- | --- | --- |
| `type` | string | Sets the icon: `message`, `exercise_assigned`, `appointment`, `progress`, `milestone`, `reminder`, `session_completed` (others get a generic icon) |
| `title` | string | e.g. "New Exercise Assigned" |
| `body` | string | |
| `data` | map | Optional. For `message`: `{ "thread": "therapist" }`, so tapping opens that conversation |
| `read` | bool | Write `false`; the app sets `true` when the patient opens it |
| `createdAt` | timestamp | |

Written by: Laravel (**every time it sends a push, also add one of these**,
and also for events with no push, like a new prescription); the app (only
`session_completed`, logged after each exercise).

### `patients/{uid}/devices/{token}`: push-notification tokens

One doc per phone the patient is signed in on. The doc id is the FCM
registration token.

| Field | Type | Notes |
| --- | --- | --- |
| `token` | string | Same as the doc id |
| `platform` | string | `android` |
| `updatedAt` | timestamp | |

Written by: the app (added at sign-in, removed at sign-out). Read by Laravel
to send notifications.

### `patients/{uid}/preferences/notifications`: which pushes the patient wants

| Field | Type | Notes |
| --- | --- | --- |
| `messages` | bool | `false` = no push for new messages (`data.type: chat`) |
| `exercises` | bool | `false` = no push for new exercises (`data.type: exercise_assigned`) |
| `updatedAt` | timestamp | Server time |

Written by: the app (Settings > Notifications). No doc means both are on.
Laravel's `PatientNotifier::push()` checks it and skips the push (returns
`null`) when that kind is off; the Notifications-page entry is still written.
Other types are always pushed. The daily exercise reminder is scheduled on the
phone and never involves Firestore.

### `patients/{uid}/avatar/photo`: profile picture

| Field | Type | Notes |
| --- | --- | --- |
| `image` | bytes | JPEG, resized by the app to fit 512 × 512 px; at most 500 KB (rule) |
| `updatedAt` | timestamp | Server time |

Written by: the app (the patient sets, replaces or deletes it). No doc means no
picture (show a default icon). Kept out of `patients/{uid}` so patient lists
don't download images. Dashboard: read it with the service account and show it
as a `data:image/jpeg;base64,...` image.

### `patients/{uid}/consents/{version}`: Terms and Privacy Policy acceptance

One doc per version the patient accepted. The doc id is the version
(`LegalInfo.version` in `lib/legal/legal_info.dart`, e.g. `2026-10-18`). The
documents themselves are `assets/legal/terms_and_conditions.md` and
`assets/legal/privacy_policy.md`.

| Field | Type | Notes |
| --- | --- | --- |
| `version` | string | Same as the doc id |
| `acceptedTerms` | bool | Always `true` |
| `acceptedPrivacyPolicy` | bool | Always `true` |
| `healthDataConsent` | bool | Always `true`: consent to process health information (Data Privacy Act, sensitive personal information) |
| `cameraConsent` | bool | Always `true`: on-device camera tracking |
| `acceptedAt` | timestamp | Server time |

Written by: the app, once, when the patient taps **Accept and continue**. The
rules make it append-only (no edits or deletes), so it serves as the audit
record of consent. The app won't open the dashboard until a doc exists for the
current version; bumping the version makes every patient accept again.

Dashboard: show "Accepted terms vX on <date>" on the patient profile, or
"Not yet accepted" (the patient hasn't signed in to the app yet). If a patient
withdraws consent (they message the clinic), archive the patient; don't delete
the consent record.

---

## Push notifications

The free Spark plan can't run Cloud Functions, so **whoever writes a staff
reply also sends the push**. After the reply batch (see messages above), add a
`notifications` doc (type `message`, `data.thread` set), then send one FCM
message per token in `patients/{uid}/devices`:

```json
{
  "message": {
    "token": "<device token>",
    "notification": { "title": "<therapist name or 'RehabPlus Clinic'>", "body": "<message text>" },
    "data": { "type": "chat", "thread": "therapist" },
    "android": { "priority": "high", "notification": { "channel_id": "chat_messages" } }
  }
}
```

- **Endpoint:** `POST https://fcm.googleapis.com/v1/projects/rehabplus-80675/messages:send`,
  authorised with an OAuth token from the service account (scope
  `https://www.googleapis.com/auth/firebase.messaging`). `kreait/laravel-firebase`
  does this for you (`Messaging::send`), and its messaging part doesn't need
  the `grpc` extension.
- **`channel_id: chat_messages`** is the app's high-importance "Messages"
  channel, so the notification pops up on screen. Leave it out and Android
  only shows it quietly in the notification shade.
- **`data.thread`** must be `therapist` or `clinic`. Tapping the notification
  opens that conversation in the app.
- **Dead tokens:** if FCM answers `UNREGISTERED` or `INVALID_ARGUMENT` for a
  token, delete that `devices` doc.
- `tool/seed/reply.mjs` is a working reference implementation.

---

## Exercise types

`exerciseType` / `exerciseId` must be one of these codes (`ExerciseType` in
`lib/models/exercise_model.dart`). An unknown code is skipped by the app.

| Code | Name | Kind | Default |
| --- | --- | --- | --- |
| `kneeExtension` | Knee Extension | reps | 10 |
| `straightLegRaise` | Straight Leg Raise | reps | 10 |
| `kneeFlexion` | Knee Flexion | reps | 10 |
| `heelSlide` | Heel Slides | reps | 10 |
| `sitToStand` | Sit-to-Stand | reps | 10 |
| `gluteBridge` | Glute Bridge | reps | 10 |
| `bicepCurl` | Bicep Curl | reps | 10 |
| `forwardRaise` | Forward Raise | reps | 10 |
| `sideRaise` | Side Raise | reps | 10 |
| `forwardPush` | Forward Push | reps | 10 |
| `singleLegBalance` | Single-Leg Balance | hold | 3 × 10 s |
| `wallSit` | Wall Sit | hold | 3 × 20 s |
| `miniSquat` | Mini Squat | reps | 10 |
| `hipAbduction` | Standing Hip Abduction | reps | 10 |
| `hamstringCurl` | Standing Hamstring Curl | reps | 10 |
| `marching` | Marching in Place | reps | 10 |
| `overheadRaise` | Overhead Arm Raise | reps | 10 |

The last five need a specific camera view: Standing Hip Abduction from the
front; Hamstring Curl, Marching and Overhead Arm Raise side-on; Mini Squat
either way (the knees-caving-in check only works from the front). Older app
builds don't know these codes and skip them.

Adding a new exercise needs an app update (pose detection is per type), not
just a dashboard change.

---

## Dashboard metrics: how to compute them

| Metric | From |
| --- | --- |
| Adherence this week | Count `sessions` per `prescriptionId` with `startTime` in the last 7 days ÷ `frequencyPerWeek` |
| Movement accuracy | Average `overallCompliance` |
| Pain trend | `painLevel` over `startTime` |
| Unassisted-practice alerts | Sessions with `outsideSchedule == true` |
| Incomplete sessions | Sessions with `endedEarly == true` |
| Missed days | Prescription `schedule.days` with no session that day |

---

## Test data

`tool/seed/seed.mjs` creates a test patient with three prescriptions:

```bash
cd tool/seed && npm install
node seed.mjs <service-account.json> <patient-email> [therapist-email]
```

`tool/seed/reply.mjs` sends a staff reply and push notification, standing in
for the dashboard:

```bash
node reply.mjs <service-account.json> <patient-email> <therapist|clinic> "<message>"
```

Service-account keys must never be committed (they're in `.gitignore`).
