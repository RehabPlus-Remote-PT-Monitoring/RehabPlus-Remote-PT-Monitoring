<?php

namespace App\Services\Patient;

use App\Auth\FirebaseUserProvider;
use App\Auth\StaffUser;
use App\Helpers\PhoneNumber;
use App\Rules\OfficialEmailDomain;
use App\Services\Firebase\FirebaseAdmin;
use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\FirestoreClient;
use App\Services\Firebase\PatientNotifier;
use App\Services\User\StaffDirectory;
use App\Services\User\UserService;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;

/**
 * Patients live in Firestore patients/{uid}, keyed by their Firebase Auth uid
 * (they sign in to the mobile app with it). See API_CONTRACT.md in the app repo.
 *
 * The service account bypasses Firestore rules, so access is checked here:
 *   - administrators see every patient
 *   - therapists see only patients whose therapistId is their uid
 *   - only admins and the patient's own therapist change anything
 */
class PatientService
{
    /** The gender choices the app accepts ('' = not set). Same list as firestore.rules and ProfileService. */
    public const GENDERS = ['Female', 'Male', 'Other', 'Prefer not to say'];

    /** Body measurement limits, the same as firestore.rules and the app. */
    public const MIN_WEIGHT_KG = 1;
    public const MAX_WEIGHT_KG = 500;
    public const MIN_HEIGHT_CM = 30;
    public const MAX_HEIGHT_CM = 300;

    /**
     * The app writes the date of birth as "December 5, 1996" (ProfileService / edit_profile_screen),
     * so the dashboard writes the same text. Older dashboard records hold "1996-12-05"; both are read.
     */
    public const BIRTH_DATE_FORMAT = 'F j, Y';

    public function __construct(
        private FirestoreClient $db,
        private FirebaseAdmin $admin,
        private UserService $users,
        private StaffDirectory $directory,
        private PatientNotifier $notifier,
    ) {
    }

    /** Patients this user may see, sorted by name. */
    public function visible(StaffUser $user, bool $includeArchived = false): array
    {
        $docs = $user->isTherapist()
            ? $this->db->query('', 'patients', [['therapistId', 'EQUAL', $user->id]])
            : $this->db->query('', 'patients');

        $patients = array_map(fn ($d) => $this->present($d), $docs);
        if (! $includeArchived) {
            $patients = array_filter($patients, fn ($p) => ! $p['archived']);
        }
        usort($patients, fn ($a, $b) => strcasecmp($a['name'], $b['name']));

        return array_values($patients);
    }

    /** Patients list page data: search by name or email, filter by condition. */
    public function search(StaffUser $user, string $search, string $condition, bool $archived): array
    {
        $all = $this->visible($user, includeArchived: true);
        $needle = mb_strtolower($search);

        $data = array_filter($all, fn ($p) => $p['archived'] === $archived
            && ($condition === '' || $p['condition'] === $condition)
            && ($needle === '' || str_contains(mb_strtolower($p['name'].' '.$p['email']), $needle)));

        $conditions = array_unique(array_filter(array_column($all, 'condition')));
        sort($conditions, SORT_NATURAL | SORT_FLAG_CASE);

        return [
            'data' => array_values($data),
            'conditions' => $conditions,
            'search' => $search,
            'selectedCondition' => $condition,
            'showArchived' => $archived,
        ];
    }

    /** The patient if this user may see them, else null (callers 404). */
    public function find(StaffUser $user, string $uid): ?array
    {
        if (! FirestoreClient::isValidId($uid)) {
            return null;
        }

        $doc = $this->db->get("patients/{$uid}");
        $patient = $doc ? $this->present($doc) : null;

        if (! $patient || ! $this->canView($user, $patient)) {
            return null;
        }

        // Patients created by older seed scripts have no email on their profile.
        if ($patient['email'] === '') {
            $patient['email'] = (string) ($this->db->get("users/{$uid}")['email'] ?? '');
        }

        return $patient;
    }

    public function canView(StaffUser $user, array $patient): bool
    {
        return ! $user->isTherapist() || $patient['therapistId'] === $user->id;
    }

    /** Edit profile, prescriptions, assessments, goals and notes. */
    public function canManage(StaffUser $user, array $patient): bool
    {
        return $user->isAdmin() || ($user->isTherapist() && $patient['therapistId'] === $user->id);
    }

