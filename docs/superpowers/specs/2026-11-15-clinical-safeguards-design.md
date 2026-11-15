# Clinical safeguards: completion gate, physician clearance, clinical/dietary profile

Date: 2026-11-15. Source: capstone panel verdict "Minimal Revisions".

The panel's required revisions, and where each one lands:

| Revision | Built as |
| --- | --- |
| Clearance gatekeeping (block until every prescribed exercise is complete, list what is missing) | Completion gate computed from prescriptions + sessions, shown on the dashboard and in the app (section 3) |
| Physician authorization (final assessment + manual sign-off, never auto-clear) | `clearances` records written only by the dashboard from a sign-off form; rules forbid every client write (section 4) |
| Dietary & clinical profile (clinician-validated, supplementary context) | `clinical/profile` doc written only from the dashboard (section 2) |
| Clinician-controlled prescriptions (no AI, no diet-driven changes) | Already true: prescriptions are written only by admins/therapists on the dashboard (`firestore.rules` prescriptions match, `role:admin,therapist` routes). Nothing in this feature changes a prescription automatically; the profile only blocks, it never assigns (section 5) |
| Pose estimation metrics | Separate document outside the repo, taken from the code (`~/Documents/RehabPlus-Manuscript-Notes/`) |
| Terminology (completion vs compliance vs recovery) | Three separately labelled states everywhere (section 1) |
| Diet informs context; clinical assessment dictates exercise rules | Dietary fields are display-only; only `restrictedExercises` / `lowTolerance`, set by a clinician, affect what the app lets the patient do (section 2) |

## 1. Terminology (used in code, UI and docs)

- **Exercise completion**: a prescription is *complete* when the patient has
  finished (`endedEarly == false`) at least `requiredSessions` sessions for it
  (`sessions.prescriptionId == prescription id`). The *program* is complete
  when every active prescription is complete and there is at least one.
- **Compliance**: how well and how regularly the patient exercised: form
  accuracy (`overallCompliance`, counted reps / attempts) and plan adherence
  (sessions per week vs `frequencyPerWeek`). It is never called recovery.
- **Medical recovery / clearance**: only a physician's signed decision
  (`clearances` record). Completion and compliance are inputs the physician
  sees, never the decision.

UI copy rule: the app never says "recovered" or "cleared" unless a
`clearances` record with `decision: cleared` exists.

## 2. Clinical & dietary profile: `patients/{uid}/clinical/profile`

