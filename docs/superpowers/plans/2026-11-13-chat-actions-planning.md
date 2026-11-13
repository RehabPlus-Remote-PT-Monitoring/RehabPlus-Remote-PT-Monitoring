# Chat message actions (reply, edit, unsend, pin) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add message-management actions (reply with quote, edit, unsend, pin/unpin, copy, three-dots menu) to the RehabPlus chat, identical on the patient app (Flutter, Android + iOS) and the staff dashboard (Laravel + Blade).

**Architecture:** Both sides share one Firestore data contract (`replyTo`, `editedAt`, `unsent`, `unsentAt`, thread pin fields). The web side is already staged in the `web/messaging` worktree and is committed as-is. The app side is built to mirror the dashboard's semantics: per-message action row (Reply nearest the bubble, `⋯` next to it opening Copy/Pin/Unsent/Edit), reply composer with a quote, "Edited" label from `editedAt`, "You deleted a message"/"Message deleted" placeholders, and a pinned banner. App pushes are receive-only, so patient replies update the thread but send no push.

**Tech Stack:** Flutter 3.11+ (Dart 3.11), cloud_firestore, Firebase Auth; Laravel 12 + Blade + a little vanilla JS; Firebase project rehabplus-80675 (no Cloud Functions).

**Spec:** `docs/superpowers/specs/2026-11-13-chat-actions-design.md`

## Global Constraints

- Messages are **never hard deleted**: unsend = soft delete (`text=''`, `unsent=true`); nothing may delete a document (`firestore.rules` `allow delete: if false`).
- Dashboard edits enforce a 15-minute window (`MessagePresenter::EDIT_WINDOW_MINUTES`); the app has no server, so the author can always edit their own message on the app (the "Edited" label comes from `editedAt`, not a window).
- The patient app writes via Firebase Auth (rules apply); the dashboard writes via a service account (rules bypassed) and enforces its own permissions.
- The patient app sends no pushes (PushService is receive-only); the dashboard sends pushes for its own staff replies.
- Copy the web dashboard's exact copy where the app mirrors it: "You deleted a message" (your own), "Message deleted" (the recipient's), "Edited", "Pinned", "Unpin".

## Review Focus

1. **Unsent messages in the merged paging list** — the chat pager keeps *all* landed messages, including ones later unsent. The merged list must drop unsent entries so a pager that scrolled back doesn't show a deleted message. Test: `ChatPager` after an unsend keeps only non-unsent messages.
2. **"Edited" is data-driven, not time-gated** — the app cannot enforce the dashboard's 15-minute window, so a patient's own message edited on the app must show "Edited" regardless of how long ago. Test: `ChatMessage.editedLabel` returns non-null whenever `editedAt` is present.
3. **Reply-to an unsent target** — replying to a message that was then deleted gives an error and does not write a reply. Test: `ChatActions::replyTarget` (web) rejects once `unsent`; the app's reply composer disables/errors on an unsent target.
4. **Pinned banner pointing at an unsent message** — the pinned banner disappears when its message is unsent. Test: `MessagePresenter::pinned` returns null when the pinned doc is unsent.
5. **Old messages render unchanged** — documents written before this change (no `replyTo`/`editedAt`/`unsent`) must render identically; no crash, no gap in history. Test: parse+render an age-old-style fixture with only the five core fields.

---

## Task 1: Web dashboard — commit staged chat-actions code + tests

**Files:**
- Commit in the `web/messaging` worktree (branch `web/messaging`): `app/Services/Messaging/ChatActionException.php`, `ChatActions.php`, `MessagePresenter.php`, `app/Http/Controllers/MessageController.php`, `MessagingService.php`, `app/Services/Firebase/FirestoreClient.php`, Blade partials `_message_menu.blade.php`, `_pinned.blade.php`, `_session_card.blade.php`, `resources/js/chat-actions.js`, `resources/js/rehabplus-dashboard.js`, `resources/views/messages/*`, `routes/web.php`, `tests/Feature/ChatActionsTest.php`, `tests/js/chat-actions.test.js`.

