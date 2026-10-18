<?php

namespace App\Services\Firebase;

use Google\Auth\Credentials\ServiceAccountCredentials;
use Illuminate\Support\Facades\Cache;
use Throwable;

/**
 * OAuth access token for the Firebase service account.
 *
 * The key comes from FIREBASE_CREDENTIALS_JSON (the JSON itself, raw or
 * base64; for hosts without a disk such as Vercel) or else from the file at
 * FIREBASE_CREDENTIALS.
 *
 * One token covers Firestore, Firebase Auth lookups and FCM. It is cached
 * until a minute before it expires, so most requests don't hit Google's
 * token endpoint.
 */
class GoogleAccessToken
{
    private const SCOPES = [
        'https://www.googleapis.com/auth/cloud-platform',
        'https://www.googleapis.com/auth/firebase.messaging',
    ];

    public function get(): string
    {
        return Cache::remember('firebase.access_token', now()->addMinutes(50), function () {
            $key = self::serviceAccountKey();

            if ($key === null) {
                throw new FirebaseException('Firebase is not configured. Set FIREBASE_CREDENTIALS (path to the service-account JSON) or FIREBASE_CREDENTIALS_JSON.');
            }

            try {
                $token = (new ServiceAccountCredentials(self::SCOPES, $key))->fetchAuthToken();
            } catch (Throwable $e) {
                throw new FirebaseException('Could not get a Firebase access token (network error or invalid service account).', 0, $e);
            }

            if (empty($token['access_token'])) {
                throw new FirebaseException('Could not get a Firebase access token from the service account.');
            }

            return $token['access_token'];
        });
    }

    public static function isConfigured(): bool
    {
        return self::serviceAccountKey() !== null;
    }

    /**
     * The decoded key from FIREBASE_CREDENTIALS_JSON, else the readable file
     * path from FIREBASE_CREDENTIALS, else null.
     */
    private static function serviceAccountKey(): array|string|null
    {
        $json = trim((string) config('services.firebase.credentials_json'));
        if ($json !== '') {
            $key = json_decode($json, true);
            if (! is_array($key)) {
                $key = json_decode((string) base64_decode($json, true), true);
            }

            return is_array($key) && isset($key['private_key'], $key['client_email']) ? $key : null;
        }

        $path = config('services.firebase.credentials');

        return $path && is_readable($path) ? $path : null;
    }
}
