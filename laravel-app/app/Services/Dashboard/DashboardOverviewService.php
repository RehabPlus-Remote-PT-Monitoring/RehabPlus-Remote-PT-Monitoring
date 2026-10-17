<?php

namespace App\Services\Dashboard;

use App\Auth\StaffUser;
use App\Services\Patient\PatientProgress;
use App\Services\Patient\PatientService;

class DashboardOverviewService
{
    public function __construct(private PatientService $patients, private PatientProgress $progress)
    {
    }

    /**
     * Stat cards, recovery chart and condition chart data for the dashboard and
     * analytics pages, from the sessions patients record in the app. Therapists
     * see their own patients; admins and staff the whole clinic.
     */
    public function overview(StaffUser $user): array
    {
        $patients = $this->patients->visible($user);
        $sessionsByPatient = $this->progress->sessionsByPatient();

        $patientStats = array_map(function (array $patient) use ($sessionsByPatient) {
            $stats = PatientProgress::stats($sessionsByPatient[$patient['uid']] ?? []);

            return [
                'id' => $patient['uid'],
                'name' => $patient['name'],
                'condition' => $patient['condition'] ?: 'Unspecified',
                'total_sessions' => $stats['total'],
                'compliance_rate' => $stats['accuracy'],
                'avg_pain' => $stats['avgPain'],
                // Movement accuracy minus a pain penalty, kept in 0-100.
                'recovery_score' => $stats['total'] ? max(0, min(100, round($stats['accuracy'] - $stats['avgPain'] * 5, 1))) : 0,
                'last_session_at' => $stats['lastSessionAt'],
            ];
        }, $patients);

        $withSessions = array_values(array_filter($patientStats, fn (array $p): bool => $p['total_sessions'] > 0));
        $count = count($withSessions);

        $conditionCounts = [];
        foreach ($patientStats as $patient) {
            $conditionCounts[$patient['condition']] = ($conditionCounts[$patient['condition']] ?? 0) + 1;
        }

        return [
            'patientStats' => $patientStats,
            'totalPatients' => count($patients),
            'avgCompliance' => $count ? round(array_sum(array_column($withSessions, 'compliance_rate')) / $count, 1) : 0,
            'avgPain' => $count ? round(array_sum(array_column($withSessions, 'avg_pain')) / $count, 1) : 0,
            'hasRecoveryData' => $count > 0,
            'recoveryLabels' => array_column($patientStats, 'name'),
            'recoveryValues' => array_map(fn (array $p): float => (float) $p['recovery_score'], $patientStats),
            'conditionCounts' => $conditionCounts,
        ];
    }
}
