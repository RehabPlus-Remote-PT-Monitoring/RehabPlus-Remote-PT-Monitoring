<?php

namespace App\Services\Patient;

use App\Auth\StaffUser;
use App\Services\Firebase\FirebaseException;
use App\Services\Firebase\FirestoreClient;
use App\Services\Firebase\PatientNotifier;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Log;

/**
 * Physician clearance records: patients/{uid}/clearances/{id}
 * (API_CONTRACT.md "Clinical safeguards", design doc section 4).
 *
 * Append-only: every sign-off is a NEW document with a create precondition,
 * and nothing here (or any route) updates or deletes one. The newest by
 * signedAt is the patient's current clearance status.
 *
 * The decision is always a person's: a clearance is only written from the
 * sign-off form, never derived from completion or compliance. `cleared` is
 * refused unless the completion gate, recomputed on the server at submit
 * time, is ready_for_review (checked by the controller with currentGate()).
 */
class ClearanceService
{
    public const CLEARED = 'cleared';

    public const NOT_CLEARED = 'not_cleared';

    public const DECISIONS = [
        self::CLEARED => 'Cleared',
        self::NOT_CLEARED => 'Not cleared (continue / revise the program)',
    ];

    /** The history was read (it may be empty). */
    public const OK = 'ok';

    /** The history couldn't be read; the page shows "unavailable". */
    public const UNAVAILABLE = 'unavailable';

    public function __construct(
        private FirestoreClient $db,
        private PatientNotifier $notifier,
        private PrescriptionService $prescriptions,
        private PatientProgress $progress,
        private ClinicalProfileService $profiles,
    ) {
    }

    /**
     * Clearance history for the patient page, newest first. Never throws for
     * a Firebase failure (logged, "unavailable"), so it can join the page's
     * concurrently() batch without failing the other reads.
     *
     * @return array{status: string, records: array<int, array>}
     */
    public function history(string $patientUid): array
    {
        if (! FirestoreClient::isValidId($patientUid)) {
            Log::warning('clearances.invalid_patient_id', ['patient' => mb_substr($patientUid, 0, 130)]);

            return ['status' => self::UNAVAILABLE, 'records' => []];
        }

        try {
            $docs = $this->db->query("patients/{$patientUid}", 'clearances');
        } catch (FirebaseException $e) {
            Log::warning('clearances.unreadable', ['patient' => $patientUid, 'error' => $e->getMessage()]);

            return ['status' => self::UNAVAILABLE, 'records' => []];
        }

        return ['status' => self::OK, 'records' => self::newestFirst($docs)];
    }

    /**
     * Every session of the patient for the gate (no limit: the page's own
     * session list stops at 100, which would undercount long programs), or
     * null when they can't be read. Never throws, like history().
     */
    public function gateSessions(string $patientUid): ?array
    {
        try {
            return $this->progress->allSessions($patientUid);
        } catch (FirebaseException $e) {
            Log::warning('clearances.sessions_unreadable', ['patient' => $patientUid, 'error' => $e->getMessage()]);

            return null;
        }
    }

    /**
     * The gate recomputed from fresh reads, for the sign-off POST. Throws on
     * a Firebase failure: if any input can't be read, nothing is signed.
     */
    public function currentGate(string $patientUid): array
    {
        [$prescriptions, $sessions, $profile] = $this->db->concurrently([
            fn () => $this->prescriptions->forPatient($patientUid),
            fn () => $this->progress->allSessions($patientUid),
            fn () => $this->profiles->read($patientUid),
        ]);

        return ClearanceGate::evaluate($prescriptions, $sessions, $profile['restrictedExercises']);
    }

