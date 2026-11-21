<?php

namespace App\Services\Messaging;

use RuntimeException;

/**
 * A chat action (reply-to, edit, unsend, pin) that can't be done. The
 * controller turns it into a response:
 *   - NOT_FOUND: 404, the message isn't in this conversation (or the id is bad)
 *   - FORBIDDEN: 403, it's someone else's message
 *   - REJECTED:  back to the conversation with the message as an error,
 *                e.g. the 15-minute edit window has passed
 * The message is safe to show staff.
 */
class ChatActionException extends RuntimeException
{
    public const NOT_FOUND = 404;

    public const FORBIDDEN = 403;

    public const REJECTED = 422;

    public static function notFound(): self
    {
        return new self('That message is not in this conversation.', self::NOT_FOUND);
    }

    public static function forbidden(string $message): self
    {
        return new self($message, self::FORBIDDEN);
    }

    public static function rejected(string $message): self
    {
        return new self($message, self::REJECTED);
    }
}
