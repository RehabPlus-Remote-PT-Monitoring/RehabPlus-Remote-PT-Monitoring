<?php

namespace App\Services\Patient;

use App\Services\Firebase\FirestoreClient;
use Carbon\CarbonImmutable;

/**
 * Exercise sessions the app uploads (patients/{uid}/sessions, read-only for
 * the dashboard) and the progress metrics from API_CONTRACT.md:
 * adherence, movement accuracy, pain, incomplete and unscheduled sessions.
 */
class PatientProgress
{
    /** Rep counts above this are treated as corrupt (the app clamps at the same value). */
    public const MAX_COUNT = 10000;

    public function __construct(private FirestoreClient $db)
    {
    }

    /** One patient's most recent sessions, newest first. */
    public function sessions(string $patientUid, int $limit = 100): array
    {
        $docs = $this->db->query("patients/{$patientUid}", 'sessions', orderBy: ['startTime', 'DESCENDING'], limit: $limit);

        return array_map(fn ($d) => self::presentSession($d), $docs);
    }

    /**
     * Sessions grouped by patient uid (newest first).
     *
     * Without $patientUids: every patient's sessions in one collection-group
     * read; callers drop patients the user can't see. With $patientUids: one
     * read per patient, in parallel, so only those patients' sessions are
     * fetched (used for therapists).
     *
     * @param  string[]|null  $patientUids
     * @return array<string, array>
     */
    public function sessionsByPatient(?array $patientUids = null): array
    {
        if ($patientUids === null) {
            $docs = $this->db->query('', 'sessions', allDescendants: true);
        } else {
            $tasks = [];
            foreach ($patientUids as $uid) {
                $tasks[] = fn () => $this->db->query("patients/{$uid}", 'sessions');
            }
            $docs = $tasks === [] ? [] : array_merge(...$this->db->concurrently($tasks));
        }

        $grouped = [];
        foreach ($docs as $doc) {
            $session = self::presentSession($doc);
            $grouped[$session['patientUid']][] = $session;
        }
        foreach ($grouped as &$sessions) {
            usort($sessions, fn ($a, $b) => ($b['startTime']?->getTimestamp() ?? 0) <=> ($a['startTime']?->getTimestamp() ?? 0));
        }

        return $grouped;
    }

    /**
     * Dashboard shape of one session document.
     *
     * Sessions are written by the patient's own phone, so every field is
     * treated as untrusted: each one is coerced to the type the views expect
     * (a map where text is expected would otherwise crash the page for every
     * staff member) and counts/scores are clamped to sane ranges.
     */
    public static function presentSession(array $doc): array
    {
        $compliance = self::number($doc['overallCompliance'] ?? null);
        $exerciseId = self::text($doc['exerciseId'] ?? null, 100);
        $startTime = ($doc['startTime'] ?? null) instanceof CarbonImmutable ? $doc['startTime']
            : (($doc['createdAt'] ?? null) instanceof CarbonImmutable ? $doc['createdAt'] : null);
        $pain = self::number($doc['painLevel'] ?? null);

        return [
            'id' => $doc['_id'],
            'patientUid' => explode('/', $doc['_path'])[1] ?? null,
            'exerciseId' => $exerciseId,
            'exerciseName' => self::text($doc['exerciseName'] ?? null, 100) ?? ExerciseCatalog::name($exerciseId),
            'prescriptionId' => self::text($doc['prescriptionId'] ?? null, 128),
            'startTime' => $startTime,
            'completedReps' => self::count($doc['completedReps'] ?? null),
            'rejectedReps' => self::count($doc['rejectedReps'] ?? null),
            'targetReps' => self::count($doc['targetReps'] ?? null),
            'accuracy' => $compliance === null ? null : round(max(0.0, min(1.0, $compliance)) * 100, 1),
            'painLevel' => $pain === null ? null : (int) max(0, min(10, $pain)),
            'painNote' => self::text($doc['painNote'] ?? null, 300),
            'endedEarly' => ($doc['endedEarly'] ?? false) === true,
            'outsideSchedule' => ($doc['outsideSchedule'] ?? false) === true,
        ];
    }

