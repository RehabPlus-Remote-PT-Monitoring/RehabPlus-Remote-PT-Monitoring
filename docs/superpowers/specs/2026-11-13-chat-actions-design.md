# Chat message actions (reply, edit, unsend, pin) — client contract

Date: 2026-11-13

## 1. Intent and why

Add message-management actions to the chat so a patient or staff member can:

- **Reply** to any message (the reply is quoted), from the app (Android + iOS)
  and the dashboard.
- **Edit** their own message. The dashboard enforces a 15-minute window; the
  app has no server, so edit is always available for the author on the app.
- **Unsend** (delete) their own message: the message becomes a
  "Message unsent" placeholder. Copy / Pin / Edit / Unsend live in a
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

- `allow update` on `messages/{messageId}`: when the caller is the patient
  themselves (`isSelf(patientId)`) or staff in this thread
  (`staffForThread(patientId, threadId)`), the *changed* keys must be only
  the content fields (`text`, `replyTo`, `editedAt`, `unsent`, `unsentAt`,
  `session`), and the new document must pass a new `validEditableMessage`
  function:
  - keys only those fields; `text` a string ≤ 1000 (empty allowed for
    unsent), `senderRole` `'patient'`|`'staff'`, `sentAt` timestamp not in
    the future, `createdAt == request.time`;
  - `replyTo` null or an embedded `{id, text, senderRole}` (id ≤ 128
    chars, text ≤ 1000);
  - `editedAt`/`unsentAt` null or timestamp, `unsent` bool.
- `allow delete`: stays `if false` — nothing deletes a message, ever.
- `validMessage` for **create** stays unchanged (it rejects the new
  fields), so a buggy old client can't quietly add fields to a message.

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

### 9.2 `lib/services/chat_service.dart` (new methods, same
"queue, don't await, log" style as `send`)

- `editMessage(thread, messageId, text)`: atomic merge of `{text,
  editedAt: serverTimestamp}`; update the thread `lastMessage` if this is
  the newest message.
- `unsendMessage(thread, messageId)`: atomic merge of
  `{text: '', unsent: true, unsentAt: serverTimestamp}` plus deletes of
  `replyTo` and `session`; update thread `lastMessage` to "Message
  unsent" if newest; clear the pin if the pinned message is this one.
- `replyMessage(thread, text, replyTo)`: atomic batch — new message with
  `replyTo`, then thread `lastMessage`/`lastMessageAt`/`lastSenderRole`
  plus `unreadForStaff++`. No push: the patient app sends no pushes at
  all (PushService is receive-only); the dashboard sends the push for its
  own staff replies only.

### 9.3 `lib/screens/messages_screen.dart` (`_ChatDetailScreenState`)

- Per-message action row (a `Row` of icon buttons) on the **left** of the bubble: the **Reply** button first (nearest the bubble), then the **⋯** button, then nothing else for actions.
- The **Reply** button starts a reply composer above the existing message
  box: a "Replying to <sender>" preview (the quoted message, clickable to
  scroll to it) and the reply text field.
- The **⋯** popup menu lists: **Copy**, **Pin**/**Unpin**, **Edit**,
  **Unsend** (last, destructive, red, with a confirm dialog).
  - Copy = the existing long-press behaviour.
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