One doc, written only by the dashboard (admin, or the patient's therapist).
The patient app reads it.

| Field | Type | Notes |
| --- | --- | --- |
| `precautions` | string ≤ 1000 | Medical precautions shown to the patient |
| `dietaryNotes` | string ≤ 1000 | Nutritional context, shown as context only |
| `nutritionFlags` | string[] | Codes from the fixed list below; context only |
| `restrictedExercises` | string[] | Exercise type codes the patient must not do (contraindicated) |
| `lowTolerance` | bool | Clinician judged exercise tolerance low |
| `toleranceNote` | string ≤ 500 | Why / what to watch |
| `validatedBy` | string | uid of the clinician who validated it |
| `validatedByName` | string | Their name |
| `validatedAt` | timestamp | Server time of the save |
| `nextReassessmentAt` | timestamp \| null | Planned reassessment date |

`nutritionFlags` codes: `diabetes`, `hypertension`, `low_intake`
(poor appetite / undernourished), `dehydration_risk`, `anemia`,
`weight_management`, `renal_diet`, `food_allergy`.

Effects (and nothing else):
- `restrictedExercises`: the app shows those exercises locked ("Paused by
  your therapist") and won't start them; the dashboard refuses to assign or
  re-activate a prescription for them and marks existing ones.
- `lowTolerance`: the app shows a caution before each session; the dashboard
  shows the tolerance review flag (below).
- `precautions`, `dietaryNotes`, `nutritionFlags`: displayed only. They
  never change a prescription, a target, or the gate.

Tolerance review flag (dashboard, computed, not stored): in the last 14 days,
any session with `painLevel >= 6` or `endedEarly`, for a patient with
`lowTolerance` or any nutrition flag, or `painLevel >= 8` for anyone. Shown
as "Needs clinician review" with the sessions listed. Reassessment = the
clinician edits the profile and/or prescriptions; the app reloads them.

## 3. Completion gate

New optional prescription field `requiredSessions` (int 1–500): finished
sessions needed for that prescription to count as complete. Set on the
dashboard prescription form. A prescription without it can't be complete;
the gate lists it as "no completion target set" (a clinician must set one).

Gate states (same pure logic in PHP and Dart, same test cases):
1. `no_program`: no active prescription.
2. `in_progress`: some active prescription incomplete. Shows each missing
   requirement: exercise name, finished / required, or "no completion target".
3. `ready_for_review`: program complete. "Ready for physician assessment"
   (unless a `cleared` record exists, which the UI shows instead).
4. Clearance state is the latest `clearances` record (section 4), shown next
   to the gate, never derived from it.

Restricted exercises: an active prescription whose type is restricted is a
blocking requirement ("restricted by clinician, adjust the program").

## 4. Physician clearance: `patients/{uid}/clearances/{id}`

Append-only, written only by the dashboard. Latest by `signedAt` wins.

| Field | Type | Notes |
| --- | --- | --- |
| `decision` | `cleared` \| `not_cleared` | `not_cleared` = continue / revise the program |
| `physicianName` | string 1–100 | Assessing physician |
| `physicianLicense` | string 1–40 | PRC license no. |
| `assessedAt` | timestamp | Date of the final assessment |
| `findings` | string 1–2000 | Assessment findings |
| `recommendations` | string ≤ 1000 | |
| `attested` | bool | Always `true`: signer confirmed a physician assessed the patient |
| `programComplete` | bool | Gate result at signing |
| `requirements` | array of maps | Snapshot: `{prescriptionId, exerciseType, finished, required}` |
| `signedBy` / `signedByName` | string | Dashboard account that recorded it |
| `signedAt` | timestamp | Server time |

Dashboard rules (server-side, the service account skips Firestore rules):
- Only admin or the patient's therapist; others get 404.
- `cleared` is refused unless the gate, recomputed at POST time, is
  complete (no form value can bypass it). The form shows the missing list and
  disables the cleared option while incomplete.
- `not_cleared` is allowed any time (reassessment).
- Attestation checkbox required. No auto-clear path exists in code.
- On a `cleared` record the patient gets an in-app notification
  (`type: progress`).

## 5. Firestore rules (app repo)

```
match /clinical/{docId}   { allow read: if isSelf(patientId) || caresFor(patientId); allow write: if false; }
match /clearances/{id}    { allow read: if isSelf(patientId) || caresFor(patientId); allow write: if false; }
```
Prescriptions keep `allow write: if caresFor(patientId)`: no patient write.
Needs a rules deploy (user OK) before the app reads these paths; until then
the app shows "not available yet" instead of failing.

## 6. App (camera/monitoring first, then merged into iphone-testing)

- Models + parsing with `FieldReader` (`lib/models/clinical_profile.dart`,
  `lib/models/clearance_record.dart`), pure gate logic
  (`lib/services/care_gate.dart`) unit-tested against the PHP cases.
- Profile > "Care plan & clearance": one entry opening a page with four
  labelled sections: Exercise completion, Compliance, Medical clearance,
  Clinician precautions (diet shown as "context from your clinician").
- Exercises: restricted ones locked; `lowTolerance` caution before start.
- Read failures (offline / rules not deployed) are logged and shown as
  "unavailable", never as "cleared".

## 7. Build order

1. This doc + handoff item. 2. Rules + emulator tests. 3. Dashboard
(web/messaging). 4. App on camera/monitoring, merge into iphone-testing.
5. Ask to deploy rules. 6. Builds with a version bump (on request).