    private static function number(mixed $v): ?float
    {
        return is_int($v) || (is_float($v) && is_finite($v)) ? (float) $v : null;
    }

    private static function count(mixed $v): int
    {
        $n = self::number($v);

        return $n === null ? 0 : (int) max(0, min(self::MAX_COUNT, $n));
    }

    /** Non-empty text, cut to $max characters; anything else is null. */
    private static function text(mixed $v, int $max): ?string
    {
        return is_string($v) && $v !== '' ? mb_substr($v, 0, $max) : null;
    }

    /**
     * Headline numbers for a set of sessions.
     *
     * @return array{total: int, completed: int, accuracy: float, avgPain: float, endedEarly: int, outsideSchedule: int, lastSessionAt: ?CarbonImmutable}
     */
    public static function stats(array $sessions): array
    {
        $accuracies = array_filter(array_column($sessions, 'accuracy'), fn ($v) => $v !== null);
        $pains = array_filter(array_column($sessions, 'painLevel'), fn ($v) => $v !== null);

        return [
            'total' => count($sessions),
            'completed' => count(array_filter($sessions, fn ($s) => ! $s['endedEarly'])),
            'accuracy' => $accuracies ? round(array_sum($accuracies) / count($accuracies), 1) : 0.0,
            'avgPain' => $pains ? round(array_sum($pains) / count($pains), 1) : 0.0,
            'endedEarly' => count(array_filter($sessions, fn ($s) => $s['endedEarly'])),
            'outsideSchedule' => count(array_filter($sessions, fn ($s) => $s['outsideSchedule'])),
            'lastSessionAt' => $sessions[0]['startTime'] ?? null,
        ];
    }

    /**
     * This week's adherence per active prescription: completed sessions in the
     * last 7 days / frequencyPerWeek (capped at 100%).
     *
     * @return array{perPrescription: array<string, array{done: int, target: int, percent: int}>, overall: ?int}
     */
    public static function adherence(array $sessions, array $prescriptions, ?CarbonImmutable $now = null): array
    {
        $since = ($now ?? CarbonImmutable::now())->subDays(7);
        $per = [];

        foreach ($prescriptions as $rx) {
            if (! $rx['active']) {
                continue;
            }
            $done = count(array_filter($sessions, fn ($s) => $s['prescriptionId'] === $rx['id']
                && ! $s['endedEarly'] && $s['startTime'] && $s['startTime']->greaterThanOrEqualTo($since)));
            $target = max(1, $rx['frequencyPerWeek']);
            $per[$rx['id']] = ['done' => $done, 'target' => $target, 'percent' => (int) min(100, round($done / $target * 100))];
        }

        return [
            'perPrescription' => $per,
            'overall' => $per ? (int) round(array_sum(array_column($per, 'percent')) / count($per)) : null,
        ];
    }

    /**
     * Average pain per day for the last $days days (null when no session that day).
     *
     * @return array<int, array{date: CarbonImmutable, pain: ?float}>
     */
    public static function painTrend(array $sessions, int $days = 14, ?CarbonImmutable $now = null): array
    {
        $today = ($now ?? CarbonImmutable::now())->setTimezone(config('app.timezone'))->startOfDay();
        $byDay = [];
        foreach ($sessions as $s) {
            if ($s['startTime'] && $s['painLevel'] !== null) {
                $byDay[$s['startTime']->setTimezone(config('app.timezone'))->format('Y-m-d')][] = $s['painLevel'];
            }
        }

        $trend = [];
        for ($i = $days - 1; $i >= 0; $i--) {
            $day = $today->subDays($i);
            $values = $byDay[$day->format('Y-m-d')] ?? [];
            $trend[] = ['date' => $day, 'pain' => $values ? round(array_sum($values) / count($values), 1) : null];
        }

        return $trend;
    }
}
