<?php

namespace App\Services\Patient;

use App\Auth\StaffUser;
use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\FirestoreClient;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Log;

/**
 * The clinician-validated clinical & dietary profile:
 * patients/{uid}/clinical/profile (API_CONTRACT.md "Clinical safeguards").
 *
 * Written only by the dashboard (admin or the patient's therapist; the app's
 * rules deny every client write). The app reads it to lock restricted
 * exercises and show a caution for low tolerance.
 *
 * Diet informs context only: precautions, dietaryNotes and nutritionFlags are
 * displayed and never change a prescription, a target or the completion gate.
 * Only restrictedExercises and lowTolerance have effects, and only because a
 * clinician set them.
 */
class ClinicalProfileService
{
    /** The profile was read (it may be empty: no doc saved yet). */
    public const OK = 'ok';

    /** The profile couldn't be read (Firebase error or bad uid). */
    public const UNAVAILABLE = 'unavailable';

    /** Contract codes => labels staff read. Unknown codes in a doc are ignored. */
    public const NUTRITION_FLAGS = [
        'diabetes' => 'Diabetes',
        'hypertension' => 'Hypertension',
        'low_intake' => 'Poor appetite / undernourished',
        'dehydration_risk' => 'Dehydration risk',
        'anemia' => 'Anemia',
        'weight_management' => 'Weight management',
        'renal_diet' => 'Renal diet',
        'food_allergy' => 'Food allergy',
    ];

    /** Contract text limits. */
    public const MAX_PRECAUTIONS = 1000;

    public const MAX_DIETARY_NOTES = 1000;

    public const MAX_TOLERANCE_NOTE = 500;

    /** Tolerance review window and pain thresholds (design doc section 2). */
    public const REVIEW_DAYS = 14;

    public const REVIEW_PAIN_SENSITIVE = 6;

    public const REVIEW_PAIN_ANYONE = 8;

    public function __construct(private FirestoreClient $db)
    {
    }

    public static function path(string $patientUid): string
    {
        return "patients/{$patientUid}/clinical/profile";
    }

    /**
     * The profile for the patient page. Never throws for a Firebase failure:
     * a failed read is logged and reported as "unavailable" so it can sit in
     * the page's concurrently() batch without failing the other reads (same
     * approach as ConsentService).
     *
     * @return array{status: string, profile: array}
     */
    public function forPatient(string $patientUid): array
    {
        if (! FirestoreClient::isValidId($patientUid)) {
            Log::warning('clinical_profile.invalid_patient_id', ['patient' => mb_substr($patientUid, 0, 130)]);

            return ['status' => self::UNAVAILABLE, 'profile' => self::present(null)];
        }

        try {
            return ['status' => self::OK, 'profile' => $this->read($patientUid)];
        } catch (FirebaseException $e) {
            Log::warning('clinical_profile.unreadable', ['patient' => $patientUid, 'error' => $e->getMessage()]);

            return ['status' => self::UNAVAILABLE, 'profile' => self::present(null)];
        }
    }

    /**
     * The profile, throwing on a Firebase failure. Used where a decision
     * depends on it (assigning a prescription, signing a clearance): if the
     * restrictions can't be read, the action must not go ahead.
     */
    public function read(string $patientUid): array
    {
        return self::present($this->db->get(self::path($patientUid)));
    }

    /**
     * Save the profile from validated form data. A merge of every contract
     * field, so it creates the doc on first save and overwrites each field
     * on later ones; validatedAt is the server time.
     */
    public function save(StaffUser $by, array $patient, array $data): void
    {
        $fields = [
            'precautions' => trim((string) ($data['precautions'] ?? '')),
            'dietaryNotes' => trim((string) ($data['dietary_notes'] ?? '')),
            'nutritionFlags' => self::knownCodes($data['nutrition_flags'] ?? [], array_keys(self::NUTRITION_FLAGS)),
            'restrictedExercises' => self::knownCodes($data['restricted_exercises'] ?? [], ExerciseCatalog::codes()),
            'lowTolerance' => (bool) ($data['low_tolerance'] ?? false),
            'toleranceNote' => trim((string) ($data['tolerance_note'] ?? '')),
            'validatedBy' => $by->id,
            'validatedByName' => $by->name,
            'nextReassessmentAt' => empty($data['next_reassessment_at'])
                ? null
                : CarbonImmutable::parse($data['next_reassessment_at'], config('app.timezone'))->startOfDay(),
        ];

        $this->db->commit([
            $this->db->mergeWrite(self::path($patient['uid']), $fields, serverTimestamps: ['validatedAt']),
        ]);

        Log::info('clinical_profile.saved', [
            'patient' => $patient['uid'],
            'by' => $by->id,
            'restricted' => count($fields['restrictedExercises']),
            'lowTolerance' => $fields['lowTolerance'],
        ]);
    }

