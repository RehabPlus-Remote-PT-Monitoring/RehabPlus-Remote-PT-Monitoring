<?php

namespace App\Services\Firebase;

use Google\Auth\Credentials\ServiceAccountCredentials;
use Illuminate\Support\Facades\Cache;
use Throwable;

/**
 * OAuth access token for the Firebase service account (FIREBASE_CREDENTIALS).
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
            $path = config('services.firebase.credentials');

            if (! $path || ! is_readable($path)) {
                throw new FirebaseException('Firebase is not configured. Set FIREBASE_CREDENTIALS in .env to the service-account JSON path.');
            }

            try {
                $token = (new ServiceAccountCredentials(self::SCOPES, $path))->fetchAuthToken();
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
        $path = config('services.firebase.credentials');

        return $path && is_readable($path);
    }
}