**Interfaces:**
- Produces committed, green code: `php artisan test` passes.

**Steps:**
- [ ] 1. `cd /home/izaac/Documents/RehabPlus-web-messaging/laravel-app && git add <the staged files> && git commit -m "feat: add chat message actions (reply, edit, unsend, pin)"`
- [ ] 2. `cd /home/izaac/Documents/RehabPlus-web-messaging/laravel-app && php artisan test` — resolve any failures before declaring green.

---

## Task 2: Web — align copy to "deleted"; contract update

**Files:**
- Modify: `app/Services/Messaging/MessagePresenter.php` (constants `UNSENT_TEXT` / `UNSENT_TEXT_MINE`), `resources/views/messages/_list.blade.php` + `show.blade.php` (unsent placeholders), `docs/superpowers/specs/2026-11-13-chat-actions-design.md` (already updated).
- Modify (app repo): `API_CONTRACT.md` (replace "never edited or deleted" with soft-unsend + edit + dashboard-only 15-min window).

**Interfaces:**
- Produce committed, green: `php artisan test` passes; the web copy reads "You deleted a message"/"Message deleted".

**Steps:**
- [ ] 1. In `MessagePresenter.php` set `UNSENT_TEXT = 'Message deleted'` and `UNSENT_TEXT_MINE = 'You deleted a message'` (and add `const DELETE_WORD = 'deleted'` so both are updated in one place).
- [ ] 2. In `_list.blade.php`, the unsent placeholder uses `MessagePresenter::UNSENT_TEXT`/`UNSENT_TEXT_MINE` (verify it renders the new strings).
- [ ] 3. `cd /home/izaac/Documents/RehabPlus-web-messaging/laravel-app && php artisan test`.

---

## Task 3: App — models: optional message fields + unsent parse fix

**Files:**
- Create: `test/chat_actions_model_test.dart`
- Modify: `lib/models/chat.dart` (`ChatMessage`, `ChatMessage.parse`, add readable fields + `editedLabel`).

**Interfaces:**
- Produces: `ChatMessage` with nullable `replyTo` (map `{id, text, senderRole}`), `editedAt` (DateTime?), `unsent` (bool), `unsentAt` (DateTime?), `session` (map); `parse` reads them and *allows empty `text` when `unsent==true`*; a UI-only `editedLabel` ("Edited" whenever `editedAt` is present).
- Consumed by Task 4 and Task 6.

**Steps:**
- [ ] 1. Add nullable fields to `ChatMessage` and wire them in the constructor.
- [ ] 2. In `_fromReader`, read `replyTo` via `r.map('replyTo')`, `editedAt` via `r.dateTime('editedAt')`, `unsent` via `r.boolean('unsent', fallback: false)`, `unsentAt` via `r.dateTime('unsentAt')`. After clipping, if `!r.data['unsent']` is true, allow `text` to be empty (the current `requireString` throws on `text=''`).
- [ ] 3. Add a UI-only `editedLabel` getter = `editedAt != null ? 'Edited' : null`.
- [ ] 4. `test/chat_actions_model_test.dart`: fixtures with the five core fields only (no crash, fields null), with `unsent`/`editedAt`/`replyTo`, and an unsent message with `text=''` (must be parsed, not dropped).

---

## Task 4: App — chat actions service (atomic writes)

**Files:**
- Create: `test/chat_service_actions_test.dart`
- Modify: `lib/services/chat_service.dart` (add `editMessage`, `unsendMessage`, `replyMessage`).

**Interfaces:**
- Produces: three new methods, each mirroring `send()`'s "queue with `batch()`, logged, not awaited" style:
  - `Future<void> editMessage(String thread, String messageId, String text)` — atomic update of `{text, editedAt: serverTimestamp}`; thread `lastMessage` updates if this is the newest message.
  - `Future<void> unsendMessage(String thread, String messageId)` — atomic update of `{text: '', unsent: true, unsentAt: serverTimestamp}` with `replyTo` and `session` deleted; thread `lastMessage` → "Message deleted" if newest; clear the pin if the pinned message is this one.
  - `Future<void> replyMessage(String thread, String text, Map<String, dynamic>? replyTo)` — atomic batch: new message (with `replyTo`), thread `lastMessage`/`lastMessageAt`/`lastSenderRole` + `unreadForStaff++`. No push.
