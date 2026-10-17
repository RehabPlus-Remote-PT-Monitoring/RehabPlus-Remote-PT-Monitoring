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

---

## Collections

### `users/{uid}`: every account

| Field | Type | Notes |
| --- | --- | --- |
| `role` | string | `patient`, `therapist` or `admin` |
| `name` | string | Display name |
| `email` | string | Same as the Auth email |

Written by: Laravel only.

### `patients/{uid}`: patient profile (same `uid` as `users`)

| Field | Type | Notes |
| --- | --- | --- |
| `name` | string | |
| `condition` | string | e.g. "MCL sprain, post-acute" |
| `therapistId` | string \| null | `uid` of the assigned therapist |
| `therapistName` | string | Copy of the therapist's name. The app shows it, because patients can't read other users' docs. Update it if the therapist changes. |
| `medicalSummary` | string | |
| `therapyPlan` | string | |
| `phone` | string | **Patient-editable** in the app (≤ 30 chars) |
| `dob` | string | **Patient-editable** in the app (≤ 30 chars) |
| `createdAt` | timestamp | |

Written by: Laravel (all fields); the app (only `phone`, `dob`).

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

Service-account keys must never be committed (they're in `.gitignore`).