    /**
     * Create the patient's app login (Firebase Auth, temporary password) plus
     * users/{uid} and patients/{uid}. A therapist's new patient is assigned to
     * them; an admin picks the therapist (or none).
     *
     * @return string the new patient's uid
     */
    public function create(StaffUser $by, array $data): string
    {
        if (! OfficialEmailDomain::allows($data['email'])) {
            throw new \InvalidArgumentException(OfficialEmailDomain::MESSAGE);
        }

        [$therapistId, $therapistName] = $this->therapistFor($by, $data['therapist_id'] ?? null);

        $uid = $this->admin->createUser($data['email'], $data['password'], $data['name']);

        $this->users->commitOrRollBack($uid, [
            $this->db->createWrite("users/{$uid}", [
                'role' => 'patient',
                'name' => $data['name'],
                'email' => strtolower($data['email']),
                'active' => true,
            ], serverTimestamps: ['createdAt']),
            $this->db->createWrite("patients/{$uid}", $this->profileFields($data) + [
                'name' => $data['name'],
                'email' => strtolower($data['email']),
                'therapistId' => $therapistId,
                'therapistName' => $therapistName,
                'archived' => false,
                'createdBy' => $by->id,
            ], serverTimestamps: ['createdAt']),
        ]);

        return $uid;
    }

    public function update(StaffUser $by, array $patient, array $data): void
    {
        $fields = $this->profileFields($data) + ['name' => $data['name']];

        if ($by->isAdmin() && array_key_exists('therapist_id', $data)) {
            [$fields['therapistId'], $fields['therapistName']] = $this->therapistFor($by, $data['therapist_id']);
        }

        $writes = [
            $this->db->mergeWrite("patients/{$patient['uid']}", $fields, serverTimestamps: ['updatedAt']),
            $this->db->mergeWrite("users/{$patient['uid']}", ['name' => $data['name']]),
        ];

        // The patient is told when their medical summary or therapy plan changes, so they know it is there.
        $notice = $this->carePlanNotice($patient, $fields);
        if ($notice !== null) {
            $writes[] = $this->notifier->notificationWrite($patient['uid'], 'care_plan', 'Care Plan Updated', $notice);
        }

        $this->db->commit($writes);

        if ($notice !== null) {
            $this->notifier->push($patient['uid'], 'Care Plan Updated', $notice, ['type' => 'care_plan']);
        }

        // The login's display name is cosmetic (the app shows users/{uid}.name), so
        // a failure here mustn't report the already-saved edit as failed.
        if ($data['name'] !== $patient['name']) {
            try {
                $this->admin->updateUser($patient['uid'], ['displayName' => $data['name']]);
            } catch (FirebaseException $e) {
                Log::warning('Could not update patient display name: '.$e->getMessage(), ['patient' => $patient['uid']]);
            }
        }
    }

    /**
     * Archive (disable the app login and hide from lists) or restore. Nothing
     * is deleted: sessions and records stay for the clinic's history.
     */
    public function setArchived(array $patient, bool $archived, ?StaffUser $by = null): void
    {
        $this->admin->updateUser($patient['uid'], ['disabled' => $archived]);

        // The archive list shows when and by whom; restoring clears both.
        $change = ['archived' => $archived];
        $serverTimestamps = ['updatedAt'];
        if ($archived) {
            $change['archivedByName'] = $by?->name ?? '';
            $serverTimestamps[] = 'archivedAt';
        } else {
            $change += ['archivedAt' => null, 'archivedByName' => null];
        }

        $this->db->commit([
            $this->db->mergeWrite("patients/{$patient['uid']}", $change, serverTimestamps: $serverTimestamps),
            $this->db->mergeWrite("users/{$patient['uid']}", ['active' => ! $archived]),
        ]);
    }

    /**
     * Permanently delete an archived patient: their record with everything
     * stored under it (sessions, prescriptions, notes, messages...), then their
     * login. The login is already disabled by archiving, so if this stops part
     * way the patient can't sign in and the delete can simply be run again.
     */
    public function deletePermanently(array $patient): void
    {
        $this->db->deleteTree("patients/{$patient['uid']}");
        $this->db->delete("users/{$patient['uid']}");
        $this->admin->deleteUser($patient['uid']);
        FirebaseUserProvider::forget($patient['uid']);
        Cache::forget(FirebaseAdmin::uidCacheKey($patient['email']));
    }

