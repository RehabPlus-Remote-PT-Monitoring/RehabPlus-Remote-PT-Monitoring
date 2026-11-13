# Chat message actions (reply, edit, unsend, pin) — client contract

Date: 2026-11-13

## 1. Intent and why

Add message-management actions to the chat so a patient or staff member can:

- **Reply** to any message (the reply is quoted), from the app (Android + iOS)
  and the dashboard.
- **Edit** their own message. The dashboard enforces a 15-minute window; the
  app has no server, so edit is always available for the author on the app.
- **Unsend** (delete) their own message: the message becomes a
  placeholder ("You deleted a message" for the author, "Message deleted"
  for the other side). Copy / Pin / Edit / Unsend live in a
  three-dots menu. Reply is a dedicated button to its left.
- **Pin / unpin** a message (one pin per thread, visible on both sides).

Both sides share the same Firestore data. The app writes directly to
Firestore (no Cloud Functions); the dashboard writes through a service
account (bypassing rules) and enforces its own permissions. Both read the
same documents, so they must agree on the schema and on what
`edit`/`unsent`/`replyTo`/`pin` mean.

## 2. Goals

- One shared data contract on app and web.
- Reply-with-quote works from both sides.
- Unsend / edit only on the sender's own message (on the app, "own" =
  the patient's own messages; on the dashboard, "own" = staff's own
  messages, per `MessagePresenter::isOwn`).
- Pin is a shared thread state, visible on both sides.
- Old messages (written before this change) still render: unknown optional
  fields are ignored, no crash, no gap in history.

## 3. Non-goals / anti-goals

- No per-message read receipts beyond the existing
  `unreadForStaff` counter (reply/unsend/edit/pin do not touch it).
- No hard delete of messages (unsend = soft delete: `text=''`,
  `unsent=true`).
- No "Forward" button in this pass (a "Forward"-style reply can be added
  later by prefixing "Forwarded: ").
- No in-app translation (no translation dependency added).
- No change to push, Notifications-page entries, or the unread badge.
- Staff can only delete/unsend their **own** messages: the dashboard's
  `ChatActions::unsend` and `edit` enforce this; the app enforces it with
  the `fromPatient` flag.

## 4. Constraints

- `messages/{id}` must never be deleted. Unsend is an update only.
- The dashboard's edit window is 15 minutes
  (`MessagePresenter::EDIT_WINDOW_MINUTES`). The app cannot enforce it
  server-side, so own-message edit is always open on the app.
- The patient app writes via Firebase Auth (rules apply); the dashboard
  uses a service account (rules bypassed).
- The Firestore rules in the app repo currently say messages
  `update, delete: if false`; they must change to allow edit/unsend only
  (no delete).
- `API_CONTRACT.md` currently says "Messages are never edited or deleted";
  it must be updated with the new optional fields and the dashboard-only
  edit window.

## 5. Approaches (picked: 1 — single shared contract)

- **Approach 1 (chosen):** one schema + one contract; the app mirrors the
  dashboard exactly. The dashboard's staged code
  (`MessagePresenter`, `ChatActions`, `MessageController`, Blade partials,
  `chat-actions.js`, tests) is the web side; the app side is built to
  match it.
- Approach 2 (rejected): app-only, web untouched → two different
  "edited/unsent" meanings, staged web routes untestable.
- Approach 3 (rejected): minimal slice, narrow schema → cross-client
  parity gap.

## 6. Data model

### Messages
`patients/{uid}/threads/{threadId}/messages/{id}` — the five core fields
are still the only *required* ones; everything else is optional.

- **Core (unchanged, required):** `text`, `senderId`, `senderRole`,
  `sentAt`, `createdAt`.
- **New optional:** `replyTo` (embedded `{id, text, senderRole}`),
  `editedAt` (server timestamp), `unsent` (bool), `unsentAt` (server
  timestamp).
- **Existing optional:** `session` (shared session card).

### Thread summary
`patients/{uid}/threads/{threadId}` — new optional pin fields:

- `pinnedMessageId` (string), `pinnedText` (string, ≤ 200), `pinnedSenderRole`
  (`'patient'`|`'staff'`), `pinnedAt` (server timestamp).

## 7. Firestore rules (app repo)

(As built; replaces the first draft, which checked the whole document's
keys and would have refused every edit.)

- `allow update` on `messages/{messageId}`: patient or staff of the thread,
  through `validMessageAction`: only the author (`senderId == auth.uid`),
  never on an unsent message, and either an **edit** (changed keys only
  `text` 1–1000 + `editedAt == request.time`) or an **unsend** (`text: ''`,
  `unsent: true`, `unsentAt == request.time`, `replyTo`/`session` removed).
- `allow delete`: stays `if false` — nothing deletes a message, ever.
- `validMessage` (create) accepts one optional field, `replyTo`
  `{id, text ≤ 200, senderRole}`, which must quote a real, not unsent
  message of the same thread by that author (`liveMessageBy`). Without it
  the app could not send a reply.
- Thread doc (`patientThreadFields`): the patient may also set
  `lastActionAt == request.time` and change the pin through
  `validPinChange`: remove all four fields, refresh `pinnedText` alone, or
  set all four at once pointing at a live message by its real author.
  Only pin fields that change are checked.

