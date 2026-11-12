# Chat actions: reply, edit, copy, pin, unsend, shared-session card

Status: approved by the user on 2026-11-13 ("keep the compact card, and then
continue with all of the changes left"). No reactions. Photos are a later,
separate round (needs Firebase Storage on the Blaze plan, or ~150 KB
compressed images inside the message doc).

## Intent
Chat should behave like a normal messaging app on all three clients: the
Laravel dashboard (staff), the Android app (camera/monitoring) and the iPhone
app (iphone-testing). Long-press (app) / hover "⋮" (web) on a bubble opens:
Reply, Edit, Copy, Pin/Unpin, Unsend. "Share a session" (iPhone-only today)
comes to Android, and a shared session shows as a compact card everywhere.

## Who can do what
| Action | Own messages | Other side's messages |
| --- | --- | --- |
| Reply | yes | yes |
| Copy | yes (not unsent) | yes (not unsent) |
| Pin / Unpin | yes | yes |
| Edit | yes, within 15 minutes of sending, not unsent, not a session card | no |
| Unsend | yes, any time | no |

- "Own" for staff = `senderRole == 'staff'` AND `senderId ==` the signed-in
  staff member's Firebase uid. Another staff member's message is NOT own.
- One pin per thread, shared: both sides see the same pinned banner and
  either side can unpin or replace it. Unsending the pinned message clears
  the pin.
- Edit and unsend never bump unread counters and never send a push.

## Data contract (Firestore)
### `patients/{uid}/threads/{threadId}/messages/{id}`, new optional fields
| Field | Type | Notes |
| --- | --- | --- |
| `replyTo` | map | Set on create only. `{ id: string <=128, text: string <=200 (snippet of the quoted message), senderRole: 'patient'|'staff' }` |
| `session` | map | Patient messages only, set on create. Compact card data: `{ exerciseName: string 1..100, startTime: timestamp, completedReps: int 0..1000, targetReps: int 0..1000, endedEarly: bool, accuracy?: int 0..100, painLevel?: int 0..10, painNote?: string <=300, sessionId?: string <=128 }`. `text` still holds the plain-text summary (sessionShareText) so old app builds and any client that doesn't know the card show today's text bubble. |
| `editedAt` | timestamp | Server time of the last edit. Shown as "Edited". |
| `unsent` | bool | `true` once unsent. `text` is then `''`; `replyTo`/`session` are removed. Clients show an italic "Message unsent" placeholder (sender sees "You unsent a message"). |
| `unsentAt` | timestamp | Server time of the unsend. |

Old messages lack all of these; every reader must treat them as optional
(FieldReader on the app, coercion in the dashboard presenter).

### `patients/{uid}/threads/{threadId}`, new optional fields
| Field | Type | Notes |
| --- | --- | --- |
| `pinnedMessageId` | string <=128 or absent | Absent/deleted = nothing pinned |
| `pinnedText` | string <=200 | Snippet shown in the banner |
| `pinnedSenderRole` | `patient`/`staff` | |
| `pinnedAt` | timestamp | |

Unpin = delete the four fields (FieldValue.delete / updateMask without
values).

### Last-message preview
When the edited/unsent message is the newest in the thread, also update
`lastMessage` (new text, or "Message unsent"). Don't change `lastMessageAt`.

## Firestore rules (app repo `firestore.rules`, deploy needs the user's OK)
- Message create (`validMessage`): allow the optional `replyTo` and (for
  role patient) `session` keys with the type/size checks above. Still no
  `editedAt`/`unsent` on create.
- Message update, patient only, own message (`resource.data.senderId ==
  request.auth.uid`, `senderRole == 'patient'`, `isPatient(patientId)`),
  not already unsent, exactly one of:
  - edit: affectedKeys hasOnly `['text','editedAt']`, text string 1..1000,
    `editedAt == request.time`, `request.time < resource.data.createdAt +
    duration.value(15, 'm')`, no `session` on the doc.
  - unsend: affectedKeys hasOnly `['text','unsent','unsentAt','replyTo','session']`,
    `text == ''`, `unsent == true`, `unsentAt == request.time`, and
    `replyTo`/`session` absent in the result.
- Message delete stays `false`. Staff never write through rules (the
  dashboard uses the service account), so no staff update rule.
- Thread update by patient (`patientThreadFields`): also allow
  `pinnedMessageId`, `pinnedText`, `pinnedSenderRole`, `pinnedAt` (set with
  types/sizes, `pinnedAt == request.time`, or all removed).
- Tests in `tool/rules-test/rules.test.mjs` for every allowed and denied case
  (other patient's message, staff message, after 15 min, double unsend,
  extra keys, oversized replyTo/session, session on staff role, pin fields).

## Dashboard (laravel-app, branch web/messaging)
- Hover/focus "⋮" on each bubble → menu. Copy uses the Clipboard API (no
  server call). Reply sets a quoted preview above the composer (with ×) and
  the next send includes `replyTo`.
- Edit: inline editor or small dialog; POST route; server checks own
  message + 15-min window + not unsent + not a session card; writes `text`,
  `editedAt` (server timestamp transform) and the preview if newest.
- Unsend: "Do you want to proceed?" confirm (existing data-confirm pattern),
  server checks own message; writes `text: ''`, `unsent: true`, `unsentAt`,
  deletes `replyTo`/`session` (updateMask), clears the pin if it pointed at
  it, fixes the preview if newest.
- Pin/Unpin: POST routes, thread-scoped, any message (not unsent). Pinned
  banner at the top of the conversation; click scrolls to the message when
  it's on the page.
- Render: reply quote inside the bubble, "Edited" next to the time, unsent
  placeholder, compact session card (teal title bar: exercise + "Shared
  session · <date>", three boxes reps / accuracy / pain, pain note quote;
  boxes for missing accuracy/pain are omitted). Light and dark themes.
- All routes use the existing role/ownership scoping (therapist thread vs
  clinic thread, 404 for other users' records) and validate ids with
  `isValidId`. Feature tests with the FakeFirebase support class assert exact
  write payloads.
- Staff do not share sessions (only patients do); staff only see the card.

## App (Flutter) — Android first on camera/monitoring, then merge into iphone-testing
- Model: `ChatMessage` gains `replyTo` (id/text/fromPatient), `session`
  (card data), `editedAt`, `unsent`; `ChatThreadSummary` gains the pin. Parse
  with FieldReader; bad optional fields are dropped and logged, never kill
  the list.
- Service: `sendMessage(..., replyTo:, session:)`, `editMessage`,
  `unsendMessage`, `pin`/`unpin`, each logged with DiagnosticLogger, errors
  surfaced as a snackbar (errors only, no success snackbars).
- UI: long-press bubble → bottom sheet with the allowed actions (same table);
  Copy → Clipboard + small "Copied" toast is acceptable (invisible result).
  Reply bar above the composer; quoted block inside bubbles; "Edited" label;
  unsent placeholder; pinned banner under the chat header (tap = scroll to
  it if loaded, × = unpin).
- Share a session on Android: port `lib/services/chat_session_share.dart`
  and `lib/widgets/chat_session_share_sheet.dart` from iphone-testing
  (identical files merge cleanly), add the button to the composer for the
  therapist thread, and send `session` + the plain text.
- Session card widget used on both platforms.
- iPhone: the older-messages pager (lib/services/chat_pager.dart) reads old
  pages once; edits/unsends to messages outside the live window show after
  reopening the chat. Note this; don't redesign the pager.

## Out of scope
Reactions, forwarding, translation, photos, staff-to-staff messages,
per-person "seen".
