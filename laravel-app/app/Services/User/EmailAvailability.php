<?php

namespace App\Services\User;

use App\Services\Firebase\FirebaseAdmin;
use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\FirestoreClient;
use Illuminate\Support\Facades\Log;

/**
 * Whether an email already belongs to an account. Patients and staff share one
 * login system, so an email is taken if any staff or patient account uses it.
 *
 * Two places are checked: the users collection (every staff and patient account
 * the dashboard created) and Firebase Auth (every login, including old ones).
 * If one of them can't be reached, the other still decides, and the account
 * creation itself refuses a taken email as a last check.
 */
class EmailAvailability
{
    public const TAKEN_MESSAGE = 'This email is already taken by another account.';

    public function __construct(private FirestoreClient $db, private FirebaseAdmin $admin)
    {
    }

    public function isTaken(string $email): bool
    {
        $email = strtolower(trim($email));

        try {
            if ($this->db->query('', 'users', [['email', 'EQUAL', $email]], limit: 1) !== []) {
                return true;
            }
        } catch (FirebaseException $e) {
            Log::info('Email check: users not read', ['error' => $e->getMessage()]);
        }

        try {
            return $this->admin->uidForEmail($email) !== null;
        } catch (FirebaseException $e) {
            Log::info('Email check: Firebase Auth not read', ['error' => $e->getMessage()]);

            return false;
        }
    }
}
