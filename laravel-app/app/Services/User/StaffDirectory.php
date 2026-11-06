<?php

namespace App\Services\User;

use App\Auth\StaffUser;
use App\Helpers\PhoneNumber;
use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\FirestoreClient;
use Illuminate\Support\Facades\Cache;

/**
 * The current name and photo of every staff account, by uid.
 *
 * Records (patients, notes, messages, shifts...) also keep the name that was
 * saved when they were written, for history and for the mobile app. The
 * dashboard shows the name from here instead, so a rename or a new photo
 * shows everywhere. Saved names are only used when an account isn't known.
 */
class StaffDirectory
{
    private const CACHE_KEY = 'staff-directory';

    /** Another server can show an old name for up to this long after a change. */
    private const CACHE_SECONDS = 300;

    private ?array $loaded = null;

    public function __construct(private FirestoreClient $db)
    {
    }

    /** @return array<string, array{name: string, role: string, photoUrl: string, active: bool}> */
    public function all(): array
    {
        if ($this->loaded === null) {
            try {
                $this->loaded = Cache::remember(self::CACHE_KEY, self::CACHE_SECONDS, fn () => $this->load());
            } catch (FirebaseException) {
                // Firestore is unavailable: records show the names saved on them, and the page still loads.
                return [];
            }
        }

        return $this->loaded;
    }

    /** @return array<string, array{name: string, role: string, photoUrl: string, active: bool}> */
    private function load(): array
    {
        $batches = $this->db->concurrently(array_map(
            fn (string $role) => fn () => $this->db->query('', 'users', [['role', 'EQUAL', $role]]),
            StaffUser::ROLES,
        ));

        $directory = [];
        foreach (array_merge([], ...array_values($batches)) as $doc) {
            $directory[$doc['_id']] = [
                'name' => (string) ($doc['name'] ?? ''),
                'role' => (string) ($doc['role'] ?? ''),
                'photoUrl' => self::safePhotoUrl($doc['photoUrl'] ?? null),
                'contactPhone' => (string) ($doc['contactPhone'] ?? ''),
                'contactEmail' => (string) ($doc['contactEmail'] ?? ''),
                'active' => ($doc['active'] ?? true) !== false,
            ];
        }

        return $directory;
    }

    /**
     * Active staff for the public board, grouped by role (physical therapists, then
     * administrators), each group sorted by name. Shows only the public details: name,
     * photo, and the contact number and email the staff member chose. Never the login
     * email. Roles with nobody active are left out.
     *
     * @return list<array{role: string, members: list<array{name: string, photoUrl: string, phone: string, email: string}>}>
     */
    public function board(): array
    {
        $groups = [];

        // Physical therapists first, then administrators.
        foreach ([StaffUser::THERAPIST, StaffUser::ADMIN] as $role) {
            $members = array_values(array_filter($this->all(), fn ($u) => $u['active'] && $u['role'] === $role));
            if ($members === []) {
                continue;
            }

            usort($members, fn ($a, $b) => strcasecmp($a['name'], $b['name']));
            $groups[] = [
                'role' => StaffUser::ROLE_LABELS[$role] ?? ucfirst($role),
                'members' => array_map(fn ($u) => [
                    'name' => $u['name'],
                    'photoUrl' => $u['photoUrl'],
                    'phone' => $u['contactPhone'] !== '' ? PhoneNumber::display($u['contactPhone']) : '',
                    'email' => filter_var($u['contactEmail'], FILTER_VALIDATE_EMAIL) ? $u['contactEmail'] : '',
                ], $members),
            ];
        }

        return $groups;
    }

    /** Call after a staff account changes, so this server shows the change at once. */
    public function forget(): void
    {
        $this->loaded = null;
        Cache::forget(self::CACHE_KEY);
    }

    /** The account's current name, or the saved name when the account isn't known. */
    public function name(?string $uid, string $saved = ''): string
    {
        $account = $uid !== null ? ($this->all()[$uid] ?? null) : null;

        return $account !== null && $account['name'] !== '' ? $account['name'] : $saved;
    }

    /** The account's current photo, or '' to show initials. */
    public function photoUrl(?string $uid): string
    {
        return $uid !== null ? ($this->all()[$uid]['photoUrl'] ?? '') : '';
    }

    /**
     * A photo is used only from Firebase Storage (the image host the
     * Content-Security-Policy allows), this site's staff photo folder, or a
     * picture uploaded on My Profile and stored as a data URL.
     */
    public static function safePhotoUrl(mixed $url): string
    {
        $allowed = '#^(https://(firebasestorage|storage)\.googleapis\.com/|/assets/images/staff/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp)$|data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$)#';

        return is_string($url) && preg_match($allowed, $url) ? $url : '';
    }
}
