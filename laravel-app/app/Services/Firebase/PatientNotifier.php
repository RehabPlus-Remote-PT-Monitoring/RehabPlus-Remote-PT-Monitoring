<?php

namespace App\Services\Firebase;

use Illuminate\Support\Facades\Log;

/**
 * Tells a patient's phone about something: an entry on the app's
 * Notifications page (patients/{uid}/notifications) plus an FCM push to every
 * registered device (patients/{uid}/devices). See API_CONTRACT.md in the app repo.
 */
class PatientNotifier
{
    public function __construct(private FirestoreClient $db, private FirebaseAdmin $admin)
    {
    }

    /**
     * The Notifications-page entry, as a write to include in the caller's commit
     * so it is saved together with whatever it announces.
     */
    public function notificationWrite(string $patientUid, string $type, string $title, string $body, array $data = []): array
    {
        return $this->db->createWrite("patients/{$patientUid}/notifications/".FirestoreClient::newId(), array_filter([
            'type' => $type,
            'title' => $title,
            'body' => $body,
            'data' => $data ?: null,
            'read' => false,
        ], fn ($v) => $v !== null), serverTimestamps: ['createdAt']);
    }

    /**
     * Push to each of the patient's phones. Dead tokens are deleted; other
     * failures are logged and never thrown (the data is already saved).
     *
     * @return int number of phones reached
     */
    public function push(string $patientUid, string $title, string $body, array $data): int
    {
        $sent = 0;

        try {
            foreach ($this->db->query("patients/{$patientUid}", 'devices') as $device) {
                $result = $this->admin->sendPush($device['_id'], $title, $body, $data);

                if ($result === 'sent') {
                    $sent++;
                } elseif ($result === 'dead') {
                    $this->db->delete($device['_path']);
                } else {
                    Log::warning('FCM push failed', ['patient' => $patientUid]);
                }
            }
        } catch (FirebaseException $e) {
            Log::warning('FCM push skipped: '.$e->getMessage(), ['patient' => $patientUid]);
        }

        return $sent;
    }
}
