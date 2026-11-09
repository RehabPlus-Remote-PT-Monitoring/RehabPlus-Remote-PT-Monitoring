<?php

namespace App\Services\Messaging;

use App\Auth\StaffUser;
use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\FirestoreClient;
use App\Services\Firebase\PatientNotifier;
use App\Services\StaffChat\StaffChatService;
use App\Services\User\StaffDirectory;
use Carbon\CarbonImmutable;
use Illuminate\Support\Str;

/**
 * Staff side of patient messaging. Data lives in Firestore and is shared with
 * the Flutter patient app (API_CONTRACT.md in the app repo):
 *
 *   patients/{uid}/threads/{therapist|clinic}            conversation summary
 *   patients/{uid}/threads/{thread}/messages/{id}        messages
 *   patients/{uid}/notifications/{id}                    app's Notifications page
 *   patients/{uid}/devices/{fcmToken}                    push targets
 *
 * Who answers what:
 *   - therapist: the "therapist" thread of patients whose therapistId is their uid
 *   - administrators: every patient's "clinic" thread
 *
 * The service account bypasses Firestore rules, so every method checks
 * access itself.
 */
class MessagingService
{
    public const THREAD_THERAPIST = 'therapist';

    public const THREAD_CLINIC = 'clinic';

    public const MAX_LENGTH = 1000;

    /**
     * How far ahead of the server a phone's clock may be. Same limit as
     * firestore.rules (sentAt / lastMessageAt <= request.time + 1 hour).
     */
    public const CLOCK_SKEW_MINUTES = 60;

    public function __construct(
        private FirestoreClient $db,
        private PatientNotifier $notifier,
        private StaffDirectory $directory,
        private StaffChatService $staffChats,
    ) {
    }

    /** The thread this user answers, or null if they can't use messaging. */
    public function threadFor(StaffUser $user): ?string
    {
        return match ($user->role) {
            StaffUser::THERAPIST => self::THREAD_THERAPIST,
            StaffUser::ADMIN => self::THREAD_CLINIC,
            default => null,
        };
    }

    /**
     * Conversations this user can answer: unread first, then newest.
     * Patients with no messages yet are included so staff can start one.
     * The main inbox holds active patients; $archived lists the archived ones.
     *
     * @return array{thread: string, conversations: array<int, array>}
     */
    public function inbox(StaffUser $user, bool $archived = false): array
    {
        $thread = $this->threadFor($user);

        $patients = $thread === self::THREAD_THERAPIST
            ? $this->db->query('', 'patients', [['therapistId', 'EQUAL', $user->id]])
            : $this->db->query('', 'patients');
        $patients = array_values(array_filter($patients, fn ($p) => (bool) ($p['archived'] ?? false) === $archived));

        $summaries = $this->db->getMany(array_map(
            fn ($p) => "patients/{$p['_id']}/threads/{$thread}",
            $patients,
        ));

        $now = CarbonImmutable::now();
        $conversations = array_map(function ($p) use ($thread, $summaries, $now) {
            $s = $summaries["patients/{$p['_id']}/threads/{$thread}"] ?? [];
            // The patient's phone sets lastMessageAt (messages can be queued
            // offline). A time in the future is ignored: otherwise a patient
            // could pin their conversation to the top of the inbox for good.
            $at = $s['lastMessageAt'] ?? null;
            $at = $at instanceof CarbonImmutable && $at->lessThanOrEqualTo($now->addMinutes(self::CLOCK_SKEW_MINUTES)) ? $at : null;

            return [
                'patientUid' => $p['_id'],
                'patientName' => $p['name'] ?? 'Unnamed patient',
                'condition' => $p['condition'] ?? null,
                'lastMessage' => is_string($s['lastMessage'] ?? null) ? $s['lastMessage'] : null,
                'lastMessageAt' => $at,
                'lastSenderRole' => $s['lastSenderRole'] ?? null,
                'unread' => max(0, (int) ($s['unreadForStaff'] ?? 0)),
            ];
        }, $patients);

        usort($conversations, fn ($a, $b) => [$b['unread'] > 0, $b['lastMessageAt']?->getTimestamp() ?? 0, $a['patientName']]
            <=> [$a['unread'] > 0, $a['lastMessageAt']?->getTimestamp() ?? 0, $b['patientName']]);

        return ['thread' => $thread, 'conversations' => $conversations];
    }

