<?php

namespace App\Services\Messaging;

use App\Auth\StaffUser;
use App\Services\Firebase\FirestoreClient;
use Illuminate\Support\Facades\Log;

/**
 * Staff actions on existing chat messages: edit, unsend, pin and unpin, plus
 * the lookup behind "Reply" (the quote stored on the new message).
 *
 * Who may do what follows the design's table
 * (docs/superpowers/specs/2026-11-13-chat-actions-design.md):
 *   - edit:   own staff message, within 15 minutes of createdAt (server
 *             time), not unsent, not a session card
 *   - unsend: own staff message, any time
 *   - pin / unpin: any message in the conversation that isn't unsent
 * "Own" means written by this staff member (MessagePresenter::isOwn), so a
 * colleague's message in the same clinic thread is not.
 *
 * The caller must authorize the conversation first (MessagingService::authorize),
 * because the service account bypasses Firestore rules. Each action is ONE
 * atomic commit. None of them bumps an unread counter or sends a push.
 * Writes that depend on what was just read carry an updateTime precondition,
 * so a parallel change (a new message, the patient unsending) makes the
 * commit fail with FirestoreConflict instead of saving stale data.
 */
class ChatActions
{
    /** Thread fields that hold the pin; unpinning deletes all four. */
    public const PIN_FIELDS = ['pinnedMessageId', 'pinnedText', 'pinnedSenderRole', 'pinnedAt'];

    /**
     * Thread field set to the server time by every edit and unsend (both
     * sides), so an open conversation page sees the change even when it was
     * an older message (MessagingService::version()).
     */
    public const ACTION_AT = 'lastActionAt';

    public function __construct(private FirestoreClient $db)
    {
    }

    /**
     * Change the text of the signed-in staff member's own message. Also fixes
     * the thread preview when it is the newest message (lastMessageAt stays).
     */
    public function edit(StaffUser $user, string $patientUid, string $thread, string $messageId, string $text): void
    {
        $text = trim($text);
        if ($text === '' || mb_strlen($text) > MessagingService::MAX_LENGTH) {
            throw ChatActionException::rejected('Message must be 1-'.MessagingService::MAX_LENGTH.' characters.');
        }

        // Step 1: the message, and whether this person may edit it.
        [$message, $messageVersion] = $this->loadMessage($patientUid, $thread, $messageId);
        if (! MessagePresenter::isOwn($message, $user)) {
            throw ChatActionException::forbidden('You can only edit your own messages.');
        }
        if (($message['unsent'] ?? null) === true) {
            throw ChatActionException::rejected('This message was unsent, so it can no longer be edited.');
        }
        if (isset($message['session'])) {
            throw ChatActionException::rejected('A shared session card cannot be edited.');
        }
        if (! MessagePresenter::withinEditWindow($message['createdAt'] ?? null)) {
            throw ChatActionException::rejected('Messages can only be edited within '.MessagePresenter::EDIT_WINDOW_MINUTES.' minutes of sending.');
        }
        if ($text === ($message['text'] ?? null)) {
            return; // nothing changed, so no "Edited" label for it
        }

        // Step 2: the thread, to update its preview if this is the newest message.
        [$summary, $threadVersion, $newest] = $this->threadState($patientUid, $thread, $messageId);

        // Step 3: one commit for the message and the thread: lastActionAt
        // always (so open conversation pages reload, whichever message it
        // was), the preview if newest, the banner text if it is the pin.
        $writes = [$this->db->mergeWrite(
            $this->messagePath($patientUid, $thread, $messageId),
            ['text' => $text],
            serverTimestamps: ['editedAt'],
            ifUpdateTime: $messageVersion,
        )];
        if ($summary !== null) {
            $threadFields = $newest ? ['lastMessage' => $text] : [];
            if (($summary['pinnedMessageId'] ?? null) === $messageId) {
                $threadFields['pinnedText'] = MessagePresenter::snippet($text);
            }
            $writes[] = $this->db->mergeWrite(
                $this->threadPath($patientUid, $thread),
                $threadFields,
                serverTimestamps: [self::ACTION_AT],
                ifUpdateTime: $threadVersion,
            );
        }
        $this->db->commit($writes);

        $this->log('messages.edited', $user, $patientUid, $thread, $messageId);
    }

    /**
     * Unsend the signed-in staff member's own message: its text is emptied and
     * its reply quote / session card removed; the patient sees "Message
     * unsent". Clears the pin if it pointed here and fixes the preview if newest.
     */
    public function unsend(StaffUser $user, string $patientUid, string $thread, string $messageId): void
    {
        // Step 1: the message, and whether this person may unsend it.
        [$message, $messageVersion] = $this->loadMessage($patientUid, $thread, $messageId);
        if (! MessagePresenter::isOwn($message, $user)) {
            throw ChatActionException::forbidden('You can only unsend your own messages.');
        }
        if (($message['unsent'] ?? null) === true) {
            throw ChatActionException::rejected('This message was already unsent.');
        }

        // Step 2: what the thread needs: a new preview, the pin cleared, or neither.
        [$summary, $threadVersion, $newest] = $this->threadState($patientUid, $thread, $messageId);
        $threadFields = $newest ? ['lastMessage' => MessagePresenter::UNSENT_TEXT] : [];
        $threadDeletes = ($summary['pinnedMessageId'] ?? null) === $messageId ? self::PIN_FIELDS : [];

        // Step 3: one commit. replyTo and session are in the mask without a
        // value, which deletes them (the rules for the app require the same).
        $writes = [$this->db->mergeWrite(
            $this->messagePath($patientUid, $thread, $messageId),
            ['text' => '', 'unsent' => true],
            serverTimestamps: ['unsentAt'],
            ifUpdateTime: $messageVersion,
            deletes: ['replyTo', 'session'],
        )];
        if ($summary !== null) {
            $writes[] = $this->db->mergeWrite(
                $this->threadPath($patientUid, $thread),
                $threadFields,
                serverTimestamps: [self::ACTION_AT],
                ifUpdateTime: $threadVersion,
                deletes: $threadDeletes,
            );
        }
        $this->db->commit($writes);

        $this->log('messages.unsent', $user, $patientUid, $thread, $messageId);
    }