    /**
     * Put the patient's mobile number on their app login, which is where the app's
     * "Forgot password" texts its code (Firebase Phone Auth). Firebase allows a number on
     * only one login, and family members can share a phone, so a failure doesn't undo the
     * saved patient: it returns the warning to show staff, or null when linked.
     */
    public function linkLoginPhone(string $uid, string $stored): ?string
    {
        $number = PhoneNumber::toE164($stored);
        $problem = 'That phone number is not valid.';

        if ($number !== null) {
            try {
                $this->admin->updateUser($uid, ['phoneNumber' => $number]);

                return null;
            } catch (FirebaseException $e) {
                Log::warning('Could not link patient phone: '.$e->getMessage(), ['patient' => $uid]);
                $problem = $e->getMessage();
            }
        }

        return "Saved, but this patient can't get password reset codes by text yet. {$problem} Use Reset password on their page if they forget it.";
    }

    /** Set a new temporary app password (the patient can change it via "Forgot password"). */
    public function resetPassword(array $patient, string $password): void
    {
        $this->admin->updateUser($patient['uid'], ['password' => $password]);
    }

    public function present(array $doc): array
    {
        $birth = self::parseBirthDate((string) ($doc['dob'] ?? ''));

        return [
            'uid' => $doc['_id'],
            'name' => (string) ($doc['name'] ?? 'Unnamed patient'),
            'email' => (string) ($doc['email'] ?? ''),
            'condition' => (string) ($doc['condition'] ?? ''),
            'therapistId' => $doc['therapistId'] ?? null,
            'therapistName' => $this->directory->name($doc['therapistId'] ?? null, (string) ($doc['therapistName'] ?? '')),
            'medicalSummary' => (string) ($doc['medicalSummary'] ?? ''),
            'therapyPlan' => (string) ($doc['therapyPlan'] ?? ''),
            'phone' => (string) ($doc['phone'] ?? ''),
            // Shown as "May 14, 1990" (or the stored text when it isn't a date); the form uses birthDate.
            'dob' => $birth ? $birth->format(self::BIRTH_DATE_FORMAT) : (string) ($doc['dob'] ?? ''),
            'birthDate' => $birth ? $birth->format('Y-m-d') : '',
            'age' => $birth ? self::ageOn($birth) : null,
            'gender' => in_array($doc['gender'] ?? null, self::GENDERS, true) ? $doc['gender'] : '',
            'weightKg' => self::measurement($doc['weightKg'] ?? null, self::MIN_WEIGHT_KG, self::MAX_WEIGHT_KG),
            'heightCm' => self::measurement($doc['heightCm'] ?? null, self::MIN_HEIGHT_CM, self::MAX_HEIGHT_CM),
            'address' => (string) ($doc['address'] ?? ''),
            'addressStreet' => (string) ($doc['addressStreet'] ?? ''),
            'addressBarangay' => (string) ($doc['addressBarangay'] ?? ''),
            'addressCity' => (string) ($doc['addressCity'] ?? ''),
            'addressProvince' => (string) ($doc['addressProvince'] ?? ''),
            'createdAt' => $doc['createdAt'] ?? null,
            'archived' => (bool) ($doc['archived'] ?? false),
            'archivedAt' => $doc['archivedAt'] ?? null,
            'archivedByName' => (string) ($doc['archivedByName'] ?? ''),
        ];
    }

    /**
     * The date of birth as the app stores it ("May 14, 1990"), from the form's Y-m-d value. '' when not set.
     */
    public static function storedBirthDate(string $ymd): string
    {
        $birth = $ymd === '' ? null : self::fromFormat($ymd, 'Y-m-d');

        return $birth ? $birth->format(self::BIRTH_DATE_FORMAT) : '';
    }