## 8. Contract (`API_CONTRACT.md`)

- Replace "Messages are never edited or deleted" with: messages are
  **edited** (within a 15-minute window enforced by the dashboard only)
  and **unsent** (soft delete); they are never hard-deleted.
- Document the new optional fields (`replyTo`, `editedAt`, `unsent`,
  `unsentAt`) and the `pin` fields on the thread summary.
- Note the asymmetry: the dashboard enforces a 15-minute edit window;
  the app has no server to enforce it, so the author can always edit
  their own message on the app.

## 9. App (Flutter) changes

### 9.1 `lib/models/chat.dart`

- `ChatMessage.parse` reads the optional fields `replyTo`,
  `editedAt`, `unsent`, `unsentAt` but still requires the five core
  fields. Old documents render unchanged.
- `ChatMessage` gains readable nullable fields: `replyTo`, `editedAt`,
  `unsent`, `session`; a UI-only `editedLabel` (e.g. "Edited").

### 9.2 `lib/services/chat_service.dart` (same "queue, don't await, log"
style as `send`; payloads built in `lib/services/chat_actions.dart`)

- `send(thread, text, replyTo: msg)`: a reply is a normal send plus the
  `replyTo` quote (one code path, so preview and `unreadForStaff++` are
  identical). No push: the patient app sends no pushes at all (PushService
  is receive-only); the dashboard pushes its own staff replies only.
- `editMessage(thread, msg, text, newest:, pinned:)`: one batch, the
  message `{text, editedAt: serverTimestamp}` and the thread
  `{lastActionAt}` + `lastMessage` if newest + `pinnedText` if pinned.
- `unsendMessage(thread, msg, newest:, pinned:)`: one batch, the message
  `{text: '', unsent: true, unsentAt}` with `replyTo`/`session` deleted, and
  the thread `{lastActionAt}` + `lastMessage: "Message deleted"` if newest
  + the pin removed if it pointed here.
- `pin(thread, msg)` / `unpin(thread)`: the four pin fields.
- `lastActionAt` exists so the dashboard's open page reloads when an older
  message changes (its poll fingerprint is the thread doc only).

### 9.3 `lib/screens/messages_screen.dart` (`_ChatDetailScreenState`)

- Per-message action row beside the bubble, shown when the bubble is tapped (or long-pressed) and hidden by tapping it again: the **Reply** button nearest the bubble, then **⋯**. Left of the patient's own (right-hand) bubbles; mirrored, right of the other side's. (The dashboard shows the same two buttons on hover, always on touch screens.)
- The **Reply** button starts a reply composer above the existing message
  box: a "Replying to <sender>" preview (the quoted message, clickable to
  scroll to it) and the reply text field.
- The **⋯** popup menu lists: **Copy**, **Pin**/**Unpin**, **Edit**,
  **Unsend** (last, destructive, red, with a confirm dialog), in this order
  on both the app and the dashboard.
  - Copy copies the text (long-press used to copy directly; it now shows the buttons).
  - Pin/Unpin toggles: the thread's single pin follows the
    `pinnedMessageId`/`pinnedText`/`pinnedSenderRole`/`pinnedAt` fields.
  - Edit = an edit dialog for the author's own message. (Edit sits in
    the ⋯ menu rather than as a separate button, per the screenshot and
    the original request — confirm when you review.)
  - Unsend = confirm, then `unsendMessage`.
- **Unsent placeholder**: your own deleted message → "You deleted a
  message"; the other person's → "Message deleted". Shown as a plain
  placeholder, no bubble, no menu, no ticks.
- **Pinned banner**: top of the conversation shows the pinned message's
  sender and a short text, with an "Unpin" button.
- Render the optional `replyTo`, `editedAt`, `unsent`, `session` fields
  only when present.
- Read receipts (`seenByStaff`) stay unchanged.

### 9.4 `lib/services/chat_pager.dart` and
`lib/widgets/chat_timeline_widgets.dart`

- Unsent placeholders occupy a list slot so the merged list (live +
  older pages) stays aligned with message ids.
- Day separators and the "New messages" divider are unchanged.

## 10. Web dashboard (already staged)

In the `web/messaging` worktree, commit the staged work once the app
contract is settled. The current staged files are:

- `app/Services/Messaging/ChatActionException.php`,
  `ChatActions.php`, `MessagePresenter.php` (with `withActions`,
  `withinEditWindow`, `replyTo`, `unsent`, `pinned`, `session`),
- `app/Http/Controllers/MessageController.php` (routes `reply`,
  `edit`, `unsend`, `pin`, `unpin`),
- `app/Services/Messaging/MessagingService.php` (added `reply`, `markRead`,
  `version`, `withReadReceipts`),
- `app/Services/Firebase/FirestoreClient.php` (`mergeWrite` with
  `ifUpdateTime`, `getVersioned`, `concurrently`),
- Blade partials `_message_menu.blade.php`, `_pinned.blade.php`,
  `_session_card.blade.php`, `resources/js/chat-actions.js`,
  `resources/js/rehabplus-dashboard.js`, and updated
  `resources/views/messages/*`, `routes/web.php`, `tests/*`.

Check: `php artisan test` passes, and the app-side contract above is what
`MessagePresenter` already coerces (so old documents still render).
