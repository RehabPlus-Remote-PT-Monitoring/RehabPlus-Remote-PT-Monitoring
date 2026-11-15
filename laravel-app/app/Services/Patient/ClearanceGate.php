<?php

namespace App\Services\Patient;

/**
 * The exercise completion gate (API_CONTRACT.md "Clinical safeguards",
 * design doc 2026-11-15-clinical-safeguards-design.md section 3).
 *
 * Pure logic, no Firebase: the Flutter app re-implements exactly the same
 * rules (lib/services/care_gate.dart) and both sides are tested against the
 * same cases, so keep this class free of I/O and keep the cases in
 * tests/Unit/ClearanceGateTest.php in sync with the app's tests.
 *
 * Rules:
 *   - only ACTIVE prescriptions count; stopped ones are ignored
 *   - a prescription's "finished" count = sessions whose prescriptionId is the
 *     prescription's id and that were not ended early
 *   - a prescription is complete when it has a requiredSessions target and
 *     finished >= requiredSessions (no target = can never be complete)
 *   - an active prescription for a restricted exercise always blocks
 *   - no active prescription at all = no_program (nothing to complete)
 *
 * The gate is only an input for the physician. It never clears a patient:
 * medical clearance is a separate, signed record (ClearanceService).
 */
class ClearanceGate
{
    /** No active prescription: there is no program to complete. */
    public const NO_PROGRAM = 'no_program';

    /** At least one active prescription is incomplete or restricted. */
    public const IN_PROGRESS = 'in_progress';

    /** Every active prescription is complete and none is restricted. */
    public const READY_FOR_REVIEW = 'ready_for_review';

    /** Why a requirement is not met yet. */
    public const REASON_NO_TARGET = 'no_target';

    public const REASON_NOT_ENOUGH = 'not_enough';

    public const REASON_RESTRICTED = 'restricted';

    /**
     * Evaluate the gate.
     *
     * @param  array<int, array>  $prescriptions  presented prescriptions
     *                                            (PrescriptionService::present: id, exerciseType, exerciseName, active, requiredSessions)
     * @param  array<int, array>  $sessions  presented sessions
     *                                       (PatientProgress::presentSession: prescriptionId, endedEarly)
     * @param  string[]  $restrictedExercises  exercise type codes the clinician restricted
     * @return array{state: string, requirements: array<int, array{prescriptionId: string, exerciseType: string, exerciseName: string, finished: int, required: ?int, restricted: bool, complete: bool, reason: ?string}>, missing: array<int, array>}
     */
    public static function evaluate(array $prescriptions, array $sessions, array $restrictedExercises): array
    {
        $finishedByPrescription = self::finishedCounts($sessions);
        $requirements = [];

        foreach ($prescriptions as $rx) {
            if (($rx['active'] ?? false) !== true) {
                continue;
            }

            $id = (string) ($rx['id'] ?? '');
            $type = (string) ($rx['exerciseType'] ?? '');
            $required = self::requiredSessions($rx['requiredSessions'] ?? null);
            $finished = $finishedByPrescription[$id] ?? 0;
            $restricted = in_array($type, $restrictedExercises, true);

            // Restricted wins over everything else: even a met target must
            // not let the program count as complete while the clinician
            // has said the patient must not do this exercise.
            $reason = match (true) {
                $restricted => self::REASON_RESTRICTED,
                $required === null => self::REASON_NO_TARGET,
                $finished < $required => self::REASON_NOT_ENOUGH,
                default => null,
            };

            $requirements[] = [
                'prescriptionId' => $id,
                'exerciseType' => $type,
                'exerciseName' => (string) ($rx['exerciseName'] ?? ExerciseCatalog::name($type)),
                'finished' => $finished,
                'required' => $required,
                'restricted' => $restricted,
                'complete' => $reason === null,
                'reason' => $reason,
            ];
        }

        $missing = array_values(array_filter($requirements, fn (array $r) => ! $r['complete']));

        $state = match (true) {
            $requirements === [] => self::NO_PROGRAM,
            $missing !== [] => self::IN_PROGRESS,
            default => self::READY_FOR_REVIEW,
        };

        return ['state' => $state, 'requirements' => $requirements, 'missing' => $missing];
    }

    /**
     * The snapshot stored on a clearance record (contract field
     * `requirements`): {prescriptionId, exerciseType, finished, required}.
     *
     * @return array<int, array{prescriptionId: string, exerciseType: string, finished: int, required: ?int}>
     */
    public static function snapshot(array $gate): array
    {
        return array_map(fn (array $r) => [
            'prescriptionId' => $r['prescriptionId'],
            'exerciseType' => $r['exerciseType'],
            'finished' => $r['finished'],
            'required' => $r['required'],
        ], $gate['requirements']);
    }

    /** One line per missing requirement, for the page and for error messages. */
    public static function describe(array $requirement): string
    {
        return match ($requirement['reason']) {
            self::REASON_RESTRICTED => "{$requirement['exerciseName']}: restricted by clinician, adjust the program",
            self::REASON_NO_TARGET => "{$requirement['exerciseName']}: no completion target set",
            self::REASON_NOT_ENOUGH => "{$requirement['exerciseName']}: {$requirement['finished']}/{$requirement['required']} sessions finished",
            default => "{$requirement['exerciseName']}: complete",
        };
    }

    /**
     * Finished (not ended early) sessions per prescription id. Sessions with
     * no prescriptionId (free practice) count for nothing.
     *
     * @return array<string, int>
     */
    private static function finishedCounts(array $sessions): array
    {
        $counts = [];
        foreach ($sessions as $session) {
            $prescriptionId = $session['prescriptionId'] ?? null;
            if (! is_string($prescriptionId) || $prescriptionId === '' || ($session['endedEarly'] ?? false) !== false) {
                continue;
            }
            $counts[$prescriptionId] = ($counts[$prescriptionId] ?? 0) + 1;
        }

        return $counts;
    }

    /** A usable target (1-500), or null for "no completion target set". */
    private static function requiredSessions(mixed $value): ?int
    {
        return is_int($value) && $value >= 1 && $value <= 500 ? $value : null;
    }
}