    /**
     * Firestore doc (or null when none was saved yet) -> the shape views and
     * checks use. Every field is coerced: the doc is dashboard-written, but a
     * hand-edited or older doc must not break the patient page.
     */
    public static function present(?array $doc): array
    {
        $doc ??= [];

        return [
            'exists' => $doc !== [],
            'precautions' => self::text($doc['precautions'] ?? null, self::MAX_PRECAUTIONS),
            'dietaryNotes' => self::text($doc['dietaryNotes'] ?? null, self::MAX_DIETARY_NOTES),
            'nutritionFlags' => self::knownCodes($doc['nutritionFlags'] ?? [], array_keys(self::NUTRITION_FLAGS)),
            'restrictedExercises' => self::knownCodes($doc['restrictedExercises'] ?? [], ExerciseCatalog::codes()),
            'lowTolerance' => ($doc['lowTolerance'] ?? false) === true,
            'toleranceNote' => self::text($doc['toleranceNote'] ?? null, self::MAX_TOLERANCE_NOTE),
            'validatedBy' => self::text($doc['validatedBy'] ?? null, 128),
            'validatedByName' => self::text($doc['validatedByName'] ?? null, 100),
            'validatedAt' => ($doc['validatedAt'] ?? null) instanceof CarbonImmutable ? $doc['validatedAt'] : null,
            'nextReassessmentAt' => ($doc['nextReassessmentAt'] ?? null) instanceof CarbonImmutable ? $doc['nextReassessmentAt'] : null,
        ];
    }

    /**
     * Sessions that need a clinician's look (computed, never stored):
     * in the last 14 days, painLevel >= 6 or ended early for a patient the
     * clinician flagged as low tolerance or with any nutrition flag; or
     * painLevel >= 8 for anyone.
     *
     * @param  array  $profile  presented profile (present())
     * @param  array<int, array>  $sessions  presented sessions (PatientProgress::presentSession)
     * @return array<int, array> the flagged sessions, newest first
     */
    public static function toleranceReview(array $profile, array $sessions, ?CarbonImmutable $now = null): array
    {
        $since = ($now ?? CarbonImmutable::now())->subDays(self::REVIEW_DAYS);
        $sensitive = ($profile['lowTolerance'] ?? false) === true || ($profile['nutritionFlags'] ?? []) !== [];

        $flagged = array_values(array_filter($sessions, function (array $s) use ($since, $sensitive) {
            $startTime = $s['startTime'] ?? null;
            if (! ($startTime instanceof CarbonImmutable) || $startTime->lessThan($since)) {
                return false;
            }
            $pain = $s['painLevel'] ?? null;

            if ($pain !== null && $pain >= self::REVIEW_PAIN_ANYONE) {
                return true;
            }

            return $sensitive && (($pain !== null && $pain >= self::REVIEW_PAIN_SENSITIVE) || ($s['endedEarly'] ?? false) === true);
        }));

        usort($flagged, fn ($a, $b) => $b['startTime']->getTimestamp() <=> $a['startTime']->getTimestamp());

        return $flagged;
    }

    /** Only known codes, each once, in the list's own order. */
    private static function knownCodes(mixed $values, array $allowed): array
    {
        if (! is_array($values)) {
            return [];
        }

        return array_values(array_filter($allowed, fn (string $code) => in_array($code, $values, true)));
    }

    /** Text cut to $max characters; anything that isn't a string is ''. */
    private static function text(mixed $value, int $max): string
    {
        return is_string($value) ? mb_substr($value, 0, $max) : '';
    }
}
