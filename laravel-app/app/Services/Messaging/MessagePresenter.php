<?php

namespace App\Services\Messaging;

use App\Auth\StaffUser;
use App\Services\Firebase\FirestoreClient;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * Turns raw message and thread documents into what the conversation page
 * shows: reply quotes, "Edited", unsent placeholders, the shared-session card,
 * the pinned banner and which actions each bubble's menu offers.
 *
 * Every field read here can be written by the patient app, and the newer ones
 * (replyTo, session, editedAt, unsent, pin) are optional and missing on old
 * documents. So each one is type- and size-checked: a bad shape is dropped
 * (and logged) instead of reaching Blade, where an array in {{ }} is a 500.
 * Contract: docs/superpowers/specs/2026-11-13-chat-actions-design.md.
 */
class MessagePresenter
{
    /** Staff may edit their own message for this long after it was saved (server time). */
    public const EDIT_WINDOW_MINUTES = 15;

    /** Longest reply quote / pinned snippet stored in Firestore. */
    public const SNIPPET_LENGTH = 200;

    /** Thread preview and bubble text for an unsent message. */
    public const UNSENT_TEXT = 'Message unsent';

    public const UNSENT_TEXT_MINE = 'You unsent a message';

    /**
     * The staff sender of the clinic thread is always "clinic" (the app shows
     * the clinic, not a person), so which staff member wrote a clinic message
     * is kept in this dashboard-only field. The app ignores it.
     */
    public const STAFF_UID_FIELD = 'senderStaffUid';

    /**
     * The shape the page needs for one message document.
     *
     * @param  array  $doc  raw message document (with _id)
     * @param  string  $senderName  display name already worked out by the caller
     */
    public static function present(array $doc, string $senderName): array
    {
        $fromPatient = ($doc['senderRole'] ?? null) === 'patient';
        $unsent = ($doc['unsent'] ?? null) === true;
        $where = $doc['_path'] ?? $doc['_id'];

        return [
            'id' => $doc['_id'],
            'text' => $unsent ? '' : self::string($doc['text'] ?? null),
            'fromPatient' => $fromPatient,
            'senderRole' => $fromPatient ? 'patient' : 'staff',
            'senderName' => $senderName,
            'staffUid' => $fromPatient ? null : self::ownerUid($doc),
            'sentAt' => self::time($doc['sentAt'] ?? null) ?? self::time($doc['createdAt'] ?? null),
            'createdAt' => self::time($doc['createdAt'] ?? null),
            'unsent' => $unsent,
            // An unsent message shows only the placeholder, whatever is left in it.
            'editedAt' => $unsent ? null : self::time($doc['editedAt'] ?? null),
            'replyTo' => $unsent ? null : self::replyTo($doc['replyTo'] ?? null, $where),
            // Only patients share sessions; a session map on a staff message is ignored.
            'session' => $unsent || ! $fromPatient ? null : self::session($doc['session'] ?? null, $where),
        ];
    }

    /**
     * Uid of the staff member who wrote a staff message, or null if unknown
     * (patient message, or a clinic message sent before senderStaffUid existed).
     */
    public static function ownerUid(array $doc): ?string
    {
        if (($doc['senderRole'] ?? null) !== 'staff') {
            return null;
        }

        $staffUid = $doc[self::STAFF_UID_FIELD] ?? null;
        if (is_string($staffUid) && $staffUid !== '') {
            return $staffUid;
        }

        $senderId = $doc['senderId'] ?? null;

        return is_string($senderId) && $senderId !== '' && $senderId !== 'clinic' ? $senderId : null;
    }

    /** Whether $user wrote this raw message document (another staff member's message is not theirs). */
    public static function isOwn(array $doc, StaffUser $user): bool
    {
        return self::ownerUid($doc) === $user->id;
    }

    /** Whether the 15-minute edit window (from the server's createdAt) is still open. */
    public static function withinEditWindow(mixed $createdAt, ?CarbonImmutable $now = null): bool
    {
        $createdAt = self::time($createdAt);

        return $createdAt !== null
            && ($now ?? CarbonImmutable::now())->lessThan($createdAt->addMinutes(self::EDIT_WINDOW_MINUTES));
    }

    /** First SNIPPET_LENGTH characters of a message, for reply quotes and the pinned banner. */
    public static function snippet(string $text): string
    {
        return Str::limit(trim($text), self::SNIPPET_LENGTH - 3, '...');
    }