    /**
     * Reads a stored date of birth in either format the apps and dashboard have used, or null if it
     * isn't a date. Both formats are checked strictly, so text like "Sept 2026" is not guessed.
     */
    public static function parseBirthDate(string $stored): ?CarbonImmutable
    {
        $stored = trim($stored);
        if ($stored === '') {
            return null;
        }

        foreach (['Y-m-d', self::BIRTH_DATE_FORMAT] as $format) {
            $parsed = self::fromFormat($stored, $format);
            if ($parsed !== null && $parsed->format($format) === $stored) {
                return $parsed->startOfDay();
            }
        }

        return null;
    }

    /**
     * Parses [text] with [format], or null. Uses DateTimeImmutable because Carbon's own
     * createFromFormat throws on text that doesn't match, which would break the profile page.
     */
    private static function fromFormat(string $text, string $format): ?CarbonImmutable
    {
        $parsed = \DateTimeImmutable::createFromFormat('!'.$format, $text);

        return $parsed === false ? null : CarbonImmutable::instance($parsed);
    }

    /** Whole years between the date of birth and today (the app's timezone), or null for a future date. */
    public static function ageOn(CarbonImmutable $birth, ?CarbonImmutable $today = null): ?int
    {
        $today ??= CarbonImmutable::now(config('app.timezone'))->startOfDay();
        if ($birth->greaterThan($today)) {
            return null;
        }

        // Full years: one less until the birthday has happened this year.
        $age = (int) $today->format('Y') - (int) $birth->format('Y');
        if ($today->format('md') < $birth->format('md')) {
            $age--;
        }

        return $age;
    }

    /** A stored weight or height as a number, or null when it's not set or out of range. */
    private static function measurement(mixed $value, float $min, float $max): ?float
    {
        if (! is_int($value) && ! is_float($value)) {
            return null;
        }

        return $value >= $min && $value <= $max ? (float) $value : null;
    }

    /** Form fields that map 1:1 onto the patients doc. */
    private function profileFields(array $data): array
    {
        return [
            'condition' => $data['condition'],
            'medicalSummary' => (string) ($data['medical_summary'] ?? ''),
            'therapyPlan' => (string) ($data['therapy_plan'] ?? ''),
            'phone' => (string) ($data['phone'] ?? ''),
            // Same text the app writes, so both show the same date.
            'dob' => self::storedBirthDate((string) ($data['dob'] ?? '')),
            // The app's edit screen fields. Blank means not set: '' for gender, null for the measurements.
            'gender' => (string) ($data['gender'] ?? ''),
            'weightKg' => isset($data['weight_kg']) ? (float) $data['weight_kg'] : null,
            'heightCm' => isset($data['height_cm']) ? (float) $data['height_cm'] : null,
            'addressStreet' => trim((string) ($data['address_street'] ?? '')),
            'addressBarangay' => trim((string) ($data['address_barangay'] ?? '')),
            'addressCity' => trim((string) ($data['address_city'] ?? '')),
            'addressProvince' => trim((string) ($data['address_province'] ?? '')),
            // One line for the profile and the app: the parts that are filled in, joined with commas.
            'address' => implode(', ', array_filter([
                trim((string) ($data['address_street'] ?? '')),
                trim((string) ($data['address_barangay'] ?? '')),
                trim((string) ($data['address_city'] ?? '')),
                trim((string) ($data['address_province'] ?? '')),
            ])),
        ];
    }

    /** What the patient is told when the medical summary or therapy plan changed, or null if neither did. */
    private function carePlanNotice(array $patient, array $fields): ?string
    {
        $summaryChanged = $patient['medicalSummary'] !== $fields['medicalSummary'];
        $planChanged = $patient['therapyPlan'] !== $fields['therapyPlan'];

        return match (true) {
            $summaryChanged && $planChanged => 'Your medical summary and therapy plan were updated.',
            $summaryChanged => 'Your medical summary was updated.',
            $planChanged => 'Your therapy plan was updated.',
            default => null,
        };
    }

    /** @return array{0: ?string, 1: string} therapistId and therapistName */
    private function therapistFor(StaffUser $by, ?string $therapistId): array
    {
        if ($by->isTherapist()) {
            return [$by->id, $by->name];
        }
        if (! $therapistId) {
            return [null, ''];
        }

        $therapist = $this->users->findStaff($therapistId);
        if (! $therapist || $therapist['role'] !== StaffUser::THERAPIST) {
            throw new FirebaseException('The selected therapist no longer exists.');
        }

        return [$therapist['uid'], $therapist['name']];
    }
}