- Consumed by Task 6 (the UI calls these).

**Steps:**
- [ ] 1. Reuse the existing `_messageRef(thread, messageId)` and `batch()` + `logUnawaitedWrite` helpers.
- [ ] 2. `unsendMessage`: `batch.update(messageRef, {'text': '', 'unsent': true, 'unsentAt': FieldValue.serverTimestamp(), 'replyTo': FieldValue.delete(), 'session': FieldValue.delete()})`; recompute the thread preview/pin like `send()` does.
- [ ] 3. `replyMessage`: `batch.set(newMessageRef, {...}, SetOptions(merge: true))` with `replyTo`, then `batch.update(threadRef, ...)` with `unreadForStaff: FieldValue.increment(1)`, then commit.
- [ ] 4. Write tests (in-memory Firestore via `cloud_firestore`'s `TestFirestore` or a fake) asserting each commit is one atomic batch and contains the right fields.

---

## Task 5: App — firestore rules + API_CONTRACT.md

**Files:**
- Modify: `firestore.rules` (`messages/{messageId}` allow update; delete stays `if false`; add `validEditableMessage`).
- Modify (app repo): `API_CONTRACT.md`.

**Interfaces:**
- Produces: rules that allow a patient or staff member to update a message's content fields only, and forbid all deletes; the contract documents soft-unsend + edit (15-min window is dashboard-only).

**Steps:**
- [ ] 1. In `firestore.rules`, replace `allow update, delete: if false;` with `allow update: if (isSelf(patientId) || staffForThread(patientId, threadId)) && validEditableMessage(request.resource.data);` and keep `allow delete: if false;`.
- [ ] 2. Add the helper `validEditableMessage(d)`:
  - keys only `['text','replyTo','editedAt','unsent','unsentAt','session']`;
  - `text` string ≤ 1000 (empty allowed for unsent), `senderRole` in `['patient','staff']`, `sentAt` timestamp not in future, `createdAt == request.time`;
  - `replyTo` null or an embedded `{id, text, senderRole}` (id ≤ 128 chars, text ≤ 1000);
  - `editedAt`/`unsentAt` null or timestamp, `unsent` bool.
- [ ] 3. Update `API_CONTRACT.md` messages section (soft-unsend + edit; optional fields; dashboard-only window).
- [ ] 4. Verify with the rules emulator (the `tool/rules-test` harness) for: patient edit, patient unsend, staff edit, staff unsend, and no delete path.

---

## Task 6: App — message action UI (list, composer, quote, placeholder, banner)

**Files:**
- Modify: `lib/screens/messages_screen.dart` (`_ChatDetailScreenState`, `_Bubble`).
- Modify: `lib/widgets/chat_timeline_widgets.dart` (unused items stay, fill-style unchanged).
- New: `lib/widgets/` as needed (message bubble wrapper, reply-composer-head, pinned banner).

**Interfaces:**
- Produces a per-message action row on the left of each bubble: **Reply** first (nearest bubble), then **⋯**. The Reply button opens a reply composer above the existing message box with a "Replying to <sender>" quote line (clickable to scroll to the quoted message) + the reply text field. The `⋯` menu lists **Copy**, **Pin/Unpin**, **Edit**, **Unsend** (destructive, with a confirm). Unsent placeholders show "You deleted a message" (your own) / "Message deleted" (the other's). The pinned banner shows the pinned message's sender + short text with an "Unpin" button. "Edited" label appears on the sender's own message when `editedAt` is present. Read receipts (`seenByStaff`) and day separators are unchanged.

**Steps:**
- [ ] 1. Refactor the existing `_Bubble` into a widget that draws the bubble + tick; wrap the per-message row with an action row.
- [ ] 2. Add the Reply/⋯ action row: `Reply` button for every non-archived thread; `⋯` menu with `Copy`, `Pin`/`Unpin`, `Edit`, `Unsend` (destructive confirm).
- [ ] 3. Reply composer: a "Replying to <sender>" preview (the quoted message, click-to-scroll) + text field, shown only when a reply is in progress; sending sets `replyTo` and can call `replyMessage()`.
- [ ] 4. Unsent placeholder (own → "You deleted a message", other → "Message deleted"), no bubble/menu/ticks.
- [ ] 5. "Edited" label from `msg.editedLabel`.
- [ ] 6. Widget tests: pump the list with a patient + a staff message, assert the action row, the reply composer, the placeholder, the "Edited" label, and the pinned banner.
- [ ] 7. Pager merge drops unsent messages so an older page cannot resurrect a deleted one (Review Focus item 1): a focused test keeps only messages whose `unsent` is false in the merged list before it reaches the screen.

---

## Task 7: App — ⋯ menu popups (Copy/Pin/Unsent/Edit + confirm)

**Files:**
- Create: popup/confirm widgets in `lib/widgets/` (e.g. `chat_action_menu.dart` holding the `⋯` overlay and the `Edit` dialog; a native-style confirmation for Unsend).
- Modify: `lib/screens/messages_screen.dart` (wiring).

**Interfaces:**
- Produces: a `⋯` button per message whose menu offers Copy/Pin/Unsent/Edit, and an edit dialog for the author's own message. The Unsend form asks "Delete this message? The author will see 'You deleted a message'". Copy short-cuts the clipboard. Pin/Unpin toggle the thread's single pin without leaving the menu.
- Consumed by: the user.

**Steps:**
- [ ] 1. Build the `⋯` button and overlay menu (positioned via a `RelativeRect`/`PopupMenuButton` style).
- [ ] 2. Add the edit dialog (text field, Save/Cancel) for the author's own message.
- [ ] 3. Give Unsend a confirm dialog ("Delete this message? …"), then call `unsendMessage`.
- [ ] 4. Widget tests: open the menu on a patient bubble, assert Copy/Pin/Unsent/Edit items; assert Unsend asks for confirmation and only reports "You deleted a message" after confirm.

---

## Task 8: App — pins (thread summary + banner)

**Files:**
- Modify: `lib/models/chat.dart` (`ChatThreadSummary` gains `pinnedMessageId`, `pinnedText`, `pinnedSenderRole`, `pinnedAt`) and `lib/services/chat_service.dart` (thread-pin reads).
- Create: `lib/widgets/pinned_banner.dart` (banner with an "Unpin" button).
- Modify: `lib/screens/messages_screen.dart` (render the banner above the message list).

**Interfaces:**
- Produces: the thread summary carries the pin fields; a banner at the top of the conversation lists the pinned message's snippet and its sender, with an "Unpin" button. When the pinned message is deleted it is not shown.
- Consumed by: Task 6's list builder.

**Steps:**
- [ ] 1. Extend `ChatThreadSummary` with the four pin fields (nullable) and `fromMap`/`toMap` as needed.
- [ ] 2. `ChatService` reads the pin fields when loading the summary.
- [ ] 3. Build `PinnedBanner` + wire it into `_buildMessageList` above the message list.
- [ ] 5. Widget test: a pinned banner appears with the pinned message's snippet and sender; after the pinned message is unsent, the banner is gone.

---

## Task 9: App — full verification + commit

**Files:** repository root (Flutter app).

**Interfaces:**
- Produces: `flutter analyze` clean; full suite green plus new tests; commits on `camera/monitoring` (then merged to `iphone-testing` per the standing workflow).

**Steps:**
- [ ] 1. `flutter analyze` — no issues.
- [ ] 2. `flutter test` — full suite + all new tests green (including the `chat_actions_model_test`, `chat_service_actions_test`, `messages_screen_actions_test`, and any emulator rule cases).
- [ ] 3. Re-run the tablet/messaging widget tests to confirm nothing regressed.
- [ ] 4. Commit per the repo's commit policy (see `handoff.md`), then `git fetch` + `git log origin/camera/monitoring..HEAD` before pushing.