    /**
     * Add each bubble's menu: which actions it offers, its reply-quote sender
     * label and the time Edit stops being offered. Follows the design's table:
     *   reply/copy/pin: any message that isn't unsent (reply only when the
     *   patient can be messaged); edit: own staff message, within 15 minutes,
     *   not a session card; unsend: own staff message.
     *
     * @param  array  $messages  oldest-first, from MessagingService::messages()
     */
    public static function withActions(array $messages, StaffUser $user, bool $canReply, ?string $pinnedId, ?CarbonImmutable $now = null): array
    {
        $now ??= CarbonImmutable::now();
        $names = array_column($messages, 'senderName', 'id');

        return array_map(function (array $m) use ($user, $canReply, $pinnedId, $now, $names) {
            $mine = ! $m['fromPatient'] && $m['staffUid'] === $user->id;
            $editable = $mine && ! $m['unsent'] && $m['session'] === null
                && self::withinEditWindow($m['createdAt'], $now);

            $actions = [];
            if (! $m['unsent']) {
                if ($canReply) {
                    $actions[] = 'reply';
                }
                if ($editable) {
                    $actions[] = 'edit';
                }
                $actions[] = 'copy';
                $actions[] = $m['id'] === $pinnedId ? 'unpin' : 'pin';
            }
            if ($mine && ! $m['unsent']) {
                $actions[] = 'unsend';
            }

            // The quoted message's sender, by name when it is on the page.
            if ($m['replyTo'] !== null) {
                $m['replyTo']['senderName'] = $names[$m['replyTo']['id']]
                    ?? ($m['replyTo']['senderRole'] === 'patient' ? 'Patient' : 'Staff');
            }

            return $m + [
                'mine' => $mine,
                'actions' => $actions,
                'editUntil' => $editable ? $m['createdAt']->addMinutes(self::EDIT_WINDOW_MINUTES) : null,
            ];
        }, $messages);
    }

    /**
     * The pinned banner from the thread summary, or null when nothing (valid)
     * is pinned, or the pinned message on the page has been unsent.
     *
     * @return array{id: string, text: string, senderRole: string, senderName: ?string, onPage: bool}|null
     */
    public static function pinned(?array $summary, array $messages): ?array
    {
        $id = $summary['pinnedMessageId'] ?? null;
        if (! is_string($id) || ! FirestoreClient::isValidId($id)) {
            if ($id !== null) {
                self::dropped($summary['_path'] ?? 'thread', 'pinnedMessageId');
            }

            return null;
        }

        $onPage = collect($messages)->firstWhere('id', $id);
        if ($onPage && $onPage['unsent']) {
            return null;
        }

        $role = ($summary['pinnedSenderRole'] ?? null) === 'patient' ? 'patient' : 'staff';

        return [
            'id' => $id,
            // Prefer the message itself: it shows edits made after it was pinned.
            'text' => Str::limit($onPage ? $onPage['text'] : self::string($summary['pinnedText'] ?? null), self::SNIPPET_LENGTH, '...'),
            'senderRole' => $role,
            'senderName' => $onPage['senderName'] ?? null,
            'onPage' => $onPage !== null,
        ];
    }

    /**
     * A reply quote: {id, text, senderRole}, or null when missing or malformed.
     */
    public static function replyTo(mixed $value, string $where = 'message'): ?array
    {
        if ($value === null) {
            return null;
        }

        $id = is_array($value) ? ($value['id'] ?? null) : null;
        $text = is_array($value) ? ($value['text'] ?? null) : null;
        $role = is_array($value) ? ($value['senderRole'] ?? null) : null;

        if (! is_string($id) || ! FirestoreClient::isValidId($id) || ! is_string($text) || ! in_array($role, ['patient', 'staff'], true)) {
            self::dropped($where, 'replyTo');

            return null;
        }

        return ['id' => $id, 'text' => Str::limit($text, self::SNIPPET_LENGTH, '...'), 'senderRole' => $role];
    }

    /**
     * The compact session card, or null when there is none or it's unusable.
     * A card needs an exercise name; every other value is optional and is
     * left out (null) when it's missing, the wrong type or out of range.
     */
    public static function session(mixed $value, string $where = 'message'): ?array
    {
        if ($value === null) {
            return null;
        }

        $name = is_array($value) ? trim(self::string($value['exerciseName'] ?? null)) : '';
        if ($name === '') {
            self::dropped($where, 'session');

            return null;
        }

        $accuracy = self::intBetween($value['accuracy'] ?? null, 0, 100);
        $note = trim(self::string($value['painNote'] ?? null));

        return [
            'exerciseName' => Str::limit($name, 100, '...'),
            'startTime' => self::time($value['startTime'] ?? null),
            'completedReps' => self::intBetween($value['completedReps'] ?? null, 0, 1000),
            'targetReps' => self::intBetween($value['targetReps'] ?? null, 0, 1000),
            'accuracy' => $accuracy,
            'accuracyTone' => match (true) {
                $accuracy === null => null,
                $accuracy >= 80 => 'good',
                $accuracy >= 50 => 'fair',
                default => 'poor',
            },
            'painLevel' => self::intBetween($value['painLevel'] ?? null, 0, 10),
            'painNote' => $note === '' ? null : Str::limit($note, 300, '...'),
        ];
    }

    private static function string(mixed $value): string
    {
        return is_string($value) ? $value : '';
    }

    private static function time(mixed $value): ?CarbonImmutable
    {
        return $value instanceof CarbonImmutable ? $value : null;
    }

    /** Whole numbers only (Firestore integers); doubles from a sloppy client are rounded. */
    private static function intBetween(mixed $value, int $min, int $max): ?int
    {
        if (is_float($value) && is_finite($value)) {
            $value = (int) round($value);
        }

        return is_int($value) && $value >= $min && $value <= $max ? $value : null;
    }

    /** A malformed optional field is skipped; log it so a broken client build gets noticed. */
    private static function dropped(string $where, string $field): void
    {
        Log::warning('messages.malformed_field', ['doc' => $where, 'field' => $field]);
    }
}
