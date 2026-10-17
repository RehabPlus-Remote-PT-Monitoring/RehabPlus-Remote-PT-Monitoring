<?php

namespace App\Services\Messaging;

use App\Auth\StaffUser;
use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\FirestoreClient;
use App\Services\Firebase\PatientNotifier;
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
 *   - admin / front-desk staff: every patient's "clinic" thread
 *
 * The service account bypasses Firestore rules, so every method checks
 * access itself.
 */
class MessagingService
{
    public const THREAD_THERAPIST = 'therapist';

    public const THREAD_CLINIC = 'clinic';

    public const MAX_LENGTH = 1000;

    public function __construct(private FirestoreClient $db, private PatientNotifier $notifier)
    {
    }

    /** The thread this user answers, or null if they can't use messaging. */
    public function threadFor(StaffUser $user): ?string
    {
        return match ($user->role) {
            StaffUser::THERAPIST => self::THREAD_THERAPIST,
            StaffUser::ADMIN, StaffUser::STAFF => self::THREAD_CLINIC,
            default => null,
        };
    }

    /**
     * Conversations this user can answer: unread first, then newest.
     * Patients with no messages yet are included so staff can start one.
     *
     * @return array{thread: string, conversations: array<int, array>}
     */
    public function inbox(StaffUser $user): array
    {
        $thread = $this->threadFor($user);

        $patients = $thread === self::THREAD_THERAPIST
            ? $this->db->query('', 'patients', [['therapistId', 'EQUAL', $user->id]])
            : $this->db->query('', 'patients');
        $patients = array_values(array_filter($patients, fn ($p) => ! ($p['archived'] ?? false)));

        $summaries = $this->db->getMany(array_map(
            fn ($p) => "patients/{$p['_id']}/threads/{$thread}",
            $patients,
        ));

        $conversations = array_map(function ($p) use ($thread, $summaries) {
            $s = $summaries["patients/{$p['_id']}/threads/{$thread}"] ?? [];

            return [
                'patientUid' => $p['_id'],
                'patientName' => $p['name'] ?? 'Unnamed patient',
                'condition' => $p['condition'] ?? null,
                'lastMessage' => $s['lastMessage'] ?? null,
                'lastMessageAt' => $s['lastMessageAt'] ?? null,
                'lastSenderRole' => $s['lastSenderRole'] ?? null,
                'unread' => (int) ($s['unreadForStaff'] ?? 0),
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

    /** Messages oldest-first (last 200). Call authorize() first. */
    public function messages(string $patientUid, string $thread): array
    {
        $messages = $this->db->query(
            "patients/{$patientUid}/threads/{$thread}",
            'messages',
            orderBy: ['sentAt', 'DESCENDING'],
            limit: 200,
        );

        return array_reverse(array_map(fn ($m) => [
            'id' => $m['_id'],
            'text' => $m['text'] ?? '',
            'fromPatient' => ($m['senderRole'] ?? null) === 'patient',
            'sentAt' => $m['sentAt'] ?? $m['createdAt'] ?? null,
        ], $messages));
    }

    /** Clear the staff unread badge for this thread (only writes if it's set). */
    public function markRead(string $patientUid, string $thread): void
    {
        $path = "patients/{$patientUid}/threads/{$thread}";
        $summary = $this->db->get($path);

        if ($summary && ($summary['unreadForStaff'] ?? 0) > 0) {
            $this->db->commit([$this->db->mergeWrite($path, ['unreadForStaff' => 0])]);
        }
    }

    /**
     * Send a staff reply: message + thread summary + Notifications-page entry
     * in one atomic commit, then a push to each of the patient's phones.
     * Push failures are logged but don't fail the reply (the message is saved).
     *
     * @return int number of phones the push reached
     */
    public function reply(StaffUser $user, string $patientUid, array $patient, string $thread, string $text): int
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
