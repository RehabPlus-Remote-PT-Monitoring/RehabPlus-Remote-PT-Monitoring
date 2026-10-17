<?php

namespace App\Services\Firebase;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;

/** Firebase Auth admin lookups and FCM pushes over REST, using the service account. */
class FirebaseAdmin
{
    public function __construct(private GoogleAccessToken $token, private FirestoreClient $firestore)
    {
    }

    /**
     * Firebase Auth uid for an email, or null if there is no such account.
     * Cached for 10 minutes; staff emails rarely change.
     */
    public function uidForEmail(string $email): ?string
    {
        $email = strtolower(trim($email));

        return Cache::remember('firebase.uid.'.sha1($email), now()->addMinutes(10), function () use ($email) {
            $response = $this->post(
                "https://identitytoolkit.googleapis.com/v1/projects/{$this->firestore->projectId()}/accounts:lookup",
                ['email' => [$email]],
            );

            if ($response->failed()) {
                throw new FirebaseException('Firebase Auth lookup failed ('.$response->status().').');
            }

            return $response->json('users.0.localId');
        });
    }

    /**
     * Send one FCM message.
     *
     * @return string 'sent', 'dead' (token no longer valid, delete it) or 'failed'
     */
    public function sendPush(string $deviceToken, string $title, string $body, array $data): string
    {
        $response = $this->post(
            "https://fcm.googleapis.com/v1/projects/{$this->firestore->projectId()}/messages:send",
            ['message' => [
                'token' => $deviceToken,
                'notification' => ['title' => $title, 'body' => $body],
                'data' => array_map('strval', $data),
                'android' => ['priority' => 'high', 'notification' => ['channel_id' => 'chat_messages']],
            ]],
        );

        if ($response->successful()) {
            return 'sent';
        }

        $code = $response->json('error.details.0.errorCode') ?? $response->json('error.status');

        return in_array($code, ['UNREGISTERED', 'INVALID_ARGUMENT'], true) ? 'dead' : 'failed';
    }

    private function post(string $url, array $data): Response
    {
        try {
            return Http::withToken($this->token->get())->acceptJson()->timeout(15)->post($url, $data);
        } catch (ConnectionException $e) {
            throw new FirebaseException('Could not reach Firebase (network error).', 0, $e);
        }
    }
}
