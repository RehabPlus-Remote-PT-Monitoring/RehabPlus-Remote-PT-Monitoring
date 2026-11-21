<?php

namespace App\Services\Notice;

use App\Auth\StaffUser;
use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\FirestoreClient;
use App\Services\User\UserService;
use Carbon\CarbonImmutable;

/**
 * Messages between staff: the clinic tells a physical therapist about their
 * appointments, and therapists ask administrators to change one. Each notice
 * is one document per recipient (staffNotices/{id}), so each person has their
 * own read state. The bell at the top of the page lists the unread ones.
 */
class StaffNoticeService
{
    public const COLLECTION = 'staffNotices';

    public const TYPE_APPOINTMENT = 'appointment';

    public const TYPE_REQUEST = 'request';

    /** How many unread notices the bell lists. */
    public const LIST_LIMIT = 10;

    public function __construct(private FirestoreClient $db, private UserService $users)
    {
    }

    public function send(string $toUid, string $type, string $title, string $body, ?string $appointmentId, string $fromName): void
    {
        $this->db->commit([$this->db->createWrite(self::COLLECTION.'/'.FirestoreClient::newId(), [
            'toId' => $toUid,
            'type' => $type,
            'title' => $title,
            'body' => $body,
            'appointmentId' => $appointmentId,
            'fromName' => $fromName,
            'read' => false,
        ], serverTimestamps: ['createdAt'])]);
    }

    /** One notice to every active administrator. */
    public function sendToAdmins(string $type, string $title, string $body, ?string $appointmentId, string $fromName): void
    {
        foreach ($this->users->staff() as $account) {
            if ($account['role'] === StaffUser::ADMIN && $account['active'] && ! $account['archived']) {
                $this->send($account['uid'], $type, $title, $body, $appointmentId, $fromName);
            }
        }
    }

    /**
     * The unread notices for this person, newest first. Empty if Firestore can't
     * be reached, so the page still loads.
     *
     * @return list<array<string, mixed>>
     */
    public function unreadFor(string $uid, int $limit = self::LIST_LIMIT): array
    {
        try {
            $docs = $this->db->query('', self::COLLECTION, [['toId', 'EQUAL', $uid]]);
        } catch (FirebaseException) {
            return [];
        }

        $notices = array_values(array_filter($docs, fn (array $doc) => ! ($doc['read'] ?? false)));
        usort($notices, fn (array $a, array $b) => $this->time($b) <=> $this->time($a));

        return array_map(fn (array $doc) => [
            'id' => $doc['_id'],
            'type' => (string) ($doc['type'] ?? ''),
            'title' => (string) ($doc['title'] ?? ''),
            'body' => (string) ($doc['body'] ?? ''),
            'appointmentId' => $doc['appointmentId'] ?? null,
            'fromName' => (string) ($doc['fromName'] ?? ''),
            'createdAt' => $doc['createdAt'] ?? null,
        ], array_slice($notices, 0, $limit));
    }

    /** Marks a notice read, but only for the person it was sent to. Returns null if it isn't theirs. */
    public function markRead(string $id, string $uid): ?array
    {
        if (! FirestoreClient::isValidId($id)) {
            return null;
        }

        $doc = $this->db->get(self::COLLECTION.'/'.$id);
        if (! $doc || ($doc['toId'] ?? null) !== $uid) {
            return null;
        }

        $this->db->commit([$this->db->mergeWrite(self::COLLECTION.'/'.$id, ['read' => true])]);

        return $doc;
    }

    private function time(array $doc): int
    {
        $at = $doc['createdAt'] ?? null;

        return $at instanceof \DateTimeInterface ? CarbonImmutable::instance($at)->getTimestamp() : 0;
    }
}
