<?php

namespace App\Services\Firebase;

/**
 * A Firestore `bytes` value (REST: `bytesValue`, base64 in the JSON).
 *
 * Kept as its own type instead of a plain string so binary data can never be
 * mistaken for text: services that expect a string field (and coerce with
 * is_string) simply ignore it, and code that wants bytes can check for this
 * class. Holds the raw, already base64-decoded bytes.
 */
final class FirestoreBytes
{
    public function __construct(public readonly string $raw) {}

    /**
     * From the base64 text Firestore REST sends. Strict decoding: anything
     * that isn't valid base64 is a malformed response, not data to guess at.
     */
    public static function fromBase64(string $base64): self
    {
        $raw = base64_decode($base64, true);
        if ($raw === false) {
            throw new FirebaseException('Firebase returned a malformed bytes value.');
        }

        return new self($raw);
    }

    public function toBase64(): string
    {
        return base64_encode($this->raw);
    }

    /** Size in bytes. */
    public function length(): int
    {
        return strlen($this->raw);
    }
}