    /**
     * Pin a message for both sides (one pin per thread: this replaces any
     * earlier pin). The banner shows a snippet stored on the thread.
     */
    public function pin(StaffUser $user, string $patientUid, string $thread, string $messageId): void
    {
        [$message] = $this->loadMessage($patientUid, $thread, $messageId);
        if (($message['unsent'] ?? null) === true) {
            throw ChatActionException::rejected('An unsent message cannot be pinned.');
        }

        $this->db->commit([$this->db->mergeWrite($this->threadPath($patientUid, $thread), [
            'pinnedMessageId' => $messageId,
            'pinnedText' => MessagePresenter::snippet(is_string($message['text'] ?? null) ? $message['text'] : ''),
            'pinnedSenderRole' => ($message['senderRole'] ?? null) === 'patient' ? 'patient' : 'staff',
        ], serverTimestamps: ['pinnedAt'])]);

        $this->log('messages.pinned', $user, $patientUid, $thread, $messageId);
    }

    /**
     * Remove the thread's pin (whoever set it). The precondition keeps this
     * from removing a pin someone else set a moment ago.
     */
    public function unpin(StaffUser $user, string $patientUid, string $thread): void
    {
        $path = $this->threadPath($patientUid, $thread);
        [$summary, $version] = $this->db->getVersioned($path);

        $pinned = array_intersect(self::PIN_FIELDS, array_keys($summary ?? []));
        if ($pinned === []) {
            return; // nothing pinned: no write, and no empty thread doc created
        }

        $this->db->commit([$this->db->mergeWrite($path, [], ifUpdateTime: $version, deletes: self::PIN_FIELDS)]);

        $this->log('messages.unpinned', $user, $patientUid, $thread, $summary['pinnedMessageId'] ?? null);
    }

    /**
     * The quote stored on a reply: {id, text (snippet), senderRole}. The quoted
     * message must be in the same conversation and not unsent; anything else
     * (another thread's id, a made-up id) is rejected.
     */
    public function replyTarget(string $patientUid, string $thread, string $messageId): array
    {
        try {
            [$message] = $this->loadMessage($patientUid, $thread, $messageId);
        } catch (ChatActionException $e) {
            throw ChatActionException::rejected('The message you replied to is no longer in this conversation.');
        }
        if (($message['unsent'] ?? null) === true) {
            throw ChatActionException::rejected('The message you replied to was unsent.');
        }

        return [
            'id' => $messageId,
            'text' => MessagePresenter::snippet(is_string($message['text'] ?? null) ? $message['text'] : ''),
            'senderRole' => ($message['senderRole'] ?? null) === 'patient' ? 'patient' : 'staff',
        ];
    }

    /**
     * The message document and its updateTime; 404 when the id is malformed
     * or the message isn't in this patient's thread.
     *
     * @return array{0: array, 1: ?string}
     */
    private function loadMessage(string $patientUid, string $thread, string $messageId): array
    {
        if (! FirestoreClient::isValidId($messageId)) {
            throw ChatActionException::notFound();
        }

        [$message, $version] = $this->db->getVersioned($this->messagePath($patientUid, $thread, $messageId));
        if ($message === null) {
            throw ChatActionException::notFound();
        }

        return [$message, $version];
    }

    /**
     * The thread summary (with its updateTime) and whether $messageId is the
     * newest message, read in parallel. Newest = first by sentAt, the order
     * the conversation page and the app show.
     *
     * @return array{0: ?array, 1: ?string, 2: bool}
     */
    private function threadState(string $patientUid, string $thread, string $messageId): array
    {
        $threadPath = $this->threadPath($patientUid, $thread);

        [[$summary, $version], $latest] = $this->db->concurrently([
            fn () => $this->db->getVersioned($threadPath),
            fn () => $this->db->query($threadPath, 'messages', orderBy: ['sentAt', 'DESCENDING'], limit: 1),
        ]);

        return [$summary, $version, ($latest[0]['_id'] ?? null) === $messageId];
    }

    private function threadPath(string $patientUid, string $thread): string
    {
        return "patients/{$patientUid}/threads/{$thread}";
    }

    private function messagePath(string $patientUid, string $thread, string $messageId): string
    {
        return "patients/{$patientUid}/threads/{$thread}/messages/{$messageId}";
    }

    private function log(string $event, StaffUser $user, string $patientUid, string $thread, ?string $messageId): void
    {
        Log::info($event, ['uid' => $user->id, 'patient' => $patientUid, 'thread' => $thread, 'message' => $messageId]);
    }
}
