<?php

namespace App\Services\StaffChat;

use App\Auth\StaffUser;
use App\Services\Firebase\FirestoreClient;
use App\Services\Messaging\MessagingService;
use App\Services\User\StaffDirectory;
use App\Services\User\UserService;
use Carbon\CarbonImmutable;
use Illuminate\Validation\ValidationException;

/**
 * Messages between staff accounts (administrators and physical therapists).
 *
 *   staffChats/{pair}                 conversation summary, one per pair of people
 *   staffChats/{pair}/messages/{id}   messages
 *
 * The pair id is the two uids in sorted order, so both people read the same
 * document. Each side has its own unread counter (unread_{uid}).
 */
class StaffChatService
{
    public const COLLECTION = 'staffChats';

    public function __construct(
        private FirestoreClient $db,
        private UserService $users,
        private StaffDirectory $directory,
    ) {
    }

    /** Active staff accounts this person can message (everyone else on the staff list), with unread counts. */
    public function people(StaffUser $me): array
    {
        $others = array_values(array_filter(
            $this->users->staff(),
            fn (array $u) => $this->canMessage($me, $u),
        ));

        $summaries = $this->db->getMany(array_map(fn (array $u) => $this->path($me->id, $u['uid']), $others));

        return array_map(function (array $u) use ($me, $summaries) {
            $summary = $summaries[$this->path($me->id, $u['uid'])] ?? [];
            $at = $summary['lastMessageAt'] ?? null;

            return [
                'uid' => $u['uid'],
                'name' => $this->directory->name($u['uid'], $u['name']),
                'role' => $u['role'],
                'roleLabel' => StaffUser::ROLE_LABELS[$u['role']] ?? ucfirst($u['role']),
                'photoUrl' => $u['photoUrl'],
                'unread' => max(0, (int) ($summary['unread_'.$me->id] ?? 0)),
                'lastMessage' => is_string($summary['lastMessage'] ?? null) ? $summary['lastMessage'] : null,
                'lastMessageAt' => $at instanceof CarbonImmutable ? $at : null,
                'lastFromMe' => ($summary['lastSenderId'] ?? null) === $me->id,
            ];
        }, $others);
    }

    /** Unread messages from staff conversations, for the Messages tab badge. */
    public function unreadTotal(StaffUser $me): int
    {
        return array_sum(array_column($this->people($me), 'unread'));
    }

    /**
     * The account to chat with if $me may message them, else null (deleted, archived,
     * disabled, a patient account, or themselves).
     *
     * @return array<string, mixed>|null
     */
    public function partner(StaffUser $me, string $uid): ?array
    {
        $user = FirestoreClient::isValidId($uid) ? $this->users->findStaff($uid) : null;

        return $user !== null && $this->canMessage($me, $user) ? $user : null;
    }

    /**
     * Messages between $me and $partner, oldest first (last 200).
     *
     * @return list<array{id: string, text: string, fromMe: bool, senderName: string, sentAt: ?CarbonImmutable}>
     */
    public function messages(StaffUser $me, string $partnerUid): array
    {
        $docs = $this->db->query($this->path($me->id, $partnerUid), 'messages', orderBy: ['sentAt', 'DESCENDING'], limit: 200);

        return array_reverse(array_map(fn (array $m) => [
            'id' => $m['_id'],
            'text' => (string) ($m['text'] ?? ''),
            'fromMe' => ($m['senderId'] ?? null) === $me->id,
            'senderName' => ($m['senderId'] ?? null) === $me->id
                ? $me->name
                : $this->directory->name($m['senderId'] ?? null, (string) ($m['senderName'] ?? '')),
            'sentAt' => $m['sentAt'] ?? $m['createdAt'] ?? null,
        ], $docs));
    }

    /** Clears my unread count for this conversation (writes only when it is set). */
    public function markRead(StaffUser $me, string $partnerUid): void
    {
        $path = $this->path($me->id, $partnerUid);
        $summary = $this->db->get($path);

        if ($summary && ($summary['unread_'.$me->id] ?? 0) > 0) {
            $this->db->commit([$this->db->mergeWrite($path, ['unread_'.$me->id => 0])]);
        }
    }

    /** Saves a message and bumps the other person's unread count, in one commit. */
    public function send(StaffUser $me, string $partnerUid, string $text): void
    {
        $text = trim($text);
        if ($text === '' || mb_strlen($text) > MessagingService::MAX_LENGTH) {
            throw ValidationException::withMessages(['text' => 'Message must be 1-'.MessagingService::MAX_LENGTH.' characters.']);
        }

        $path = $this->path($me->id, $partnerUid);
        $now = CarbonImmutable::now();

        $this->db->commit([
            $this->db->createWrite("{$path}/messages/".FirestoreClient::newId(), [
                'text' => $text,
                'senderId' => $me->id,
                'senderName' => $me->name ?: 'Staff',
                'sentAt' => $now,
            ], serverTimestamps: ['createdAt']),
            $this->db->mergeWrite($path, [
                'participants' => [$me->id, $partnerUid],
                'lastMessage' => $text,
                'lastMessageAt' => $now,
                'lastSenderId' => $me->id,
            ], increments: ['unread_'.$partnerUid => 1]),
        ]);
    }

    /** Both people may message each other: active, not archived, administrator or therapist, not themselves. */
    private function canMessage(StaffUser $me, array $user): bool
    {
        return $user['uid'] !== $me->id
            && in_array($user['role'], StaffUser::ROLES, true)
            && $user['active']
            && ! $user['archived'];
    }

    private function path(string $a, string $b): string
    {
        $pair = [$a, $b];
        sort($pair);

        return self::COLLECTION.'/'.implode('__', $pair);
    }
}