    /**
     * Write one clearance record (append-only) with the gate snapshot. A
     * `cleared` decision also adds a "progress" entry on the app's
     * Notifications page in the same commit, then pushes best-effort after
     * the commit: a failed push is logged and never undoes the record.
     *
     * The caller has already refused `cleared` for an incomplete gate.
     *
     * @return string the new record id
     */
    public function record(StaffUser $by, array $patient, array $data, array $gate): string
    {
        $id = FirestoreClient::newId();
        $decision = $data['decision'];
        $physician = trim((string) $data['physician_name']);

        $writes = [
            $this->db->createWrite("patients/{$patient['uid']}/clearances/{$id}", [
                'decision' => $decision,
                'physicianName' => $physician,
                'physicianLicense' => trim((string) $data['physician_license']),
                'assessedAt' => CarbonImmutable::parse($data['assessed_at'], config('app.timezone'))->startOfDay(),
                'findings' => trim((string) $data['findings']),
                'recommendations' => trim((string) ($data['recommendations'] ?? '')),
                'attested' => true,
                'programComplete' => $gate['state'] === ClearanceGate::READY_FOR_REVIEW,
                'requirements' => ClearanceGate::snapshot($gate),
                'signedBy' => $by->id,
                'signedByName' => $by->name,
            ], serverTimestamps: ['signedAt']),
        ];

        $title = 'Medical clearance issued';
        $body = "{$physician} has signed your medical clearance after your final assessment. Your therapist will talk you through the next steps.";
        if ($decision === self::CLEARED) {
            $writes[] = $this->notifier->notificationWrite($patient['uid'], 'progress', $title, $body);
        }

        $this->db->commit($writes);

        Log::info('clearances.recorded', [
            'patient' => $patient['uid'],
            'record' => $id,
            'decision' => $decision,
            'programComplete' => $gate['state'] === ClearanceGate::READY_FOR_REVIEW,
            'by' => $by->id,
        ]);

        if ($decision === self::CLEARED) {
            // After the commit: the record is saved whatever happens to the push.
            try {
                $this->notifier->push($patient['uid'], $title, $body, ['type' => 'progress']);
            } catch (FirebaseException $e) {
                Log::warning('clearances.push_failed', ['patient' => $patient['uid'], 'record' => $id, 'error' => $e->getMessage()]);
            }
        }

        return $id;
    }

    /**
     * Raw clearance docs -> presented records, newest signedAt first. A doc
     * with an unknown decision is skipped (logged): showing it as either
     * decision would misreport the patient's status.
     */
    public static function newestFirst(array $docs): array
    {
        $records = [];
        foreach ($docs as $doc) {
            $record = self::present($doc);
            if ($record === null) {
                Log::warning('clearances.unknown_decision', ['path' => $doc['_path'] ?? null]);

                continue;
            }
            $records[] = $record;
        }

        usort($records, fn ($a, $b) => ($b['signedAt']?->getTimestamp() ?? 0) <=> ($a['signedAt']?->getTimestamp() ?? 0));

        return $records;
    }

    /** One clearance doc with every field coerced, or null if its decision is unknown. */
    private static function present(array $doc): ?array
    {
        $decision = $doc['decision'] ?? null;
        if (! is_string($decision) || ! array_key_exists($decision, self::DECISIONS)) {
            return null;
        }

        $requirements = [];
        foreach (is_array($doc['requirements'] ?? null) ? $doc['requirements'] : [] as $r) {
            if (! is_array($r)) {
                continue;
            }
            $type = is_string($r['exerciseType'] ?? null) ? $r['exerciseType'] : '';
            $requirements[] = [
                'prescriptionId' => is_string($r['prescriptionId'] ?? null) ? $r['prescriptionId'] : '',
                'exerciseType' => $type,
                'exerciseName' => ExerciseCatalog::name($type),
                'finished' => is_int($r['finished'] ?? null) ? max(0, $r['finished']) : 0,
                'required' => is_int($r['required'] ?? null) ? $r['required'] : null,
            ];
        }

        return [
            'id' => (string) $doc['_id'],
            'decision' => $decision,
            'physicianName' => self::text($doc['physicianName'] ?? null, 100),
            'physicianLicense' => self::text($doc['physicianLicense'] ?? null, 40),
            'assessedAt' => ($doc['assessedAt'] ?? null) instanceof CarbonImmutable ? $doc['assessedAt'] : null,
            'findings' => self::text($doc['findings'] ?? null, 2000),
            'recommendations' => self::text($doc['recommendations'] ?? null, 1000),
            'programComplete' => ($doc['programComplete'] ?? false) === true,
            'requirements' => $requirements,
            'signedByName' => self::text($doc['signedByName'] ?? null, 100),
            'signedAt' => ($doc['signedAt'] ?? null) instanceof CarbonImmutable ? $doc['signedAt'] : null,
        ];
    }

    private static function text(mixed $value, int $max): string
    {
        return is_string($value) ? mb_substr($value, 0, $max) : '';
    }
}