    /**
     * The patient's profile if $user may read/answer this thread, else null.
     * Therapists only get their own patients; clinic staff only the clinic thread.
     */
    public function authorize(StaffUser $user, string $patientUid, string $thread): ?array
    {
        if ($thread !== $this->threadFor($user) || ! FirestoreClient::isValidId($patientUid)) {
            return null;
        }

        $patient = $this->db->get("patients/{$patientUid}");
        if (! $patient) {
            return null;
        }

        if ($thread === self::THREAD_THERAPIST && ($patient['therapistId'] ?? null) !== $user->id) {
            return null;
        }

        return $patient;
    }

    /**
     * Messages oldest-first (last 200), each with the sender's display name.
     * Call authorize() first and pass the patient profile it returned.
     */
    public function messages(string $patientUid, string $thread, array $patient = []): array
    {
        $messages = $this->db->query(
            "patients/{$patientUid}/threads/{$thread}",
            'messages',
            orderBy: ['sentAt', 'DESCENDING'],
            limit: 200,
        );

        $patientName = ($patient['name'] ?? '') ?: 'Patient';
        // Staff messages sent before senderName was stored fall back to the thread's owner.
        $staffFallback = $thread === self::THREAD_THERAPIST
            ? (($patient['therapistName'] ?? '') ?: 'Therapist')
            : 'RehabPlus Clinic';

        return array_reverse(array_map(function ($m) use ($patientName, $staffFallback) {
            $fromPatient = ($m['senderRole'] ?? null) === 'patient';

            return [
                'id' => $m['_id'],
                'text' => $m['text'] ?? '',
                'fromPatient' => $fromPatient,
                'senderName' => $fromPatient ? $patientName : $this->directory->name($m['senderId'] ?? null, ($m['senderName'] ?? '') ?: $staffFallback),
                'sentAt' => $m['sentAt'] ?? $m['createdAt'] ?? null,
            ];
        }, $messages));
    }

    /** Unread messages across this person's conversations, for the Messages tab. Zero if they can't be read. */
    public function unreadTotal(StaffUser $user): int
    {
        try {
            $patients = array_sum(array_column($this->inbox($user)['conversations'], 'unread'));
        } catch (FirebaseException $e) {
            report($e);
            $patients = 0;
        }

        try {
            $staff = $this->staffChats->unreadTotal($user);
        } catch (FirebaseException $e) {
            report($e);
            $staff = 0;
        }

        return $patients + $staff;
    }

    /**
     * The Messages tab's list: patient conversations and staff conversations
     * together, unread first, then the most recent. Staff chats are only in the
     * inbox, not the archive.
     *
     * Each row: name, tag (who it is), subtitle, lastMessage, lastMessageAt,
     * fromMe (the last message was yours), unread and the page it opens.
     *
     * @return list<array<string, mixed>>
     */
    public function allConversations(StaffUser $user, bool $archived = false): array
    {
        $rows = array_map(fn (array $c) => [
            'name' => $c['patientName'],
            'tag' => 'Patient',
            'tagTone' => 'patient',
            'subtitle' => $c['condition'] ?? '',
            'lastMessage' => $c['lastMessage'],
            'lastMessageAt' => $c['lastMessageAt'],
            'fromMe' => $c['lastSenderRole'] === 'staff',
            'unread' => $c['unread'],
            'url' => route('messages.show', $c['patientUid']),
        ], $this->inbox($user, $archived)['conversations']);

        if (! $archived) {
            $rows = array_merge($rows, array_map(fn (array $p) => [
                'name' => $p['name'],
                'tag' => $p['roleLabel'],
                'tagTone' => $p['role'],
                'subtitle' => '',
                'lastMessage' => $p['lastMessage'],
                'lastMessageAt' => $p['lastMessageAt'],
                'fromMe' => $p['lastFromMe'],
                'unread' => $p['unread'],
                'url' => route('staff-chat.show', $p['uid']),
            ], $this->staffChats->people($user)));
        }

        usort($rows, fn ($a, $b) => [$b['unread'] > 0, $b['lastMessageAt']?->getTimestamp() ?? 0, $a['name']]
            <=> [$a['unread'] > 0, $a['lastMessageAt']?->getTimestamp() ?? 0, $b['name']]);

        return $rows;
    }

