<?php

namespace App\Services\Patient;

use App\Services\Firebase\FirestoreBytes;
use App\Services\Firebase\FirestoreClient;

/**
 * A patient's profile picture. The app sets it at patients/{uid}/avatar/photo
 * (field `image`, JPEG bytes, at most 500 KB); the dashboard only reads it.
 * With no picture, a grey and white default silhouette is shown, in the form
 * that suits the patient's gender (see API_CONTRACT.md).
 */
class PatientAvatarService
{
    /** The app's limit for a picture (its rule). Anything larger is ignored and the default shows. */
    public const MAX_BYTES = 500 * 1024;

    public const DEFAULT = 'assets/images/avatars/default.svg';

    public const MALE = 'assets/images/avatars/male.svg';

    public const FEMALE = 'assets/images/avatars/female.svg';

    public function __construct(private FirestoreClient $db)
    {
    }

    /** The picture as a data URL, or null when the patient has none (or it is unusable). */
    public function photoDataUrl(string $uid): ?string
    {
        if (! FirestoreClient::isValidId($uid)) {
            return null;
        }

        $doc = $this->db->get("patients/{$uid}/avatar/photo");
        $image = $doc['image'] ?? null;

        if (! $image instanceof FirestoreBytes || $image->length() === 0 || $image->length() > self::MAX_BYTES) {
            return null;
        }

        return 'data:image/jpeg;base64,'.$image->toBase64();
    }

    /** The default silhouette for a gender: male, female, or the neutral one for anything else. */
    public static function defaultFor(?string $gender): string
    {
        return match ($gender) {
            'Male' => self::MALE,
            'Female' => self::FEMALE,
            default => self::DEFAULT,
        };
    }

    /** The URL to show: the patient's picture, or the default silhouette. */
    public function urlFor(string $uid, ?string $gender): string
    {
        return $this->photoDataUrl($uid) ?? asset(self::defaultFor($gender));
    }
}