    /**
     * Clear the staff unread badge for this thread (only writes if it's set).
     * Returns the thread summary it read, so read receipts can use it.
     */
    public function markRead(string $patientUid, string $thread): ?array
    {
        $path = "patients/{$patientUid}/threads/{$thread}";
        $summary = $this->db->get($path);

        if ($summary && ($summary['unreadForStaff'] ?? 0) > 0) {
            $this->db->commit([$this->db->mergeWrite($path, ['unreadForStaff' => 0])]);
        }

        return $summary;
    }

    /**
     * A short fingerprint of what the conversation page shows, from the thread
     * summary alone: it changes when a message arrives (lastMessageAt) or the
     * patient reads the chat (unreadForPatient). The page polls this cheaply
     * (one document read) and only reloads the messages when it changes.
     * unreadForStaff is left out: opening the page resets it, which would
     * cause one pointless reload.
     */
    public static function version(?array $summary): string
    {
        $at = $summary['lastMessageAt'] ?? null;

        return md5(implode('|', [
            $at instanceof \DateTimeInterface ? $at->format('U.u') : '',
            (int) ($summary['unreadForPatient'] ?? 0),
        ]));
    }

    /** The thread summary document, or null if there is none yet. Call authorize() first. */
    public function summary(string $patientUid, string $thread): ?array
    {
        return $this->db->get("patients/{$patientUid}/threads/{$thread}");
    }

    /**
     * Mark each staff message 'sent' (one tick) or 'seen' (two ticks).
     *
     * There is no per-message read flag: the thread's unreadForPatient counter
     * goes up by one per staff reply and the app resets it to 0 when the
     * patient opens the chat. So the newest unreadForPatient staff messages
     * are unseen and every older one has been seen. Without a summary (it
     * couldn't be read) everything shows as just 'sent'.
     *
     * @param  array  $messages  oldest-first, as returned by messages()
     */
    public static function withReadReceipts(array $messages, ?array $summary): array
    {
        $unseen = $summary === null ? PHP_INT_MAX : max(0, (int) ($summary['unreadForPatient'] ?? 0));

        for ($i = count($messages) - 1; $i >= 0; $i--) {
            if ($messages[$i]['fromPatient']) {
                $messages[$i]['status'] = null;

                continue;
            }
            $messages[$i]['status'] = $unseen > 0 ? 'sent' : 'seen';
            $unseen--;
        }

        return $messages;
    }

    /**
     * Send a staff reply: message + thread summary + Notifications-page entry
     * in one atomic commit, then a push to each of the patient's phones.
     * Push failures are logged but don't fail the reply (the message is saved).
     *
     * @return int|null number of phones the push reached, or null if the
     *                  patient turned message notifications off
     */
    public function reply(StaffUser $user, string $patientUid, array $patient, string $thread, string $text): ?int
    {
        $text = trim($text);
        if ($text === '' || mb_strlen($text) > self::MAX_LENGTH) {
            throw new FirebaseException('Message must be 1-'.self::MAX_LENGTH.' characters.');
        }

        $now = CarbonImmutable::now();
        $threadPath = "patients/{$patientUid}/threads/{$thread}";
        $senderId = $thread === self::THREAD_THERAPIST ? $user->id : 'clinic';
        $title = $thread === self::THREAD_THERAPIST
            ? (($patient['therapistName'] ?? '') ?: ($user->name ?: 'Your therapist'))
            : 'RehabPlus Clinic';
        $preview = Str::limit($text, 117, '...');

        $this->db->commit([
            $this->db->createWrite("{$threadPath}/messages/".FirestoreClient::newId(), [
                'text' => $text,
                'senderId' => $senderId,
                'senderRole' => 'staff',
                // Dashboard-only: who on staff wrote it (the app ignores this field).
                'senderName' => $user->name ?: 'Staff',
                'sentAt' => $now,
            ], serverTimestamps: ['createdAt']),
            $this->db->mergeWrite($threadPath, [
                'lastMessage' => $text,
                'lastMessageAt' => $now,
                'lastSenderRole' => 'staff',
            ], increments: ['unreadForPatient' => 1]),
            $this->notifier->notificationWrite($patientUid, 'message', "Message from {$title}", $preview, ['thread' => $thread]),
        ]);

        return $this->notifier->push($patientUid, $title, $preview, ['type' => 'chat', 'thread' => $thread]);
    }
}
